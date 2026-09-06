#!/usr/bin/env -S -u RUBYOPT -u RUBYLIB -u RUBYGEMS_GEMDEPS -u BUNDLE_GEMFILE -u BUNDLE_PATH -u BUNDLE_BIN_PATH -u GEM_HOME -u GEM_PATH /usr/bin/ruby
# frozen_string_literal: true

# Replace city-center placeholder coordinates with real geocodes.
#
# The pipeline's radius guard only enforces a spot is within the city; spots it
# could not pin down share one fallback point (the city center), so many spots
# in one file report the exact same distance. This script finds every group of
# spots sharing one coarse coordinate and, for each spot
# with a street `address`, geocodes it with Nominatim (OpenStreetMap — free, no
# key) and writes the corrected `lat`/`lon` rounded to 6 decimals.
#
# A "placeholder" group is any set of 2+ entries sharing the same (lat, lon)
# where both values are coarse — 4 or fewer decimal places, or missing
# entirely (a nil coordinate has 0 decimal places, so it is coarse too). The
# city-center fallbacks are coarse, while genuine co-locations (two
# restaurants in one building) were geocoded to full 6-decimal precision;
# coordinate-less entries group under [nil, nil] and are geocoded from their
# address. Spots with no `address` (or where Nominatim misses) are reported,
# never guessed.
#
# Usage:
#   ruby bin/geocode_fallback.rb            # geocode all placeholders
#   ruby bin/geocode_fallback.rb --dry-run  # print the plan, write nothing (still calls Nominatim)
#
# Resumes via .geocode-progress. ~1.2s between requests (Nominatim's polite
# rate), matching backfill_websites.

require_relative 'pipeline_common'
require_relative 'website_sources'

GEOCODE_PROGRESS = File.join(ROOT, '.geocode-progress')

# City string appended to a street address to disambiguate the Nominatim query.
# CITIES[:name] is the display name; curated/country-level keys fall back to the
# Yelp `location` string (e.g. australia -> "Sydney, Australia").
#
# Deliberately targets Yelp's `location` string (CITIES[:name] /
# CITIES[:location]), NOT the JS `cityLabelFor` display name in catalog-utils.js.
# The two look interchangeable but are not: Nominatim needs a geocodable place
# string, so "unifying" them against the JS display-name helper would regress
# the query. The explicit name guards against that cleanup.
def nominatim_city_query(city_key)
  CITIES.dig(city_key, :name) || CITIES.dig(city_key, :location) || city_key.tr('-', ' ').split.map(&:capitalize).join(' ')
end

# Default search provider: a one-result Nominatim search, because the geocoder
# consumes only `results.first`. It is a single-argument lambda (not
# `method(:nominatim_search)`) so the seam matches the one-argument
# `search_provider.call(query)` call site — the raw method binds the required
# `limit:` keyword and raises ArgumentError on the first placeholder.
NOMINATIM_SEARCH_PROVIDER = ->(query) { nominatim_search(query, limit: 1) }

# Placeholder groups: [lat, lon] => [entry, ...] for coordinates shared by 2+
# spots at coarse precision (4-or-fewer decimal places, or missing entirely).
# Coordinate-less entries group under [nil, nil]; coarse_coord?(nil, nil) is
# true (decimal_places(nil) is 0), so that group is a coarse placeholder and is
# geocoded from its address too.
def placeholder_groups(entries)
  entries.group_by { |e| [e['lat'], e['lon']] }
         .select { |(lat, lon), group| group.size > 1 && coarse_coord?(lat, lon) }
end

# True when an entry carries a non-blank street `address`. Shared by
# geocode_work_items and the address-less reporting loop below, so the
# "geocodable" and "reported as no-address" sets are exact complements.
def address_present?(entry)
  address = entry['address']
  address && !address.to_s.strip.empty?
end

# Enumerable of [entry, lat, lon, key] for every placeholder spot that has an
# address and is not yet marked tried — the exact set the crawl geocodes. Shared
# by the dry-run counter and the geocode loop so the two can't drift. Keys match
# .reverse-geocode-progress (city|name|lat,lon): the unit of work is one specific
# placeholder coordinate for one specific spot. `placeholders` is the
# placeholder_groups(entries) result, passed in so the group-by runs once per
# file rather than being recomputed by each caller.
def geocode_work_items(placeholders, city_key, done)
  placeholders.flat_map do |(lat, lon), group|
    group.filter_map do |entry|
      next unless address_present?(entry)

      key = geocode_progress_key(city_key, entry['name'], lat, lon)
      next if done.include?(key)

      [entry, lat, lon, key]
    end
  end
end

