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
#   ruby bin/backfill_websites.rb --dry-run melbourne  # print hits, write nothing
#
# Resume via .website-progress. ~1.2s between requests (Nominatim's polite rate).
# Provider adapters (Nominatim/Foursquare) live in website_sources.rb.

require_relative 'pipeline_common'
require_relative 'website_sources'
require 'set'

BACKFILL_WEBSITES_PROGRESS = File.join(ROOT, '.website-progress')

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

# ---- main ----
if __FILE__ == $PROGRAM_NAME
  dry_run = ARGV.delete('--dry-run')
  city_arg = ARGV[0]

  done = load_progress(BACKFILL_WEBSITES_PROGRESS)
  puts "Resuming: #{done.size} spots already tried" unless done.empty?

  files = Dir.glob(File.join(DATA_DIR, '*.jsonl')).map { |path| File.basename(path) }.sort
  files = select_city_files(files, city_arg)

  missing = 0
  file_data = {}

  files.each do |filename|
    path = File.join(DATA_DIR, filename)
    entries = load_jsonl(path)
    file_data[filename] = { path: path, entries: entries }
    entries.each { |entry| missing += 1 if entry && !entry['website'] && entry['name'] }
  end

  puts "#{missing} entries missing website"

  if missing < MIN_MISSING_TO_CRAWL && !dry_run
    puts "Only #{missing} missing — skipping crawl (coverage already ~100%)."
    exit 0
  end

  filled = 0
  progress_file = dry_run ? nil : File.open(BACKFILL_WEBSITES_PROGRESS, 'a')

  # Phase 1 — batch Foursquare per city (one call resolves ~50 spots).
  if foursquare_api_key
    file_data.each do |filename, record|
      city_key = filename.sub(/\.jsonl\z/, '')
      center = city_center(city_key)
      next unless center

      pending = record[:entries].each_with_index.select do |entry, _i|
        entry && !entry['website'] && entry['name']
      end
      next if pending.empty?

      # normalized_name => entry index, built once so each batch hit resolves
      # in O(1) instead of re-normalizing every candidate inside the loop.
      # `||=` keeps first-wins semantics when two entries share a normalized name.
      pending_by_name = pending.each_with_object({}) do |(entry, idx), map|
        map[normalize_name(entry['name'])] ||= idx
      end

      pending_names = pending_by_name.keys.to_set
      batch = foursquare_batch(center, pending_names)
      next if batch.empty?

      changed = false
      batch.each do |normalized, host|
        idx = pending_by_name[normalized]
        next unless idx

        entry = record[:entries][idx]
        next if entry['website']

        puts "  [batch] #{entry['name']} (#{city_key}) -> #{host}"
        unless dry_run
          entry['website'] = "https://#{host}"
          changed = true
        end
        filled += 1
      end
      # One write per city per phase: mutating in the loop and writing once after
      # keeps the file on disk a single rewrite instead of one full rewrite per
      # filled spot.
      write_atomic(record[:path], record[:entries]) if changed
      sleep(NOMINATIM_SLEEP)
    end
  end

  # Phase 2 — Nominatim fallback for spots the batch missed.
  file_data.each do |filename, record|
    city_key = filename.sub(/\.jsonl\z/, '')
    changed = false
    tried_keys = []
    record[:entries].each do |entry|
      next unless entry && !entry['website'] && entry['name']

      key = "#{entry['name']}|#{city_key}"
      next if done.include?(key)

      # Disambiguate the Nominatim query with the file-stem city key (the
      # canonical city).
      host = nominatim_fetch(entry['name'], city_key)
      # Require the domain to echo a distinctive name token.
      tokens = distinctive_tokens(entry['name'])
      host = nil if host && !tokens.empty? && !tokens.any? { |token| host.include?(token) }

      if host && !host.empty?
        puts "  #{entry['name']} (#{city_key}) -> #{host}"
        unless dry_run
          entry['website'] = "https://#{host}"
          changed = true
        end
        filled += 1
      end
      tried_keys << key
      sleep(NOMINATIM_SLEEP)
    end
    # Persist the city's file BEFORE recording its spots as tried: a crash in
    # between then leaves unwritten fills unmarked, so the next run retries them
    # instead of skipping spots whose website never reached disk. The reverse
    # order (mark first, write later) was the bug.
    write_atomic(record[:path], record[:entries]) if changed
    unless tried_keys.empty?
      progress_file&.write(tried_keys.join("\n") + "\n")
      progress_file&.flush
    end
  end

  progress_file&.close
  puts "\nDone: filled #{filled} websites"
end
