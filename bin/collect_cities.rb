#!/usr/bin/env -S -u RUBYOPT -u RUBYLIB -u RUBYGEMS_GEMDEPS -u BUNDLE_GEMFILE -u BUNDLE_PATH -u BUNDLE_BIN_PATH -u GEM_HOME -u GEM_PATH /usr/bin/ruby
# frozen_string_literal: true

# Collect omakase restaurant data from the Yelp Fusion API for new cities.
#
# Usage:
#   echo "YELP_API_KEY=your-key" > .env
#   ruby bin/collect_cities.rb          # first run
#   ruby bin/collect_cities.rb          # resume after abort (skips done cities)
#
# - Resume via `.fetch-progress` — re-running skips completed cities.
# - Retries with backoff on transient errors (YELP_MAX_ATTEMPTS attempts, in
#   yelp_client.rb).
# - One query per city: "omakase" + sushi category, capped at our YELP_MAX_PAGES
#   pages of YELP_PAGE_SIZE results (our collection cap, defined below).
# - Dedup by (name.strip.downcase, city_key) already in data/*.jsonl.

require_relative 'pipeline_common'
require 'fileutils'
require 'set'

FETCH_PROGRESS = File.join(ROOT, '.fetch-progress')

# Reject Yelp hits that belong to a *neighbouring* metro area (e.g. NYC results
# bleeding into a Philadelphia query): Yelp's `location=` is a region, not a
# strict city, so without this guard a big omakase city can pollute a small one.
# Spots farther than this (km) from the city center (CITIES[:center] in
# cities.rb) are treated as a different metro area and dropped. 70 km keeps
# genuine suburbs (Atlanta's Sandy Springs, ~20 km) while rejecting cross-metro
# pollution (NYC into Philly, ~130 km).
# Distinct from pipeline_common's MAX_CENTER_KM (250, the wrong-city/region
# implausibility threshold for geocoded points): this is the collection-time
# metro guard, not the geocode sanity bound.
COLLECT_RADIUS_KM = 70

# Cap first-time collection at YELP_MAX_PAGES pages of YELP_PAGE_SIZE results per
# city (100 max). This is a deliberate cost cap, not Yelp's own limit:
# refresh_yelp_fields.rb's bulk pass pages up to offset 1000 — its
# YELP_SEARCH_MAX_OFFSET, i.e. 20 pages of 50 — not 5 pages. Two pages seeds a
# new city; the full window is never needed for first collection. YELP_PAGE_SIZE
# lives in yelp_client.rb so the two pagination loops can't drift apart.
YELP_MAX_PAGES = 2

# Pause between cities so a full run doesn't hammer Yelp back-to-back across the
# whole collectable set.
INTER_CITY_SLEEP = 1.5

# Terms that disqualify a Yelp hit as a non-omakase neighbour (grocery, ramen,
# food truck, ...). Matched against the lowercased name and category aliases.
#
# `buffet` is deliberately NOT a reject term: a buffet host is an AYCE signal per
# the kind policy (spot-utils.js), so a sushi buffet must be collected rather
# than dropped here. A non-sushi buffet still fails the sushi/omakase/Japanese
# guard below.
REJECT_TERMS = [
  'grocery', 'supermarket', 'convenience', 'fast food',
  'food truck', 'food stand', 'pop-up', 'meal delivery', 'catering',
  'poke', 'hot dogs', 'chinese', 'korean', 'thai', 'vietnamese',
  'noodle', 'ramen', 'bubble tea', 'ice cream', 'dessert',
  'cooking class', 'culinary school', 'meal prep'
].freeze

def within_city?(city_key, business)
  center = CITIES.dig(city_key, :center)
  return true unless center

  coords = business['coordinates'] || {}
  lat = coords['latitude']
  lon = coords['longitude']
  return true unless lat && lon

  haversine_km(center[0], center[1], lat, lon) <= COLLECT_RADIUS_KM
end