# One city file's geocode pass: report the address-less placeholder spots, then
# geocode the eligible remainder via the shared enumerable. Mutates the shared
# `state` (filled/no_address_entries/missed/errored/changed_files tallies) and
# the shared `query_cache` (per-run query dedup), and writes the file's data and
# progress via persist_then_mark. Returns nothing.
def geocode_file(path, city_key, search_provider:, done:, progress_file:, query_cache:, dry_run:, sleeper:, failures:, state:)
  entries = load_jsonl(path)

  placeholders = placeholder_groups(entries)
  return if placeholders.empty?

  center = CITIES.dig(city_key, :center)
  label = nominatim_city_query(city_key)
  changed = false
  tried_keys = []

  # Report address-less placeholder spots (they are never geocoded), then
  # geocode the eligible remainder via the shared enumerable.
  placeholders.each_value do |group|
    group.each do |entry|
      state[:no_address_entries] << "#{entry['name']} (#{city_key})" unless address_present?(entry)
    end
  end

  geocode_work_items(placeholders, city_key, done).each do |entry, lat, lon, key|
    query = "#{entry['address'].to_s.strip}, #{label}"
    results = cached_query(query_cache, query) do
      result = search_provider.call(query)
      sleeper.call(NOMINATIM_SLEEP)
      result
    end

    # Distinguish a hard failure (nil) from a clean miss ([]): the former is
    # an error worth surfacing separately and is never marked tried, the
    # latter is just "no result" and is recorded so a re-run skips it.
    results = guard_result(failures, results, entry['name'], city_key)
    if results.nil?
      state[:errored] << "#{entry['name']} (#{city_key}) - Nominatim error for #{query.inspect}"
      next
    end
    tried_keys << key
    if results.empty?
      state[:missed] << "#{entry['name']} (#{city_key}) - Nominatim miss for #{query.inspect}"
      next
    end

    new_coord = [results.first['lat'].to_f, results.first['lon'].to_f]

    if implausible_from_center?(new_coord[0], new_coord[1], center)
      km = haversine_km(new_coord[0], new_coord[1], center[0], center[1])
      state[:missed] << "#{entry['name']} (#{city_key}) - #{format('%.0f', km)} km from center, implausible"
      next
    end

    new_lat = new_coord[0].round(6)
    new_lon = new_coord[1].round(6)
    puts "  #{entry['name']} (#{city_key}): #{lat}, #{lon} -> #{new_lat}, #{new_lon}"
    unless dry_run
      entry['lat'] = new_lat
      entry['lon'] = new_lon
      changed = true
    end
    state[:filled] += 1
  end

  if persist_then_mark(changed, path, entries, progress_file, tried_keys)
    state[:changed_files] += 1
    puts "#{File.basename(path)}: geocoded"
  end
end

# Print the run summary and return the result hash (geocoded + the missed/errored
# counts). Reads the shared `state` built by the per-file step, so the report
# lives in one place.
def report_geocode_run(state, file_count, dry_run:)
  print_run_summary(state, file_count, dry_run: dry_run, labels: {
    filled: 'spots',
    sections: [
      { heading: 'Skipped', key: :no_address_entries, detail: 'no address' },
      { heading: 'Missed', key: :missed, detail: 'Nominatim miss / implausible' },
      { heading: 'Errored', key: :errored, detail: 'Nominatim request failed' }
    ]
  })

  { geocoded: state[:filled], missed: state[:missed].size, errored: state[:errored].size }
end

# ---- main ----
# Geocode placeholder coordinates by Nominatim search. Collaborators are
# injected so the orchestration is testable off-network: `search_provider` is
# the Nominatim search client (nil | [] | [result]), `data_dir`/`progress_path`
# isolate every file read/write, and `sleeper` lets tests suppress the real
# rate-limit pauses. Defaults keep the CLI path identical to before.
def geocode_fallback(search_provider: NOMINATIM_SEARCH_PROVIDER,
                     data_dir: DATA_DIR,
                     progress_path: GEOCODE_PROGRESS,
                     dry_run: false,
                     sleeper: ->(secs) { sleep(secs) })
  done = load_progress_with_resume(progress_path)

  files = data_filenames(data_dir)

  # Shared mutable run state the per-file step accumulates. Threaded as a hash so
  # one file's tallies accumulate across the whole run and the report reads one
  # place.
  state = { filled: 0, no_address_entries: [], missed: [], errored: [], changed_files: 0 }
  failures = build_failure_guard(
    warn_text: ->(name, city) { "#{name} (#{city}): geocode failed" },
    abort_text: 'geocode failures (rate limit or network).'
  )
  progress_file = open_progress(progress_path, dry_run: dry_run)
  # Per-run query dedup: two spots in one placeholder group sharing the same
  # address string would otherwise issue two identical Nominatim searches.
  query_cache = {}

  # A dry run still geocodes: every placeholder spot with an address issues a
  # Nominatim search. Count the distinct searches the run expects (deduped by
  # query string, matching the cache below) before any request, so a "check
  # first" run sees its cost up front.
  if dry_run
    print_distinct_units_estimate(
      files, dedup_across_files: true,
      summary: ->(count) { "#{count} search(es) expected" },
      provider: 'Nominatim'
    ) do |filename|
      path = File.join(data_dir, filename)
      city_key = city_key_for(filename)
      label = nominatim_city_query(city_key)
      geocode_work_items(placeholder_groups(load_jsonl(path)), city_key, done).map do |entry, _lat, _lon, _key|
        "#{entry['address'].to_s.strip}, #{label}"
      end
    end
  end

  files.each do |filename|
    path = File.join(data_dir, filename)
    city_key = city_key_for(filename)
    geocode_file(path, city_key, search_provider: search_provider, done: done,
                 progress_file: progress_file, query_cache: query_cache,
                 dry_run: dry_run, sleeper: sleeper, failures: failures,
                 state: state)
  end

  close_progress(progress_file)
  report_geocode_run(state, files.size, dry_run: dry_run)
end

if __FILE__ == $PROGRAM_NAME
  flags = parse_common_flags(ARGV, supported: %w[--dry-run --help -h])
  if flags.help
    print_usage('geocode_fallback.rb',
                'Replace city-center placeholder coordinates with real geocodes.',
                [['--dry-run', 'Print the plan, write nothing (still calls Nominatim).']])
    exit 0
  end
  result = geocode_fallback(dry_run: flags.dry_run)
  exit 1 if result[:errored].positive? && result[:geocoded].zero?
end
