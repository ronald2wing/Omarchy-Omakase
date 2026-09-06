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
# Idempotent: re-running leaves an already-normalized file untouched.

require_relative 'pipeline_common'

# Street-type tokens that mark a value as a street address. Word-boundary
# matched, so "Broadway" does not match "way" and "St James" (a place name) is
# only caught when it actually starts a street. US covers Anglo cities; EU
# covers Latin/Germanic/Nordic street words that otherwise leak through as
# neighborhood names.
US_STREET_TYPES = %w[
  st street ave avenue rd road blvd boulevard dr drive ln lane way ct court
  pl place ter terrace hwy cres close grove mews quay esplanade square
].freeze

EU_STREET_TYPES = %w[
  via viale piazza corso calle carrer rua largo praceta plaza ronda rue gasse
  weg platz hovedgade vej
].freeze

# Words that begin a street prefix or a unit/floor indicator. These only count
# at the start of the string (the `prefix` test), unlike the street types above
# which count anywhere: "Ste B" (suite) and "Ground Floor" are addresses, while
# "Lower Ground Fl" is not caught here because "Lower" is the first word.
STREET_PREFIX_WORDS = %w[
  via calle carrer rua unit shop suite ste level fl floor ground shp
].freeze

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

# Derive the street address for an entry: the first non-empty `display_address`
# element verbatim (it is an array), else the original `neighborhood` when it is
# address-like, else nil.
def derive_address(entry)
  display = entry['display_address']
  if display.is_a?(Array)
    first = display.find { |el| el && !el.to_s.strip.empty? }
    return first if first
  end

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
  dry_run = ARGV.delete('--dry-run')

  files = Dir.glob(File.join(DATA_DIR, '*.jsonl')).sort

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
      if has_nb
        address_like?(original_nb) ? blanked += 1 : kept += 1
      end

      display = entry['display_address']
      if display.is_a?(Array) && display.find { |el| el && !el.to_s.strip.empty? }
        from_display_address += 1
      elsif has_nb && address_like?(original_nb)
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