# True when a Yelp business is a relevant omakase/sushi hit: its name or
# category mentions sushi/omakase/Japanese cuisine, and no reject term matches.
# `'japane'` is a deliberate prefix for Yelp's "japanese" category alias (also
# covering "japanesecurry" etc.), not a typo for "japanese".
def relevant_omakase_business?(business)
  name = (business['name'] || '').downcase
  category_text = (business['categories'] || []).map { |c| c['alias'] }.join(' ')
  return false if REJECT_TERMS.any? { |term| name.include?(term) || category_text.include?(term) }

  category_text.include?('sushi') || category_text.include?('japane') ||
    name.include?('omakase') || name.include?('sushi')
end

def business_to_entry(business, currency)
  location = business['location'] || {}
  latitude, longitude = rounded_coordinates(business)

  entry = {
    'name' => business['name'],
    'currency' => currency,
    'address' => location['address1'].to_s,
    'yelp_id' => business['id'].to_s,
    'yelp_rating' => business['rating'],
    'yelp_review_count' => business['review_count'],
    'yelp_price_level' => business['price'].to_s,
    'yelp_url' => canonical_yelp_url(business['url']).to_s
  }
  entry['lat'] = latitude if latitude
  entry['lon'] = longitude if longitude

  # Write the fields refresh_yelp_fields would otherwise re-fetch, so a
  # first-collected spot is already complete. fill_yelp_fields! mirrors the same
  # YELP_FILL_MAP source paths + transforms, guards each with fill_if_absent!
  # (nil/""/[] count as absent), and applies is_closed the same way merge_yelp!
  # does. `phone` is filled here (not written directly above) so collection and
  # refresh agree on the display_phone || raw-phone fallback. The 6-key subset is
  # the fields a fresh entry does not already set above.
  fill_yelp_fields!(entry, business, keys: %w[image_url transactions region_code country display_address phone])

  # Drop blank values the direct writes above left ("" address/url/price/id, a
  # nil rating/name). Only nil/"" survive to here — fill_if_absent! already
  # dropped []/{} for the mapped fields and the direct writes are String/nil — so
  # this predicate narrows to exactly what can reach it; blank_value?'s
  # empty-collection arm would be dead here.
  entry.delete_if { |_k, v| v.nil? || v == '' }
  entry
end

# Canonical dedup identity for a spot: its stripped, lowercased name plus the
# city key. Two entries/businesses with the same identity are the same spot.
#
# Deliberately a different normalization from jsonl.rb's normalize_name: this is
# exact-name dedup that keeps punctuation and spaces, whereas normalize_name is
# the fuzzy match key that strips non-alphanumerics. So "Sushi-Saito" is a
# distinct identity here but collapses onto "Sushi Saito" under normalize_name.
# `name.to_s` guards the nil name relevant_omakase_business? tolerates
# (`business['name'] || ''`), so a nameless Yelp hit degrades to an empty-string
# identity instead of raising NoMethodError.
def dedup_key(name, city)
  [name.to_s.strip.downcase, city]
end

def load_existing_keys(data_dir = DATA_DIR)
  existing = Set.new
  data_filenames(data_dir).each do |filename|
    path = File.join(data_dir, filename)
    city = city_key_for(filename)
    load_jsonl(path).each do |entry|
      existing.add(dedup_key(entry['name'], city))
    end
  end
  existing
end

