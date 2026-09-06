#!/usr/bin/env -S -u RUBYOPT -u RUBYLIB -u RUBYGEMS_GEMDEPS -u BUNDLE_GEMFILE -u BUNDLE_PATH -u BUNDLE_BIN_PATH -u GEM_HOME -u GEM_PATH /usr/bin/ruby
# frozen_string_literal: true

# Find and backfill official websites for spots missing one, using only
# official APIs (no search-engine scraping, no browser spoofing):
#
# - Nominatim (OpenStreetMap): free, no key, accurate for well-known spots
# - Foursquare Places API: needs FOURSQUARE_API_KEY in .env / env
#
# Usage:
#   ruby bin/backfill_websites.rb              # all missing
#   ruby bin/backfill_websites.rb melbourne    # one city
#   ruby bin/backfill_websites.rb --dry-run melbourne  # print hits, write nothing (still calls the APIs)
#
# Resume via .website-progress. ~1.2s between requests (Nominatim's polite rate).
# Provider adapters (Nominatim/Foursquare) live in website_sources.rb.

require_relative 'pipeline_common'
require_relative 'website_sources'
require 'set'

BACKFILL_WEBSITES_PROGRESS = File.join(ROOT, '.website-progress')
# Phase 1 (Foursquare batch) resume marker, keyed PER SPOT via spot_progress_key
# (`name|city`, the same shape as .website-progress). A per-city marker would
# permanently skip a city that later gains a new spot — that spot would never get
# a batch. Keying per spot means a batch is re-issued whenever any pending spot is
# unmarked, so new spots are covered.
FOURSQUARE_PROGRESS = File.join(ROOT, '.foursquare-progress')

# Skip the crawl when nearly every spot already has a website: a full
# Nominatim/Foursquare pass (rate-limited, ~1.2s per request) isn't worth it
# for a handful of stragglers — coverage is already ~100%.
MIN_MISSING_TO_CRAWL = 20

# Words that never identify a specific restaurant's domain.
STOPWORDS = %w[
  the and of for a an restaurant bar cafe grill house kitchen table lounge
  express garden fresh market japanese sashimi sake ramen noodle bistro dining
].freeze

# Generic sushi-world words that appear in nearly every sushi domain, so they
# can't distinguish one restaurant from another (biansushi.co.nz vs sushiedo
# .com.au both contain "sushi").
GENERIC_TOKENS = %w[sushi omakase izakaya robata teppanyaki hibachi].freeze

# Distinctive words from a restaurant name — strip stopwords, generic sushi
# words, and short words (< 3 chars). "Sushi Edo" -> ["edo"], "Osushi" ->
# ["osushi"], "Minamishima" -> ["minamishima"], "L.A Sushi" -> [].
def distinctive_tokens(name)
  name.to_s.downcase.gsub(/[^a-z0-9\s]/, ' ').split
      .reject { |word| word.length < 3 }
      .reject { |word| STOPWORDS.include?(word) }
      .reject { |word| GENERIC_TOKENS.include?(word) }
end

# One spot's Nominatim website search, shaped like search_yelp for injection:
# nil on a hard failure, [] when the request succeeded but no spot yielded a
# usable host, [host, ...] otherwise (first host wins). The host extraction
# lives here — not in the website_sources adapters — so the caller can tell
# a failed request (nil) from a clean miss ([]); that distinction decides
# whether a spot is recorded as permanently tried.
def search_website_hosts(name, city)
  # The caller consumes only `hosts.first` below, so one result is enough — a
  # limit of 3 fetched two extra results that were never used. Fewer bytes per
  # call, same match.
  places = nominatim_search("#{name} #{city}", limit: 1)
  return nil unless places

  places.filter_map do |place|
    website = (place['extratags'] || {})['website'].to_s
    next if website.empty?

    clean_host(website)
  end
end

# A spot's website counts as missing when the field is absent or an empty
# string. One predicate shared by the missing-count and both fill phases, so a
# spot persisted with `"website": ""` is treated identically everywhere — Ruby's
# "" is truthy, so a bare `entry['website']` would read an empty string as
# already filled, leaving the spot counted missing yet never filled.
def website_missing?(entry)
  entry['website'].to_s.empty?
end

