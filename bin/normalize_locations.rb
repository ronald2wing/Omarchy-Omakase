#!/usr/bin/env -S -u RUBYOPT -u RUBYLIB -u RUBYGEMS_GEMDEPS -u BUNDLE_GEMFILE -u BUNDLE_PATH -u BUNDLE_BIN_PATH -u GEM_HOME -u GEM_PATH /usr/bin/ruby
# frozen_string_literal: true

# Normalize the location fields across every data/*.jsonl entry.
#
# Sources disagree on the location fields: `neighborhood` may hold a street
# address (Yelp's `location.address1`), `city` merely duplicates the file stem,
# and `display_address` is only sometimes present. This script splits the two
# locations apart:
#
#   address      — the street address: `display_address[0]`, else an
#                  address-like `neighborhood` value.
#   neighborhood — only real neighborhood names survive; street/floor values
#                  move to `address` and are dropped from here.
#   city         — dropped entirely; the file stem is the canonical city.
#
# Usage:
#   ruby bin/normalize_locations.rb --dry-run   # per-city counts, write nothing
#   ruby bin/normalize_locations.rb             # apply, rewriting changed files only
#
# Offline: reads and writes only the local data/*.jsonl files — it makes no API
# calls, so --dry-run is a free preview (unlike the website/geocode scripts,
# whose dry runs still call their providers).
#
# Idempotent: re-running leaves an already-normalized file untouched.

require_relative 'pipeline_common'

# Words that mark a street address only in prefix position (the `prefix` test),
# unlike the US_STREET_TYPES/EU_STREET_TYPES defined in pipeline_common.rb, which
# mark a street type anywhere in the string: "Ste B" (suite) and "Ground Floor"
# are addresses, while "Lower Ground Fl" is not caught here because "Lower" is
# not in this list.
#
# The EU street words (via, calle, carrer, rua, ...) are derived from
# EU_STREET_TYPES rather than re-listed, so a new EU street word is added in one
# place only. They already match anywhere via EU_STREET_TYPES; reusing the list
# keeps the prefix set in step with the anywhere set at no behavioural cost.
STREET_PREFIX_WORDS = (EU_STREET_TYPES + %w[
  unit shop suite ste level fl floor ground shp
]).freeze

# True when `s` looks like a street address rather than a neighborhood name:
# contains a digit, contains a street-type token, or starts with a street prefix
# / unit / floor word.
def address_like?(s)
  return false if s.nil?

  text = s.to_s.strip
  return false if text.empty?
  return true if text.match?(/\d/)

  words = text.downcase.scan(/[a-z0-9]+/)
  return true if words.any? { |word| US_STREET_TYPES.include?(word) || EU_STREET_TYPES.include?(word) }
  return true if STREET_PREFIX_WORDS.include?(words.first)

  false
end

# The entry's first non-empty `display_address` element, or nil when absent — the
# value `derive_address` returns verbatim. `find` returns the element itself
# (truthy) or nil, and `display.is_a?(Array)` short-circuits a non-array to
# false, so the same call doubles as a presence test (the dry-run counter) and
# the value extraction (derive_address).
def first_display_address(entry)
  display = entry['display_address']
  display.is_a?(Array) && display.find { |el| el && !el.to_s.strip.empty? }
end

# Derive the street address for an entry: the first non-empty `display_address`
# element verbatim (it is an array), else the original `neighborhood` when it is
# address-like, else nil.
def derive_address(entry)
  first = first_display_address(entry)
  return first if first

  nb = entry['neighborhood']
  return nb if nb && !nb.to_s.strip.empty? && address_like?(nb)

  nil
end

# Decide whether the original `neighborhood` survives as a real neighborhood
# name. Returns the kept string, or nil when it was blank or address-like (so it
# belonged in `address` instead). `nb` is the value captured before any
# normalization, so the decision never depends on a half-normalized entry.
def clean_neighborhood(nb)
  return nil if nb.nil? || nb.to_s.strip.empty?
  return nil if address_like?(nb)

  nb
end

# Normalize one entry: derive + insert the `address`, drop `city`, drop a
# blank/address-like `neighborhood`, and delete any remaining blank values. Key
# order is preserved, with `address` inserted immediately before `neighborhood`
# (or, when there is no `neighborhood` key, immediately after `display_address`,
# else appended). Returns a new hash; the input is not mutated. Idempotent:
# normalizing an already-normalized entry is a fixed point.
def normalize_entry(entry)
  original_nb = entry['neighborhood']
  derived = derive_address(entry)
  kept_nb = clean_neighborhood(original_nb)

  # Reuse an already-normalized `address` when nothing new was derived, so a
  # second pass over a normalized entry (whose address-like neighborhood is
  # already gone) does not drop the address.
  address = derived || entry['address']

  pairs = []
  placed = false
  entry.each do |key, value|
    next if key == 'city' # the file stem is the canonical city

    case key
    when 'address'
      pairs << [key, address]
      placed = true
    when 'neighborhood'
      if address && !placed
        pairs << ['address', address]
        placed = true
      end
      pairs << ['neighborhood', kept_nb] if kept_nb
    else
      pairs << [key, value]
    end
  end

  if !placed && address
    display_index = pairs.index { |key, _| key == 'display_address' }
    if display_index
      pairs.insert(display_index + 1, ['address', address])
    else
      pairs << ['address', address]
    end
  end

  pairs.delete_if { |_, value| value.nil? || (value.respond_to?(:empty?) && value.empty?) }
  pairs.to_h
end

# ---- main ----
if __FILE__ == $PROGRAM_NAME
  flags = parse_common_flags(ARGV, supported: %w[--dry-run --help -h])
  if flags.help
    print_usage('normalize_locations.rb',
                'Normalize the location fields across every data/*.jsonl entry.',
                [['--dry-run', 'Per-city counts, write nothing.']])
    exit 0
  end
  dry_run = flags.dry_run

  files = data_paths(DATA_DIR)

  totals = { kept: 0, blanked: 0, from_neighborhood: 0, from_display_address: 0 }
  changed_files = 0

  files.each do |path|
    filename = File.basename(path)
    entries = load_jsonl(path)

    kept = 0
    blanked = 0
    from_neighborhood = 0
    from_display_address = 0

    entries.each do |entry|
      original_nb = entry['neighborhood']
      has_nb = original_nb && !original_nb.to_s.strip.empty?
      kept_nb = clean_neighborhood(original_nb)

      if has_nb
        kept_nb.nil? ? blanked += 1 : kept += 1
      end

      if first_display_address(entry)
        from_display_address += 1
      elsif has_nb && kept_nb.nil?
        from_neighborhood += 1
      end
    end

    totals[:kept] += kept
    totals[:blanked] += blanked
    totals[:from_neighborhood] += from_neighborhood
    totals[:from_display_address] += from_display_address

    if dry_run
      puts "#{filename}: kept=#{kept} blanked=#{blanked} " \
           "from-neighborhood=#{from_neighborhood} from-display_address=#{from_display_address}"
    else
      normalized = entries.map { |entry| normalize_entry(entry) }
      sort_entries!(normalized)
      next if normalized == entries

      write_atomic(path, normalized)
      changed_files += 1
      puts "#{filename}: normalized (#{entries.size} entries)"
    end
  end

  if dry_run
    puts "Total: kept=#{totals[:kept]} blanked=#{totals[:blanked]} " \
         "from-neighborhood=#{totals[:from_neighborhood]} " \
         "from-display_address=#{totals[:from_display_address]}"
  else
    puts "\nChanged #{changed_files} of #{files.size} files"
  end
end