# ---- main ----
# Collect every not-yet-collected city in `cities`, resuming from `progress_path`.
# Collaborators are injected so the orchestration is testable off-network:
# `search` is the Yelp client (a stub can be passed), `data_dir`/`progress_path`
# isolate every file read/write to a temp dir, and `sleeper` lets tests suppress
# the real rate-limit pauses. Defaults keep the CLI path identical to before.
def collect_cities(search: method(:search_yelp), data_dir: DATA_DIR,
                   progress_path: FETCH_PROGRESS, cities: COLLECTABLE_CITIES,
                   dry_run: false, sleeper: ->(secs) { sleep(secs) })
  done = load_progress(progress_path)
  skipped = cities.keys.select { |c| done.include?(c) }
  puts "Skipping #{skipped.size} already-completed cities: #{skipped.sort.join(', ')}" unless skipped.empty?

  existing = load_existing_keys(data_dir)
  total = 0
  incomplete_cities = 0

  cities.each do |city_key, city|
    next if done.include?(city_key)

    path = File.join(data_dir, "#{city_key}.jsonl")
    location = city[:location]
    currency = city[:currency]
    print "\n#{city_key} (#{location}): "

    seen_ids = Set.new
    new_entries = []
    aborted = false

    begin
      YELP_MAX_PAGES.times do |page|
        results = search.call('term' => 'omakase', 'categories' => 'sushi',
                              'location' => location, 'limit' => YELP_PAGE_SIZE, 'offset' => page * YELP_PAGE_SIZE,
                              'sort_by' => 'best_match')
        if results.nil? # hard failure (429 exhausted, bad key, ...) — stop this city
          aborted = true
          break
        end

        results.each do |business|
          business_id = business['id'].to_s
          next if business_id.empty? || seen_ids.include?(business_id) || !relevant_omakase_business?(business)
          next unless within_city?(city_key, business)

          seen_ids.add(business_id)
          key = dedup_key(business['name'], city_key)
          next if existing.include?(key)

          new_entries << business_to_entry(business, currency)
          existing.add(key)
        end
        break if results.size < YELP_PAGE_SIZE
        # Pace the next page only — the final request of a city (a short page or
        # the last allowed page) is not followed by another, so its sleep is
        # skipped; the inter-city pause below still separates the cities.
        sleeper.call(YELP_SLEEP) if page < YELP_MAX_PAGES - 1
      end
    rescue LocationNotFound
      # Yelp cannot resolve this city's location string at all — city-level,
      # deterministic, and permanent, so retrying its pages can never succeed.
      # Warn once (naming the city and the location string) and skip the rest of
      # this city's pages, spending only the one call already made. Not marked
      # done, matching the nil/aborted path's "future run resumes it" semantics.
      warn_unresolvable_city(city_key, location)
      aborted = true
    end

    if new_entries.any?
      # A dry run still fetches and counts, but writes nothing: both this data
      # write (and its mkdir) and the progress mark below are skipped, so a
      # "safe preview" run leaves disk and resume state untouched.
      unless dry_run
        FileUtils.mkdir_p(data_dir)
        # Re-write the file sorted (existing + new) instead of appending, so the
        # on-disk name order the rest of the repo relies on stays intact.
        existing_entries = File.exist?(path) ? load_jsonl(path) : []
        merged = existing_entries + new_entries
        sort_entries!(merged)
        write_atomic(path, merged)
      end
      puts "#{new_entries.size} new entries"
      total += new_entries.size
    else
      puts '0 new entries'
    end

    # Mark the city done only when every page request actually completed. A
    # hard failure (nil) leaves it unrecorded so a future run resumes it
    # instead of silently skipping a city that collected nothing. A dry run
    # never records progress, so a later real run re-collects the city.
    if aborted
      puts "#{city_key} incomplete — not marking done"
      incomplete_cities += 1
    else
      mark_progress(progress_path, [city_key]) unless dry_run
    end
    # Sleep unconditionally between processed cities. Gating this on the table
    # index was wrong: the loop skips already-done cities, so the sleep could be
    # skipped after a city that was not the last one actually processed. The
    # trailing pause after the final city is harmless.
    sleeper.call(INTER_CITY_SLEEP)
  end

  puts "\nTotal: #{total} new entries"
  puts 'Next: ruby tests/validate_data.rb && omarchy-shell omakase refresh' if total.positive?
  # An aborted city is a failed run for a shell/CI caller, so carry the count
  # out for the CLI block below (the function still returns the entry count).
  @incomplete_cities = incomplete_cities
  total
end

if __FILE__ == $PROGRAM_NAME
  flags = parse_common_flags(ARGV, supported: %w[--dry-run --help -h])
  if flags.help
    print_usage('collect_cities.rb',
                'Collect omakase restaurant data from the Yelp Fusion API for new cities.',
                [])
    exit 0
  end
  collect_cities(dry_run: flags.dry_run)
  exit 1 if @incomplete_cities.to_i.positive?
end
