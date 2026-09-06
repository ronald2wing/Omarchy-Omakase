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
# where both values carry 4 or fewer decimal places — the city-center fallbacks
# are coarse, while genuine co-locations (two restaurants in one building) were
# geocoded to full 6-decimal precision. Spots with no `address` (or where
# Nominatim misses) are reported, never guessed.
#
# Usage:
#   ruby bin/geocode_fallback.rb            # geocode all placeholders
#   ruby bin/geocode_fallback.rb --dry-run  # print the plan, write nothing
#
# ~1.2s between requests (Nominatim's polite rate), matching backfill_websites.

require_relative 'pipeline_common'
require_relative 'website_sources'

# A geocoded point farther than this (km) from the city center is treated as a
# miss rather than written — it is far more likely a wrong-country match than a
# real spot. Country-level keys (no center in CITIES) skip the check.
MAX_CENTER_KM = 250

# City label appended to a street address to disambiguate the Nominatim query.
# city_name is the display name; curated/country-level keys fall back to the
# Yelp `location` string via city_location (e.g. australia -> "Sydney, Australia").
def city_label(stem)
  city_name(stem) || city_location(stem) || stem.tr('-', ' ').split.map(&:capitalize).join(' ')
end

# Count of digits after the decimal point in a stored coordinate.
def decimal_places(value)
  fraction = value.to_s.split('.')[1]
  fraction ? fraction.length : 0
end

# True when a shared coordinate is coarse enough to be a fallback point.
def coarse_coord?(lat, lon)
  decimal_places(lat) <= 4 && decimal_places(lon) <= 4
end

# Geocode one query string with Nominatim, returning [lat, lon] floats or nil.
def nominatim_geocode(query)
  results = nominatim_search(query, limit: 1)
  return nil if results.nil? || results.empty?

  first = results.first
  [first['lat'].to_f, first['lon'].to_f]
rescue StandardError => e
  warn "nominatim_geocode(#{query.inspect}): #{e.class}: #{e.message}"
  nil
end

# ---- main ----
if __FILE__ == $PROGRAM_NAME
  dry_run = ARGV.delete('--dry-run')
  files = Dir.glob(File.join(DATA_DIR, '*.jsonl')).sort

  geocoded = 0
  no_address = []
  missed = []
  changed_files = 0

  files.each do |path|
    filename = File.basename(path)
    stem = filename.sub(/\.jsonl\z/, '')
    entries = load_jsonl(path)

    placeholders = entries.compact.group_by { |e| [e['lat'], e['lon']] }
                          .select { |(lat, lon), group| group.size > 1 && coarse_coord?(lat, lon) }
    next if placeholders.empty?

    center = city_center(stem)
    label = city_label(stem)
    changed = false

    placeholders.each do |(lat, lon), group|
      group.each do |entry|
        name = entry['name']
        address = entry['address']

        unless address && !address.to_s.strip.empty?
          no_address << "#{name} (#{stem})"
          next
        end

        query = "#{address.strip}, #{label}"
        new_coord = nominatim_geocode(query)
        sleep(NOMINATIM_SLEEP)

        unless new_coord
          missed << "#{name} (#{stem}) — Nominatim miss for #{query.inspect}"
          next
        end

        if center
          km = haversine_km(new_coord[0], new_coord[1], center[0], center[1])
          if km > MAX_CENTER_KM
            missed << "#{name} (#{stem}) — #{format('%.0f', km)} km from center, implausible"
            next
          end
        end

        new_lat = new_coord[0].round(6)
        new_lon = new_coord[1].round(6)
        puts "  #{name} (#{stem}): #{lat}, #{lon} -> #{new_lat}, #{new_lon}"
        unless dry_run
          entry['lat'] = new_lat
          entry['lon'] = new_lon
          changed = true
        end
        geocoded += 1
      end
    end

    next unless changed

    write_atomic(path, entries)
    changed_files += 1
    puts "#{filename}: geocoded"
  end

  puts "\nGeocoded: #{geocoded} spots#{dry_run ? ' (dry run)' : ''}"
  puts "Skipped (no address): #{no_address.size}"
  no_address.each { |line| puts "  - #{line}" }
  puts "Missed (Nominatim miss / implausible): #{missed.size}"
  missed.each { |line| puts "  - #{line}" }
  puts "Changed #{changed_files} of #{files.size} files#{dry_run ? ' (dry run — nothing written)' : ''}"
end
