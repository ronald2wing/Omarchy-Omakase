#!/usr/bin/env ruby
# frozen_string_literal: true

# Collect omakase restaurant data from the Yelp Fusion API for new cities.
#
# Usage:
#   echo "YELP_API_KEY=your-key" > .env
#   ruby bin/collect_city.rb            # first run
#   ruby bin/collect_city.rb            # resume after abort (skips done cities)
#
# - Resume via `.fetch-progress` — re-running skips completed cities.
# - Retries 3x with backoff on transient errors.
# - One query per city: "omakase" + sushi category, MAX_PAGES pages of PAGE_SIZE results.
# - Dedup by (name.downcase, city_key) already in data/*.jsonl.

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
MAX_CITY_RADIUS_KM = 70

# Yelp's max `limit` per search call, and the number of pages fetched per city
# (100 results max, matching Yelp's own cap).
PAGE_SIZE = 50
MAX_PAGES = 2

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
    'neighborhood' => location['address1'].to_s,
    'source' => 'yelp',
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

def load_existing
  existing = Set.new
  Dir.glob(File.join(DATA_DIR, '*.jsonl')).each do |path|
    city = File.basename(path, '.jsonl')
    load_jsonl(path).each do |entry|
      existing.add(dedup_key(entry['name'], city))
    end
  end
  existing
end

# ---- main ----
if __FILE__ == $PROGRAM_NAME
  done = load_progress(FETCH_PROGRESS)
  skipped = COLLECTABLE_CITIES.keys.select { |c| done.include?(c) }
  puts "Skipping #{skipped.size} already-completed cities: #{skipped.sort.join(', ')}" unless skipped.empty?

  existing = load_existing
  total = 0

  COLLECTABLE_CITIES.each_with_index do |(city_key, city), index|
    next if done.include?(city_key)

    path = File.join(DATA_DIR, "#{city_key}.jsonl")
    location = city_location(city_key)
    currency = city[:currency]
    print "\n#{city_key} (#{location})... "

    seen_ids = Set.new
    new_entries = []

    MAX_PAGES.times do |page|
      results = search_yelp('term' => 'omakase', 'categories' => 'sushi',
                            'location' => location, 'limit' => PAGE_SIZE, 'offset' => page * PAGE_SIZE,
                            'sort_by' => 'best_match')
      break if results.nil? # hard 429 — stop this city, keep going

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
      sleep(YELP_SLEEP)
      break if results.size < PAGE_SIZE
    end

    if new_entries.any?
      FileUtils.mkdir_p(DATA_DIR)
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

    File.open(FETCH_PROGRESS, 'a') { |f| f.puts(city_key) }
    sleep(1.5) unless index == COLLECTABLE_CITIES.size - 1
  end

  puts "\nTotal: #{total} new entries"
  puts 'Next: ruby tests/validate_data.rb && omarchy-shell omakase refresh' if total.positive?
end