# Enumerable of [entry, index] pairs for one city's Foursquare batch — the
# missing-website, named spots the batch resolves. Shared by the dry-run counter
# and the Phase 1 loop so the two can't drift.
def missing_website_entries(entries)
  entries.each_with_index.select { |entry, _idx| website_missing?(entry) && entry['name'] }
end

# True when a Foursquare batch should be issued for one city: at least one spot
# is missing and not every missing spot's `name|city` key is already marked in
# .foursquare-progress. Keying per spot (not per city) means a NEW spot in a
# previously-batched city still re-issues its batch.
def batch_needed?(pending, city_key, foursquare_done)
  return false if pending.empty?

  pending.any? { |entry, _idx| !foursquare_done.include?(spot_progress_key(entry['name'], city_key)) }
end

# Enumerable of [entry, tokens, key] for the spots Phase 2 (Nominatim fallback)
# searches from one file — missing website, named, with a distinctive token (a
# purely-CJK name yields none and is unmatchable), and not already marked tried.
# Shared by the dry-run counter and the Phase 2 loop so the two can't drift.
def nominatim_eligible(entries, city_key, done)
  entries.filter_map do |entry|
    next unless website_missing?(entry) && entry['name']

    tokens = distinctive_tokens(entry['name'])
    next if tokens.empty?

    key = spot_progress_key(entry['name'], city_key)
    next if done.include?(key)

    [entry, tokens, key]
  end
end

# The Nominatim query string for one spot — the spot's name disambiguated by its
# file-stem city key (the canonical city). Shared by the dry-run call count and
# the Phase 2 loop so the counted query and the issued query are the identical
# string, and therefore memoize together.
def nominatim_query(entry, city_key)
  "#{entry['name']} #{city_key}"
end

# ---- main ----
# Count the calls a dry run expects before any request is issued, so a "check
# first" run sees its cost up front. A dry run still fetches: Phase 1 calls the
# Foursquare batch API and Phase 2 calls Nominatim per spot. The Foursquare
# count is the number of city batches — each batch may page up to
# FOURSQUARE_MAX_PAGES, so the real request count depends on the results.
def count_dry_run_calls(file_data:, foursquare_done:, done:)
  batch_calls = 0
  file_data.each do |filename, record|
    city_key = city_key_for(filename)
    next unless CITIES.dig(city_key, :center) && foursquare_api_key

    batch_calls += 1 if batch_needed?(missing_website_entries(record[:entries]), city_key, foursquare_done)
  end
  print_distinct_units_estimate(
    file_data.keys, dedup_across_files: true,
    summary: ->(nominatim_calls) { "#{batch_calls} Foursquare city batch(es), #{nominatim_calls} Nominatim search(es)" }
  ) do |filename|
    record = file_data[filename]
    city_key = city_key_for(filename)
    nominatim_eligible(record[:entries], city_key, done).map do |entry, _tokens, _key|
      nominatim_query(entry, city_key)
    end
  end
end

