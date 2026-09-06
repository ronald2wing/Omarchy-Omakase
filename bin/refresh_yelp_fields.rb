#!/usr/bin/env ruby
# frozen_string_literal: true

# Unified Yelp refresh: fill missing Yelp fields for the whole directory.
#
# Two-phase strategy that minimizes API calls while guaranteeing coverage:
#
#   Phase 1 (bulk): per city, `term=omakase&location=<city>` searches (50
#   results/call) matched by `id` — cheap for the bulk of spots.
#   Phase 2 (exact): spots the bulk pass missed get a `term=<name>` search,
#   matched by normalized name — reliable for curated English names whose Yelp
#   titles differ (kanji, "Sushi Saito" vs "鮨 さいとう").
#
# Re-runnable: every field is guarded by fill-missing, so already-filled spots
# are skipped and only genuine gaps cost an API call.
#
# Usage:
#   ruby bin/refresh_yelp_fields.rb            # all cities
#   ruby bin/refresh_yelp_fields.rb tokyo      # one city

require_relative 'pipeline_common'

# Fill `entry[key]` from `value` only when the key is absent AND the value is
# non-blank. Blank means nil, "", or [] — the [] case is the documented gotcha:
# an empty array is valid JSON but means "no data", so it must not count as a
# value (otherwise `[].to_s == "[]"` would mark the field as set). Returns
# whether it wrote.
def fill_if_absent!(entry, key, value)
  blank = value.nil? || (value.respond_to?(:empty?) && value.empty?)
  return false if blank || entry.key?(key)

  entry[key] = value
  true
end

# Map entry key => { path:, transform: }, where `path` is the Yelp business JSON
# path (resolved with dig) and `transform` (optional) post-processes the resolved
# value: yelp_url drops Yelp's analytics query string, phone falls back to the raw
# `phone` field when `display_phone` is absent. The two fields this table can't
# express (boolean `is_closed`, rounded lat/lon) are handled inline in `merge_yelp`.
YELP_FIELD_MAP = {
  'yelp_url' => { path: %w[url], transform: ->(_business, value) { canonical_yelp_url(value) } },
  'yelp_rating' => { path: %w[rating] },
  'yelp_review_count' => { path: %w[review_count] },
  'yelp_price' => { path: %w[price] },
  'yelp_id' => { path: %w[id] },
  'image_url' => { path: %w[image_url] },
  'phone' => { path: %w[display_phone], transform: ->(business, value) { value || business['phone'] } },
  'transactions' => { path: %w[transactions] },
  'city' => { path: %w[location city] },
  'state' => { path: %w[location state] },
  'country' => { path: %w[location country] },
  'display_address' => { path: %w[location display_address] }
}.freeze

# Resolve the Yelp value for one YELP_FIELD_MAP row: `dig` walks the nested
# path nil-safely, then the row's optional transform post-processes the raw
# value.
def business_value(business, spec)
  value = business.dig(*spec[:path])
  spec[:transform] ? spec[:transform].call(business, value) : value
end

def merge_yelp(entry, business)
  # `map` (not `any?` with a block) so every field is attempted — `any?` with a
  # block is lazy and would stop at the first filled field, leaving the rest unset.
  changed = YELP_FIELD_MAP.map do |entry_key, spec|
    fill_if_absent!(entry, entry_key, business_value(business, spec))
  end.any?

  # `is_closed` is a boolean, so false is a valid value — key presence (not
  # truthiness) decides whether Yelp reported it.
  if business.key?('is_closed') && !entry.key?('is_closed')
    entry['is_closed'] = business['is_closed']
    changed = true
  end

  coordinates = business['coordinates'] || {}
  if coordinates['latitude'] && coordinates['longitude']
    entry['lat'] ||= coordinates['latitude'].round(6)
    entry['lon'] ||= coordinates['longitude'].round(6)
    changed = true
  end
  changed
end

