#!/usr/bin/env -S -u RUBYOPT -u RUBYLIB -u RUBYGEMS_GEMDEPS -u BUNDLE_GEMFILE -u BUNDLE_PATH -u BUNDLE_BIN_PATH -u GEM_HOME -u GEM_PATH /usr/bin/ruby
# frozen_string_literal: true

# Require hub for the data pipeline: pulls in the city table (cities.rb), the
# JSONL/progress IO (jsonl.rb), and the Yelp client (yelp_client.rb), then
# defines the small shared helpers — project paths, env-key loading, URL
# normalization, fill-missing Yelp fields (fill_if_absent!/YELP_FILL_MAP/
# fill_yelp_fields!) and the rounded-coordinate extractor (rounded_coordinates),
# haversine distance and the coordinate/street-token lists
# (implausible_from_center?/MAX_CENTER_KM/coarse_coord?, STREET_*), the on-disk
# sort key, the shared progress keys + token sanitizer (spot_progress_key/
# geocode_progress_key/sanitize_progress_token), the dry-run unit counter,
# estimate printer, and run summary (count_distinct_units/
# print_distinct_units_estimate/print_dry_run_estimate/print_run_summary/
# DRY_RUN_SUFFIX), the per-run query-cache memo (cached_query), the
# deferred rate-limit sleep (defer_sleep), the consecutive-failure abort guard
# (build_failure_guard/ConsecutiveFailureGuard) plus the shared nil-vs-empty
# check (guard_result) and unresolvable-city warn (warn_unresolvable_city), and
# the shared CLI flag parser + usage printer (parse_common_flags/CommonFlags,
# print_usage) — that don't warrant a file of their own.

ROOT = File.expand_path('..', __dir__)
DATA_DIR = File.join(ROOT, 'data')
ENV_FILE = File.join(ROOT, '.env')

$stdout.sync = true

require 'uri'
require_relative 'cities'
require_relative 'jsonl'
require_relative 'yelp_client'