# Phase 1 — batch Foursquare per city (one call resolves ~50 spots). Mutates the
# shared `state[:filled]` tally; returns nothing. The caller gates this on
# `foursquare_api_key`.
def foursquare_phase(file_data:, foursquare_done:, foursquare_progress_path:, dry_run:, sleeper:, failures:, state:)
  foursquare_progress_file = open_progress(foursquare_progress_path, dry_run: dry_run)
  need_sleep = false
  file_data.each do |filename, record|
    city_key = city_key_for(filename)
    center = CITIES.dig(city_key, :center)
    next unless center

    pending = missing_website_entries(record[:entries])
    next unless batch_needed?(pending, city_key, foursquare_done)

    # Per-spot resume keys (`name|city`), mirroring .website-progress.
    pending_keys = pending.map { |entry, _idx| spot_progress_key(entry['name'], city_key) }

    # Pace only when a previous batch actually ran — the sleep after the final
    # batch (the trailing pause before Phase 2) is dropped.
    need_sleep = defer_sleep(sleeper, FOURSQUARE_SLEEP, need_sleep)

    # normalized_name => entry index, built once so each batch hit resolves
    # in O(1) instead of re-normalizing every candidate inside the loop.
    # `||=` keeps first-wins semantics when two entries share a normalized
    # name: a Foursquare result carries one website per place, so it can only
    # resolve one of two same-named spots, and filling every duplicate with
    # that host would misattribute it. The unmatched duplicate stays missing
    # and is handled by Phase 2's per-spot Nominatim fallback. Its key is
    # still marked by the wholesale append_progress below — safe, because the
    # batch is one call for the whole city (every pending spot in it was
    # attempted together) and a re-issued batch could never resolve the
    # duplicate either.
    pending_by_name = pending.each_with_object({}) do |(entry, idx), map|
      normalized = normalized_name_or_nil(entry['name'])
      map[normalized] ||= idx if normalized
    end

    pending_names = pending_by_name.keys.to_set
    batch = guard_result(failures, foursquare_batch(center, pending_names), 'foursquare_batch')
    next unless batch

    changed = false
    batch.each do |normalized, host|
      idx = pending_by_name[normalized]
      next unless idx

      entry = record[:entries][idx]
      next unless website_missing?(entry)

      puts "  #{entry['name']} (#{city_key}) -> #{host}"
      unless dry_run
        entry['website'] = "https://#{host}"
        changed = true
      end
      state[:filled] += 1
    end
    # One write per city per phase: mutating in the loop and writing once after
    # keeps the file on disk a single rewrite instead of one full rewrite per
    # filled spot.
    write_atomic(record[:path], record[:entries]) if changed
    # Persist-then-mark: only a non-nil batch records the attempted keys (an
    # empty {} is a success and IS marked, matching .website-progress). nil is
    # never recorded, so a transient outage retries instead of a permanent
    # skip. The marking is wholesale — every pending key, matched or not —
    # because a batch is one call for the whole city, so every pending spot in
    # it was attempted together.
    append_progress(foursquare_progress_file, pending_keys)
    need_sleep = true
  end
  close_progress(foursquare_progress_file)
end

# Phase 2 — Nominatim fallback for spots the batch missed. Per-run query dedup
# lives in the shared cached_query (two spots sharing the same name+city issue
# the identical Nominatim search). Mutates the shared `state` filled/
# skipped_empty/errored tallies; returns nothing.
def nominatim_phase(search_provider:, file_data:, done:, progress_file:, dry_run:, sleeper:, failures:, state:)
  # Per-run query dedup: two spots sharing the same name+city issue the identical
  # Nominatim search, so memoize by the exact request string — a cache hit skips
  # both the request and its rate-limit sleep. Local to this run, so it never
  # leaks between runs.
  query_cache = {}
  file_data.each do |filename, record|
    city_key = city_key_for(filename)
    changed = false
    tried_keys = []
    nominatim_eligible(record[:entries], city_key, done).each do |entry, tokens, key|
      # A cached identical query reuses the result and skips the request AND its
      # rate-limit sleep — the sleep fires once per real request, never on a
      # cache hit.
      query = nominatim_query(entry, city_key)
      hosts = cached_query(query_cache, query) do
        result = search_provider.call(entry['name'], city_key)
        sleeper.call(NOMINATIM_SLEEP)
        result
      end

      hosts = guard_result(failures, hosts, 'nominatim')
      if hosts.nil?
        state[:errored] += 1
        next
      end

      host = hosts.first
      # Require the domain to echo a distinctive name token.
      host = nil if host && !tokens.any? { |token| host.include?(token) }

      if host
        puts "  #{entry['name']} (#{city_key}) -> #{host}"
        unless dry_run
          entry['website'] = "https://#{host}"
          changed = true
        end
        state[:filled] += 1
      else
        state[:skipped_empty] += 1
      end
      tried_keys << key
    end
    persist_then_mark(changed, record[:path], record[:entries], progress_file, tried_keys)
  end
end