# Core fields Yelp reliably returns; only these drive a search. image_url/phone
# are omitted: ~2-6% of spots lack them on Yelp itself, so requiring them would
# re-search the same unfillable spots on every run. `is_closed` is checked for
# key presence (false is a valid value), so it is handled separately in
# needs_fill rather than listed here.
REQUIRED_FIELDS = %w[yelp_url yelp_rating city state display_address].freeze

def needs_fill(entry)
  return false unless entry
  return false if entry['time'] && entry['discount']

  REQUIRED_FIELDS.any? { |field| !entry[field] } || !entry.key?('is_closed')
end

# ---- main ----
if __FILE__ == $PROGRAM_NAME
  city_arg = ARGV[0]

  files = Dir.glob(File.join(DATA_DIR, '*.jsonl')).map { |p| File.basename(p) }.sort
  files = files.select { |f| f == (city_arg.end_with?('.jsonl') ? city_arg : "#{city_arg}.jsonl") } if city_arg

  calls = 0
  filled = 0
  consecutive_429 = 0

  search_counted = lambda do |params|
    businesses = search_yelp(params)
    if businesses.nil?
      consecutive_429 += 1
      abort "\nAbort: consecutive 429s." if consecutive_429 >= 8
      return nil
    end
    consecutive_429 = 0
    calls += 1
    businesses
  end

  files.each do |filename|
    city_key = filename.sub(/\.jsonl\z/, '')
    location = city_location(city_key)
    next unless location

    path = File.join(DATA_DIR, filename)
    entries = load_jsonl(path)

    pending_by_id = {}
    pending_by_name = {}
    entries.each_with_index do |entry, index|
      next unless needs_fill(entry)

      pending_by_id[entry['yelp_id']] = index if entry['yelp_id']
      pending_by_name[normalize_name(entry['name'])] = index
    end
    next if pending_by_id.empty? && pending_by_name.empty?

    puts "\n#{city_key}: #{pending_by_id.size + pending_by_name.size} keys to fill"

    # Phase 1 — bulk "omakase" search matched by id (then name).
    offset = 0
    while offset < 250 && (!pending_by_id.empty? || !pending_by_name.empty?)
      businesses = search_counted.call('term' => 'omakase', 'location' => location,
                                       'limit' => 50, 'offset' => offset, 'sort_by' => 'best_match')
      break if businesses.nil? || businesses.empty?

      businesses.each do |business|
        business_id = business['id']
        business_key = normalize_name(business['name'])
        index = (business_id && pending_by_id[business_id]) || pending_by_name[business_key]
        next unless index && needs_fill(entries[index])

        if merge_yelp(entries[index], business)
          filled += 1
          puts "  [bulk] #{entries[index]['name']} -> #{business['name']}"
        end
        pending_by_id.delete(business_id) if business_id
        pending_by_name.delete(business_key)
      end
      sleep(YELP_SLEEP)
      break if businesses.size < 50

      offset += 50
    end

    write_atomic(path, entries)

    # Phase 2 — exact name search for the leftovers (dedup by entry index).
    seen = {}
    changed = false
    (pending_by_id.values + pending_by_name.values).each do |index|
      next if seen[index] || !needs_fill(entries[index])

      seen[index] = true

      name = entries[index]['name'].to_s
      businesses = search_counted.call('term' => name, 'location' => location, 'limit' => 10)
      break if businesses.nil?

      target = normalize_name(name)
      best = nil
      businesses.each do |business|
        candidate_key = normalize_name(business['name'])
        if candidate_key == target
          best = business
          break
        end
        if target != '' && candidate_key != '' && (target.include?(candidate_key) || candidate_key.include?(target))
          best ||= business
        end
      end
      if best && merge_yelp(entries[index], best)
        filled += 1
        puts "  [exact] #{name} -> #{best['name']}"
        changed = true
      end
      sleep(YELP_SLEEP)
    end

    write_atomic(path, entries) if changed
  end

  puts "\nDone: #{filled} spots gained fields (#{calls} API calls)"
end
