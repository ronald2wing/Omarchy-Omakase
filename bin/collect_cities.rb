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
# - Retries 3x with backoff on transient errors.
# - One query per city: "omakase" + sushi category, YELP_MAX_PAGES pages of YELP_PAGE_SIZE results.
# - Dedup by (name.downcase, city_key) already in data/*.jsonl.

require_relative 'pipeline_common'
require 'fileutils'
require 'set'

COLLECT_CITIES_PROGRESS = File.join(ROOT, '.fetch-progress')

# Reject Yelp hits that belong to a *neighbouring* metro area (e.g. NYC results
# bleeding into a Philadelphia query): Yelp's `location=` is a region, not a
# strict city, so without this guard a big omakase city can pollute a small one.
# Spots farther than this (km) from the city center (CITIES[:center] in
# cities.rb) are treated as a different metro area and dropped. 70 km keeps
# genuine suburbs (Atlanta's Sandy Springs, ~20 km) while rejecting cross-metro
# pollution (NYC into Philly, ~130 km).
MAX_CITY_RADIUS_KM = 70

# Cap first-time collection at YELP_MAX_PAGES pages of YELP_PAGE_SIZE results per
# city (100 max). This is a deliberate cost cap, not Yelp's own limit: Yelp
# allows up to 50 pages (offset 0..1000), and refresh_yelp_fields.rb fetches up
# to 5 pages (250). Two pages seeds a new city; the full window is never needed
# for first collection. YELP_PAGE_SIZE lives in yelp_client.rb so the two
# pagination loops can't drift apart.
YELP_MAX_PAGES = 2

# Pause between cities so a full run doesn't hammer Yelp back-to-back across the
# whole collectable set.
INTER_CITY_SLEEP = 1.5

# Terms that disqualify a Yelp hit as a non-omakase neighbour (grocery, ramen,
# food truck, ...). Matched against the lowercased name and category aliases.
REJECT_TERMS = [
  'grocery', 'supermarket', 'convenience', 'fast food', 'buffet',
  'food truck', 'food stand', 'pop-up', 'meal delivery', 'catering',
  'poke', 'hot dogs', 'chinese', 'korean', 'thai', 'vietnamese',
  'noodle', 'ramen', 'bubble tea', 'ice cream', 'dessert',
  'cooking class', 'culinary school', 'meal prep'
].freeze

def within_city?(city_key, business)
  center = city_center(city_key)
  return true unless center

  coords = business['coordinates'] || {}
  lat = coords['latitude']
  lon = coords['longitude']
  return true unless lat && lon

  haversine_km(center[0], center[1], lat, lon) <= MAX_CITY_RADIUS_KM
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
  coordinates = business['coordinates'] || {}
  location = business['location'] || {}
  latitude = coordinates['latitude']
  longitude = coordinates['longitude']

  entry = {
    'name' => business['name'],
    'currency' => currency,
    'address' => location['address1'].to_s,
    'yelp_id' => business['id'].to_s,
    'yelp_rating' => business['rating'],
    'yelp_review_count' => business['review_count'],
    'yelp_price' => business['price'].to_s,
    'yelp_url' => canonical_yelp_url(business['url']).to_s
  }
  entry['lat'] = latitude.round(6) if latitude
  entry['lon'] = longitude.round(6) if longitude
  entry['phone'] = business['display_phone'] if business['display_phone'] && !business['display_phone'].to_s.empty?

  entry.delete_if { |_k, v| v == '' || v.nil? }
  entry
end

# Canonical dedup identity for a spot: its stripped, lowercased name plus the
# city key. Two entries/businesses with the same identity are the same spot.
def dedup_key(name, city)
  [name.strip.downcase, city]
end

def load_existing_keys(data_dir = DATA_DIR)
  existing = Set.new
  Dir.glob(File.join(data_dir, '*.jsonl')).each do |path|
    city = File.basename(path, '.jsonl')
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
                   progress_path: COLLECT_CITIES_PROGRESS, cities: COLLECTABLE_CITIES,
                   sleeper: ->(secs) { sleep(secs) })
  done = load_progress(progress_path)
  skipped = cities.keys.select { |c| done.include?(c) }
  puts "Skipping #{skipped.size} already-completed cities: #{skipped.sort.join(', ')}" unless skipped.empty?

  existing = load_existing_keys(data_dir)
  total = 0

  cities.each_with_index do |(city_key, city), index|
    next if done.include?(city_key)

    path = File.join(data_dir, "#{city_key}.jsonl")
    location = city[:location]
    currency = city[:currency]
    print "\n#{city_key} (#{location})... "

    seen_ids = Set.new
    new_entries = []
    aborted = false

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
      sleeper.call(YELP_SLEEP)
      break if results.size < YELP_PAGE_SIZE
    end

    if new_entries.any?
      FileUtils.mkdir_p(data_dir)
      # Re-write the file sorted (existing + new) instead of appending, so the
      # on-disk name order the rest of the repo relies on stays intact.
      existing_entries = File.exist?(path) ? load_jsonl(path) : []
      merged = existing_entries + new_entries
      sort_entries!(merged)
      write_atomic(path, merged)
      puts "#{new_entries.size} new"
      total += new_entries.size
    else
      puts '0 new'
    end

    # Mark the city done only when every page request actually completed. A
    # hard failure (nil) leaves it unrecorded so a future run resumes it
    # instead of silently skipping a city that collected nothing.
    if aborted
      puts "#{city_key} incomplete — not marking done"
    else
      File.open(progress_path, 'a') { |f| f.puts(city_key) }
    end
    sleeper.call(INTER_CITY_SLEEP) unless index == cities.size - 1
  end

  puts "\nTotal: #{total} new entries"
  puts 'Next: ruby tests/validate_data.rb && omarchy-shell omakase refresh' if total.positive?
  total
end

if __FILE__ == $PROGRAM_NAME
  collect_cities
end