# Look up `name` in the environment, then fall back to a `NAME=value` line in
# the .env file at `path` (defaults to the gitignored project .env; the
# argument is for tests). Returns nil when neither source has it. An unreadable
# .env (mode 000, wrong owner) degrades to nil exactly like a missing one, but
# warns once with the OS cause instead of raising out of File.foreach and
# crashing the pipeline. Only SystemCallError is rescued — a programming error
# still propagates.
def load_env_key(name, path = ENV_FILE)
  key = ENV[name]
  return key if key

  return nil unless File.exist?(path)

  File.foreach(path) do |line|
    return line.strip.split('=', 2)[1].strip.gsub(/\A["']|["']\z/, '') if line.strip.start_with?("#{name}=")
  end
  nil
rescue SystemCallError => e
  warn "load_env_key: cannot read #{path}: #{e.message}"
  nil
end

# Strip Yelp's analytics query string (`?adjust_creative=...&utm_...`) from a
# business URL, keeping the base https://www.yelp.com/biz/<slug> link the Yelp
# button and Yelp's display terms require. The provider-supplied URL is
# untrusted, so this write boundary also validates it: only an https:// link on
# a yelp host (yelp.com or a subdomain of it) survives, and anything else — a
# javascript:/file: scheme, a foreign host, or a malformed URL — is dropped
# (nil) rather than persisted for the widget to have to defend against.
# Non-strings pass through unchanged.
def canonical_yelp_url(url)
  return url unless url.is_a?(String)

  base = url.split('?', 2).first
  uri = URI.parse(base)
  host = uri.host.to_s.downcase
  return nil unless uri.scheme == 'https' && (host == 'yelp.com' || host.end_with?('.yelp.com'))

  base
rescue URI::InvalidURIError
  nil
end

# Shared blank-value predicate: nil, "", [], or {} count as blank. `nil?` covers
# nil; `respond_to?(:empty?) && empty?` covers every empty collection uniformly,
# so an empty hash counts as blank too, not just the documented [] gotcha: an
# empty array/hash is valid JSON but means "no data", so it must not count as a
# value (otherwise `[].to_s == "[]"` would mark the field as set). Shared by
# fill_if_absent! and collect_cities' write boundary so the two can't drift.
def blank_value?(value)
  value.nil? || (value.respond_to?(:empty?) && value.empty?)
end

# Fill `entry[key]` from `value` only when the key is absent AND the value is
# non-blank (blank_value?). Returns whether it wrote.
def fill_if_absent!(entry, key, value)
  return false if blank_value?(value) || entry.key?(key)

  entry[key] = value
  true
end

# Map entry key => { path:, transform: }, where `path` is the Yelp business JSON
# path (resolved with dig) and `transform` (optional) post-processes the resolved
# value: yelp_url drops Yelp's analytics query string, phone falls back to the raw
# `phone` field when `display_phone` is absent. The two fields this table can't
# express (boolean `is_closed`, rounded lat/lon) are handled elsewhere:
# `is_closed` in `fill_yelp_fields!`, lat/lon via `rounded_coordinates`.
# Named for the fill behaviour, not Yelp: several entry keys it fills (`address`,
# `region_code`, `country`, `display_address`, `phone`, `image_url`, `transactions`)
# are not `yelp_`-prefixed.
YELP_FILL_MAP = {
  'yelp_url' => { path: %w[url], transform: ->(_business, value) { canonical_yelp_url(value) } },
  'yelp_rating' => { path: %w[rating] },
  'yelp_review_count' => { path: %w[review_count] },
  'yelp_price_level' => { path: %w[price] },
  'yelp_id' => { path: %w[id] },
  'image_url' => { path: %w[image_url] },
  'phone' => { path: %w[display_phone], transform: ->(business, value) { value || business['phone'] } },
  'transactions' => { path: %w[transactions] },
  'address' => { path: %w[location address1] },
  'region_code' => { path: %w[location state] },
  'country' => { path: %w[location country] },
  'display_address' => { path: %w[location display_address] }
}.freeze

# Fill every `YELP_FILL_MAP` field named in `keys` into `entry` from `business`,
# then apply the `is_closed` boolean. Each fill resolves the row's Yelp value
# (`dig` walks the nested path nil-safely, then the optional transform
# post-processes it) and uses `fill_if_absent!` (never overwrites; nil/""/[]
# count as absent). `is_closed` is a boolean, so false is a valid value — key
# presence (not truthiness) decides whether Yelp reported it. Returns whether
# anything was written. `keys` defaults to the full map; collect_cities passes
# the subset it mirrors (the fields it pre-writes at collection time).
#
# The fill loop is `map` + `any?`, not `any?` with a block: the block form is
# lazy and would stop at the first filled field, leaving the rest unset.
def fill_yelp_fields!(entry, business, keys: YELP_FILL_MAP.keys)
  changed = keys.map do |key|
    spec = YELP_FILL_MAP.fetch(key)
    value = business.dig(*spec[:path])
    value = spec[:transform].call(business, value) if spec[:transform]
    fill_if_absent!(entry, key, value)
  end.any?

  if business.key?('is_closed') && !entry.key?('is_closed')
    entry['is_closed'] = business['is_closed']
    changed = true
  end

  changed
end

# Rounded [lat, lon] for one Yelp business's `coordinates`, or a slot's nil when
# that coordinate is absent. Each present coordinate is rounded to 6 decimals
# (the stored precision); a call site that needs both (merge_yelp!) tests
# `lat && lon`, while one that fills each independently (business_to_entry)
# writes only the present slot. Shared by the two Yelp fill sites so the
# coordinate rounding can't drift.
def rounded_coordinates(business)
  coordinates = business['coordinates'] || {}
  lat = coordinates['latitude']
  lon = coordinates['longitude']
  [lat && lat.round(6), lon && lon.round(6)]
end

# Great-circle distance in km between two (lat, lon) points. The single Ruby
# implementation; collect_cities' radius guard calls this (the JS copy lives in
# spot-utils.js for a different runtime).
def haversine_km(lat1, lon1, lat2, lon2)
  d_lat = (lat2 - lat1) * Math::PI / 180
  d_lon = (lon2 - lon1) * Math::PI / 180
  a = Math.sin(d_lat / 2)**2 +
      Math.cos(lat1 * Math::PI / 180) * Math.cos(lat2 * Math::PI / 180) *
      Math.sin(d_lon / 2)**2
  6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
end

# A geocoded point farther than this (km) from the city center is treated as a
# wrong-city/region result rather than a real spot: geocode_fallback.rb reports
# it as an implausible miss (never writes), reverse_geocode_addresses.rb skips
# it. Cities without a center in CITIES skip the check. Distinct from
# collect_cities' COLLECT_RADIUS_KM (70, the collection-time metro guard) — this
# is the geocode sanity bound, not the collect guard.
MAX_CENTER_KM = 250

# True when `lat`/`lon` lies implausibly far (> MAX_CENTER_KM) from the city
# center, i.e. a wrong-city/region geocode rather than a real spot. A nil center
# (a curated/country-level key with no center in CITIES) is never implausible —
# there is nothing to measure against, so the check is skipped. Shared by
# geocode_fallback.rb and reverse_geocode_addresses.rb so the threshold can't
# drift apart.
def implausible_from_center?(lat, lon, center)
  return false unless center

  haversine_km(lat, lon, center[0], center[1]) > MAX_CENTER_KM
end

# Abort after this many consecutive hard failures across all three crawlers
# (refresh_yelp_fields, backfill_websites, reverse_geocode_addresses): `nil`
# covers a rate limit that exhausted its retries, a missing/invalid key, a
# transport error, and a non-2xx alike, so a sustained run of them means the
# key/network is blocked. All three crawlers abort after the same number of
# consecutive hard failures, so one shared constant is honest. Fail loudly
# rather than hammering the API forever.
MAX_CONSECUTIVE_FAILURES = 8

# Count of digits after the decimal point in a stored coordinate. This assumes
# the value stringifies as a plain decimal: it splits on '.', so a scientific-
# notation form (e.g. "1.0e-05") would be counted from the exponent onward and
# mis-measure the fraction. Coordinates are stored as rounded floats
# (`round(6)`, e.g. 40.773812), which never stringify with an exponent, so the
# float-only assumption holds — documented rather than "fixed" because it is the
# algorithm's input contract.
def decimal_places(value)
  fraction = value.to_s.split('.')[1]
  fraction ? fraction.length : 0
end

# True when a coordinate is coarse enough to be a city-center fallback point —
# genuine geocodes carry 6 decimals, placeholders 4 or fewer.
def coarse_coord?(lat, lon)
  decimal_places(lat) <= 4 && decimal_places(lon) <= 4
end

# Street-token vocabulary, shared by the two data scripts that reason about
# addresses so the lists cannot drift. Two distinct purposes use it:
#
#   * reverse_geocode_addresses.rb compares a stored address against a geocoded
#     one, dropping street-type words (STREET_STOPWORDS) first so "Avenue" and
#     "Ave" match.
#   * normalize_locations.rb detects whether a value looks like a street
#     address rather than a neighborhood name (US_STREET_TYPES/EU_STREET_TYPES).
#
# STREET_TOKEN_BASE holds the Anglo street-type tokens both purposes agree on;
# each list below adds only what its own purpose (or region) needs.
STREET_TOKEN_BASE = %w[
  street st road rd avenue ave boulevard blvd drive dr lane ln way place pl
  court ct terrace ter square quay
].freeze

# Tokens dropped when comparing addresses that are not shared Anglo types:
# non-US street words a geocoder may return (rue, via, strasse, gade, kaj) and
# abbreviations that never distinguish one address from another.
STREET_STOPWORDS = (STREET_TOKEN_BASE + %w[rue via strasse str alley sq kaj gade]).freeze

# US/Anglo street-type markers beyond the shared base.
US_STREET_TYPES = (STREET_TOKEN_BASE + %w[hwy cres close grove mews esplanade]).freeze

# Latin/Germanic/Nordic street words that mark a European address; disjoint from
# the Anglo base, so this list stands on its own.
EU_STREET_TYPES = %w[
  via viale piazza corso calle carrer rua largo praceta plaza ronda rue gasse
  weg platz hovedgade vej
].freeze

# Deterministic on-disk sort key for a data/*.jsonl entry: name case-insensitively
# (locale-independent fold), tie-broken by lat then lon. Missing coordinates sort
# last (Infinity), so the order is total and reproducible regardless of Ruby's
# sort stability. `name` is always present in seed data, but `to_s` keeps the key
# total if it ever is absent.
def entry_sort_key(entry)
  lat = entry['lat']
  lon = entry['lon']
  [
    entry['name'].to_s.downcase,
    lat.nil? ? Float::INFINITY : lat.to_f,
    lon.nil? ? Float::INFINITY : lon.to_f
  ]
end

# Sort JSONL entries in place by entry_sort_key, so every file on disk shares the
# same order and a line reorder never churns git diffs.
def sort_entries!(entries)
  entries.sort_by! { |entry| entry_sort_key(entry) }
end

# Collapse a provider-supplied free-text token (a spot name or address) to a
# single line by replacing control characters (NUL–US and DEL) with a space. A
# hostile name carrying a newline would otherwise inject a spurious resume key
# into a progress file (corrupting resume state across runs), and ANSI/control
# characters would inject terminal escapes into the operator's log. Normal
# names carry no control characters, so they pass through byte-identical — the
# progress-key shape is unchanged for real data.
def sanitize_progress_token(value)
  value.to_s.gsub(/[\x00-\x1f\x7f]/, ' ')
end

# Resume key for one spot's coordinate in a Nominatim progress file — the unit of
# work is one specific coordinate for one specific spot, so the key is
# `city|name|lat,lon`. geocode_fallback.rb (.geocode-progress) and
# reverse_geocode_addresses.rb (.reverse-geocode-progress) key their files the
# same way, so this lives here to keep the two from drifting.
def geocode_progress_key(city_key, name, lat, lon)
  "#{city_key}|#{sanitize_progress_token(name)}|#{lat},#{lon}"
end

# Resume key for one spot in a per-spot progress file: `name|city_key`. Shared by
# backfill_websites (.website-progress / .foursquare-progress) and
# refresh_yelp_fields (.yelp-refresh-progress), whose on-disk key shapes are
# identical — keying the spot by name plus its city keeps two same-named spots in
# different cities from colliding within a file.
def spot_progress_key(name, city_key)
  "#{sanitize_progress_token(name)}|#{city_key}"
end

# Count the distinct API-call units a pipeline run would issue, so a dry-run
# pre-count cannot drift from the loop that issues the requests. `filenames` is
# the data basenames; for each, the `units_by_file` block yields the dedup key
# of every unit the run would issue from that file (the same eligibility and
# dedup-key logic the run's loop applies). Keys are deduped across the whole run
# when `dedup_across_files` is true — the query-cache crawlers (backfill_websites'
# Phase 2, geocode_fallback) memoize one query string across every file — and
# per-file otherwise (reverse_geocode_addresses groups each file's coordinates
# independently, so a coordinate shared by two cities issues two calls). Returns
# the distinct count.
def count_distinct_units(filenames, dedup_across_files:, &units_by_file)
  seen = {}
  count = 0
  filenames.each do |filename|
    seen = {} unless dedup_across_files
    units_by_file.call(filename).each do |key|
      next if seen.key?(key)

      seen[key] = true
      count += 1
    end
  end
  count
end

# Print the dry-run expected-call estimate line, shared by the three crawlers
# that pre-count their provider calls before issuing them (backfill_websites,
# geocode_fallback, reverse_geocode_addresses). `summary` carries the count
# phrase(s) (the noun and the count — two phrases for backfill_websites' two
# providers); `provider` names what the run still calls, defaulting to the
# generic "the APIs" for the two-provider backfill run.
def print_dry_run_estimate(summary, provider: 'the APIs')
  puts "Dry run: still calls #{provider} (nothing is written) — #{summary}."
end

# Suffix appended to a summary line to say that, while the provider calls still
# happened, nothing reached disk. One shared constant so the crawlers can't
# drift (reverse_geocode_addresses once used a shorter ' (dry run)' that
# understated that fetches still happened).
DRY_RUN_SUFFIX = ' (dry run — nothing written)'

# Count the distinct provider-call units a dry run would issue and print the
# estimate, in one step shared by the three crawlers that pre-count
# (backfill_websites, geocode_fallback, reverse_geocode_addresses). `filenames`
# is the list of data basenames; `units_by_file` yields the dedup key of each
# unit from one file; `summary` builds the count phrase(s) from the distinct
# count. Only the unit-key expression differs between the three call sites.
def print_distinct_units_estimate(filenames, dedup_across_files:, summary:, provider: 'the APIs', &units_by_file)
  count = count_distinct_units(filenames, dedup_across_files: dedup_across_files, &units_by_file)
  print_dry_run_estimate(summary.call(count), provider: provider)
end

# Print the shared run-summary block (Filled / skipped / missed / errored /
# Changed) for geocode_fallback and reverse_geocode_addresses — the shape is
# identical, only the labels differ. `labels` carries the Filled noun and the
# ordered mid sections, each `{ heading:, key:, detail: }`; the value at
# `state[key]` is either an Integer count or an Array of detail lines (printed
# as a bullet list). The dry-run suffix appears once, on the Filled line.
def print_run_summary(state, file_count, dry_run:, labels:)
  puts "\nFilled: #{state[:filled]} #{labels[:filled]}#{dry_run ? DRY_RUN_SUFFIX : ''}"
  labels[:sections].each do |section|
    value = state[section[:key]]
    count = value.is_a?(Array) ? value.size : value
    puts "#{section[:heading]} (#{section[:detail]}): #{count}"
    value.each { |line| puts "  - #{line}" } if value.is_a?(Array)
  end
  puts "Changed #{state[:changed_files]} of #{file_count} files"
end

# A consecutive-hard-failure guard shared by the three crawlers. The counter
# resets on any success and aborts on the Nth consecutive hard failure, so a
# sustained run of nil results stops the crawl instead of hammering the API
# forever. Build one via build_failure_guard (below), which supplies the shared
# construction and lets each crawler pass only its message text.
class ConsecutiveFailureGuard
  def initialize(max:, abort_with:, warn_with: nil)
    @count = 0
    @max = max
    @abort_with = abort_with
    @warn_with = warn_with
  end

  # Record one hard failure: bump the counter, log via `warn_with` (if set),
  # then abort via `abort_with` once `max` consecutive failures have accrued.
  # Extra args pass through to both message builders.
  def note_failure(*context)
    @count += 1
    @warn_with&.call(@count, *context)
    @abort_with.call(@count, *context) if @count >= @max
  end

  def reset
    @count = 0
  end
end

# Build a ConsecutiveFailureGuard for one crawler. The three crawlers share the
# construction — max: MAX_CONSECUTIVE_FAILURES, an abort message prefixed with
# "\nAbort: N consecutive ", an optional warn message suffixed with
# "(N consecutive)" — and differ only in their message text and whether they
# warn. `abort_text`/`warn_text` carry that text: a String when the message is
# static (refresh_yelp_fields, reverse_geocode_addresses' abort), or a lambda of
# the note_failure context when it names a source/spot (backfill_websites,
# reverse_geocode_addresses' warn). A nil `warn_text` omits the warn
# (refresh_yelp_fields has none). A String is wrapped in a constant lambda at
# build time, so the failure call sites stay single-form. The built lambdas
# close over the importing script's own `abort`/`warn`, so the user-facing text
# stays script-local.
def build_failure_guard(abort_text:, warn_text: nil)
  # Normalize the message builders once here: a String becomes a constant lambda,
  # so the failure call sites below always `.call` instead of re-testing
  # `respond_to?(:call)` per failure. Distinct locals keep a wrapped String from
  # re-capturing the (now lambda) parameter.
  abort_builder = abort_text.respond_to?(:call) ? abort_text : ->(*) { abort_text }
  warn_builder = warn_text && (warn_text.respond_to?(:call) ? warn_text : ->(*) { warn_text })

  abort_with = lambda do |count, *context|
    abort "\nAbort: #{count} consecutive #{abort_builder.call(*context)}"
  end
  warn_with = warn_builder && lambda do |count, *context|
    warn "  #{warn_builder.call(*context)} (#{count} consecutive)"
  end
  ConsecutiveFailureGuard.new(max: MAX_CONSECUTIVE_FAILURES, abort_with: abort_with, warn_with: warn_with)
end

# Record one provider result against the shared failure guard: a nil result is a
# hard failure (note it with any context and return nil — never to be recorded
# as tried), while any non-nil result (even an empty []/{}) resets the guard and
# passes through. Shared by the four crawlers' call sites so the nil-vs-empty
# provider-adapter contract can't drift.
def guard_result(failures, result, *context)
  if result.nil?
    failures.note_failure(*context)
    return nil
  end

  failures.reset
  result
end

# Warn once for a city whose `location` string Yelp cannot resolve at all
# (LOCATION_NOT_FOUND) — city-level, deterministic, and permanent, so retrying
# can never succeed. Shared by the two Yelp crawlers so the exact warn text
# can't drift apart.
def warn_unresolvable_city(city_key, location)
  warn "  #{city_key}: Yelp could not resolve location #{location.inspect}; skipping city"
end

# Memoize one provider result per query string within a run: a cache hit returns
# the stored result, a miss yields to the block (which must issue the request AND
# its rate-limit sleep) and stores the returned value. Two spots sharing the
# identical query string (same name+city, or same address+city label) therefore
# issue one request, and the sleep fires once per real request, never on a cache
# hit. The cache is local to a run, so it never leaks between runs.
def cached_query(query_cache, query)
  return query_cache[query] if query_cache.key?(query)

  query_cache[query] = yield
end

# Defer a rate-limit sleep to the NEXT request, never the last: sleep `interval`
# only when a previous request is still awaiting its pause (`pending`), then
# report the flag cleared. The caller re-arms the flag after issuing the next
# request, so the pause after a run's final request is dropped while real
# requests stay >= interval apart. Stateless on purpose, so a caller keeps the
# flag inline (`flag = defer_sleep(sleeper, interval, flag)` before a request,
# `flag = true` after) whether it is a local or a hash slot.
def defer_sleep(sleeper, interval, pending)
  sleeper.call(interval) if pending
  false
end

# Parsed common CLI flags, returned by parse_common_flags. `city` is the first
# positional; `positionals` is the full positional list (sort_data is multi-city).
CommonFlags = Struct.new(:dry_run, :validate, :city, :help, :positionals)

# The four flags parse_common_flags recognizes; a caller narrows the set via
# `supported:` so a flag it does not honour (e.g. --validate) is rejected as
# unknown instead of being silently ignored.
SUPPORTED_COMMON_FLAGS = %w[--dry-run --validate --help -h].freeze

# Parse the shared CLI flags from `argv`: --dry-run, --validate, and --help/-h,
# leaving the first positional argument as `city` and the full list as
# `positionals`. The array is mutated in place to hold only the positional
# arguments; any other `--`-prefixed argument — or a recognized flag excluded
# from `supported:` — is rejected with one uniform message and exit 1, so a typo
# like `--dryrun` never silently becomes a city name. The flags are parsed but
# not interpreted here — each CLI decides which of the four it honours, and
# passes `supported:` to reject the rest.
def parse_common_flags(argv, supported: SUPPORTED_COMMON_FLAGS)
  dry_run = false
  validate = false
  help = false
  positionals = []

  argv.each do |arg|
    if arg.start_with?('--') && !supported.include?(arg)
      warn "Unknown option: #{arg}"
      exit 1
    end

    case arg
    when '--dry-run' then dry_run = true
    when '--validate' then validate = true
    when '--help', '-h' then help = true
    else
      positionals << arg
    end
  end

  argv.replace(positionals)
  CommonFlags.new(dry_run, validate, positionals.first, help, positionals)
end

# Print one bin script's usage in the uniform form every CLI's --help branch
# shares: a Usage line, a one-line description, then the option list (the shared
# --help/-h entry is appended here, so the scripts can't drift on it).
def print_usage(script, description, options, positional = nil)
  args = ['[options]', positional].compact.join(' ')
  puts "Usage: ruby bin/#{script} #{args}"
  puts
  puts "  #{description}"
  puts
  puts 'Options:'
  options.each { |flag, text| puts format('  %-14s %s', flag, text) }
  puts format('  %-14s %s', '--help, -h', 'Show this help.')
end