# Backfill official websites for spots missing one. `search_provider` is the
# per-spot Nominatim search (nil | [] | [host]); `data_dir`/`progress_path`
# isolate every file read/write; `sleeper` lets tests suppress the real
# rate-limit pauses. Defaults keep the CLI path identical to before.
def backfill_websites(search_provider: method(:search_website_hosts), data_dir: DATA_DIR,
                      progress_path: BACKFILL_WEBSITES_PROGRESS,
                      foursquare_progress_path: FOURSQUARE_PROGRESS, city_arg: nil,
                      dry_run: false, sleeper: ->(secs) { sleep(secs) })
  done = load_progress_with_resume(progress_path)
  foursquare_done = load_progress(foursquare_progress_path)

  files = data_filenames(data_dir)
  files = select_city_files(files, city_arg)

  missing = 0
  untried_missing = 0
  file_data = {}

  files.each do |filename|
    path = File.join(data_dir, filename)
    entries = load_jsonl(path)
    file_data[filename] = { path: path, entries: entries }
    city_key = city_key_for(filename)

    # Reuse missing_website_entries' "named + missing website" definition (shared
    # with the Phase 1/2 loops and the dry-run counter) so the three notions of
    # "pending" can't drift. `missing` counts them all; `untried_missing` counts
    # only those not already marked tried in `done` (the same keyed check
    # nominatim_eligible applies).
    pending = missing_website_entries(entries)
    missing += pending.size
    untried_missing += pending.count { |entry, _idx| !done.include?(spot_progress_key(entry['name'], city_key)) }
  end

  puts "#{missing} entries missing website"

  # The crawl is worth it only when enough UNTRIED spots are missing: `done`
  # (already-tried keys) would no-op here — Phase 1 skips fully-marked cities,
  # Phase 2 skips each marked key — so counting raw `missing` would re-run a
  # no-op crawl after a failed pass. `untried_missing` counts only missing
  # spots whose `name|city` key is absent from `done`; subtracting `done.size`
  # would under-count, because `done` also holds keys for spots that were
  # filled and are therefore no longer missing (a newly added spot would be
  # skipped forever once `done.size > missing`). The raw count is still
  # printed above.
  if untried_missing < MIN_MISSING_TO_CRAWL && !dry_run
    puts "Only #{untried_missing} untried missing — skipping crawl (below MIN_MISSING_TO_CRAWL=#{MIN_MISSING_TO_CRAWL})."
    return { filled: 0, skipped_empty: 0, errored: 0 }
  end

  # Shared mutable run state the phases accumulate.
  state = { filled: 0, skipped_empty: 0, errored: 0 }
  failures = build_failure_guard(
    warn_text: ->(source) { "#{source}: hard failure" },
    abort_text: ->(source) { "#{source} hard failures (rate limit or network)." }
  )
  progress_file = open_progress(progress_path, dry_run: dry_run)

  count_dry_run_calls(file_data: file_data, foursquare_done: foursquare_done, done: done) if dry_run

  # Phase 1 — batch Foursquare per city (one call resolves ~50 spots).
  foursquare_phase(file_data: file_data, foursquare_done: foursquare_done,
                   foursquare_progress_path: foursquare_progress_path, dry_run: dry_run,
                   sleeper: sleeper, failures: failures, state: state) if foursquare_api_key

  # Phase 2 — Nominatim fallback for spots the batch missed.
  nominatim_phase(search_provider: search_provider, file_data: file_data, done: done,
                  progress_file: progress_file, dry_run: dry_run, sleeper: sleeper,
                  failures: failures, state: state)

  close_progress(progress_file)
  # A dry run is not free: Phase 1 still calls the Foursquare batch API and
  # Phase 2 still calls Nominatim per spot (the startup warning above states the
  # expected call count), so the suffix makes clear nothing reached disk.
  puts "\nDone: filled #{state[:filled]} websites, #{state[:skipped_empty]} skipped (no result), " \
       "#{state[:errored]} errored#{dry_run ? DRY_RUN_SUFFIX : ''}"
  { filled: state[:filled], skipped_empty: state[:skipped_empty], errored: state[:errored] }
end

if __FILE__ == $PROGRAM_NAME
  flags = parse_common_flags(ARGV, supported: %w[--dry-run --help -h])
  if flags.help
    print_usage('backfill_websites.rb',
                'Find and backfill official websites for spots missing one.',
                [['--dry-run', 'Print hits, write nothing (still calls the APIs).']],
                '[city]')
    exit 0
  end
  result = backfill_websites(city_arg: flags.city, dry_run: flags.dry_run)
  # A run that errored on something and filled nothing is a failure; a genuine
  # partial success (some filled, some errored) still exits 0.
  exit 1 if result[:errored].positive? && result[:filled].zero?
end
