#!/usr/bin/env -S -u RUBYOPT -u RUBYLIB -u RUBYGEMS_GEMDEPS -u BUNDLE_GEMFILE -u BUNDLE_PATH -u BUNDLE_BIN_PATH -u GEM_HOME -u GEM_PATH /usr/bin/ruby
# frozen_string_literal: true

# Fill missing `address` fields by Nominatim reverse geocoding (OpenStreetMap —
# free, no key). Yelp 403s from this network, so a Yelp refresh cannot fill
# `address`, but every spot in the directory carries coordinates and Nominatim
# can derive a street address from them.
#
# Only empty `address` fields are filled (a non-empty address is never touched),
# and only for spots with coordinates. Spots whose coordinates are city-centre
# placeholders are skipped, because reverse geocoding a placeholder yields a
# confidently wrong address. A placeholder is any coarse coordinate (4 or fewer
# decimal places in both lat and lon — the same threshold geocode_fallback.rb
# uses to spot fallback points; city-centre anchors are always coarse), plus any
# precise coordinate implausibly far (> MAX_CENTER_KM) from its city centre
# (e.g. a wrong-country geocode).
#
# Usage:
#   ruby bin/reverse_geocode_addresses.rb --validate  # sample known-good spots, report match rate
#   ruby bin/reverse_geocode_addresses.rb             # fill empty addresses
#   ruby bin/reverse_geocode_addresses.rb --dry-run   # print the plan, write nothing (still calls Nominatim)
#   ruby bin/reverse_geocode_addresses.rb [city]      # one city only (optional)
#
# Resumes via .reverse-geocode-progress. ~1.2s between requests (Nominatim's
# polite rate), matching backfill_websites.

require_relative 'pipeline_common'
require_relative 'website_sources'

REVERSE_GEOCODE_PROGRESS = File.join(ROOT, '.reverse-geocode-progress')

# Number of known-good spots --validate samples to estimate the match rate:
# enough for a stable percentage without paying a Nominatim round-trip per spot
# in the whole directory.
VALIDATION_SAMPLE_SIZE = 25

# Han-ideograph range (CJK unified ideographs + extension A) and the kana block
# (hiragana + katakana), shared by the CJK-aware compare/match helpers below so
# the hand-written copies of the ideograph class can't drift. String constants
# interpolate into the helpers' regexp literals, where the `\u` escapes resolve.
HAN = '[\u3400-\u4dbf\u4e00-\u9fff]'
KANA = '[\u3040-\u30ff]'

# Derive a concise street address from Nominatim's structured `address` map.
# Western addresses combine house number + road; CJK/block-addressed places fall
# back to the neighbourhood/quarter/suburb (Japan reverse geocoding is
# block-level, so no house numbers). Returns nil when the map has nothing
# address-like.
def derive_street_address(place)
  return nil unless place

  a = place['address'] || {}
  return "#{a['house_number']} #{a['road']}" if a['house_number'] && a['road']
  return a['road'] if a['road']
  return a['neighbourhood'] if a['neighbourhood'] && !a['neighbourhood'].empty?
  return a['quarter'] if a['quarter'] && !a['quarter'].empty?
  return a['suburb'] if a['suburb'] && !a['suburb'].empty?

  nil
end

# Lowercase, fold every non-letter/digit/CJK run to a single space, strip.
def compare_normalize(text)
  text.to_s.downcase.gsub(/[^a-z0-9#{KANA}#{HAN}]+/, ' ').strip
end

# Han-ideograph run in a CJK address (Japan/Korea block addresses have no spaces).
def cjk?(text)
  text =~ /#{HAN}/
end

# CJK addresses share a district when the two names overlap on at least two han
# characters (e.g. "西区愛宕3-1-6" and "愛宕三丁目" both carry 愛宕). Reverse
# geocoding Japan is block-level, so this is the best achievable match.
def shared_cjk_district?(a, b)
  a_han = a.scan(/#{HAN}/).uniq
  b_han = b.scan(/#{HAN}/).uniq
  (a_han & b_han).size >= 2
end

# How well a derived address matches the stored one: :exact when the token sets
# are identical (ignoring order and street-type words), :street when they share
# a distinctive non-numeric token (or, for CJK, a shared district), :miss
# otherwise.
def match_level(stored, derived)
  return :miss unless stored && !stored.empty? && derived && !derived.empty?

  if cjk?(stored) || cjk?(derived)
    return shared_cjk_district?(stored, derived) ? :street : :miss
  end

  stored_tokens = compare_normalize(stored).split
  derived_tokens = compare_normalize(derived).split
  significant = ->(tokens) do
    tokens.reject do |t|
      STREET_STOPWORDS.include?(t) || t.match?(/\A\d+\z/) || t.length < 3
    end
  end
  stored_sig = significant.call(stored_tokens)
  derived_sig = significant.call(derived_tokens)
  return :exact if stored_sig == derived_sig && stored_sig.any?
  return :street unless (stored_sig & derived_sig).empty?

  :miss
end

# ---- validation ----
# Reverse geocode a deterministic sample of spots that already carry a correct
# `address`, compare the derived address to the stored one, and print the match
# rate. This is the gate: only proceed to fill if the rate is useful. `sleeper`
# is injected (like the main run) so tests can suppress the real rate-limit pause.
def run_validation(sleeper: ->(secs) { sleep(secs) })
  sample = []
  data_filenames(DATA_DIR).each do |filename|
    path = File.join(DATA_DIR, filename)
    city_key = city_key_for(filename)
    load_jsonl(path).each do |entry|
      next unless address_present?(entry)
      next unless entry['lat'] && entry['lon']

      sample << [city_key, entry['name'], entry['address'], entry['lat'].to_f, entry['lon'].to_f]
    end
  end

  n = VALIDATION_SAMPLE_SIZE
  step = [sample.size / n, 1].max
  picked = (0...sample.size).step(step).first(n).map { |i| sample[i] }

  exact = 0
  street = 0
  missed = 0
  no_result = 0
  rows = []

  picked.each do |(city_key, name, stored, lat, lon)|
    place = nominatim_reverse(lat, lon)
    sleeper.call(NOMINATIM_SLEEP)
    derived = place && derive_street_address(place)
    unless derived
      no_result += 1
      rows << "  #{name} (#{city_key}): stored #{stored.inspect} -> no reverse result"
      next
    end

    level = match_level(stored, derived)
    exact += 1 if level == :exact
    street += 1 if level == :street
    missed += 1 if level == :miss
    rows << format('  %-8s %s (%s): stored %s -> %s', level.upcase, name, city_key, stored.inspect, derived.inspect)
  end

  rows.each { |row| puts row }
  useful = exact + street
  puts "\nValidation sample: #{picked.size} spots"
  puts "  exact:   #{exact}"
  puts "  street:  #{street}"
  puts "  miss:    #{missed}"
  puts "  no data: #{no_result}"
  if picked.empty?
    puts '  useful (exact+street) match rate: n/a (empty sample)'
  else
    puts "  useful (exact+street) match rate: #{format('%.0f%%', 100.0 * useful / picked.size)}"
  end
end

# Enumerable of [entry, lat, lon] for every empty-address spot with coordinates
# that is neither a coarse city-center placeholder nor implausibly far from its
# city center — the set the crawl reverse geocodes. Shared by the dry-run
# counter and the reverse loop so the two can't drift. Skip reasons (a coarse
# placeholder or an implausible point) are yielded to the optional block, so the
# loop reports them without re-deriving the predicate.
def reverse_work_items(entries, city_key)
  center = CITIES.dig(city_key, :center)
  entries.filter_map do |entry|
    next unless entry['name']
    next if address_present?(entry)
    next unless entry['lat'] && entry['lon']

    if coarse_coord?(entry['lat'], entry['lon'])
      yield entry, :coarse if block_given?
      next
    end
    if implausible_from_center?(entry['lat'].to_f, entry['lon'].to_f, center)
      yield entry, :wrong if block_given?
      next
    end

    [entry, entry['lat'], entry['lon']]
  end
end

# The entries of one coordinate group whose `city|name|lat,lon` key is not yet
# marked tried in `done`. Shared by the dry-run counter and the reverse loop so
# the two can't drift: a coordinate issues a reverse call only when this returns
# a non-empty set.
def pending_entries(lat, lon, group, city_key, done)
  group.reject { |entry, _lat, _lon| done.include?(geocode_progress_key(city_key, entry['name'], lat, lon)) }
end

# Group the reverse work items for one file by coordinate, keeping only the
# groups that still have an unmarked pending spot — the exact coordinate set the
# reverse loop calls. Shared by the dry-run counter and reverse_file so the two
# can't drift on the grouping. Skip reasons forward to the optional block.
def pending_coordinate_groups(entries, city_key, done, &skip_reporter)
  reverse_work_items(entries, city_key, &skip_reporter)
    .group_by { |_entry, lat, lon| [lat, lon] }
    .filter_map do |(lat, lon), group|
      pending = pending_entries(lat, lon, group, city_key, done)
      [lat, lon, pending] unless pending.empty?
    end
end

# ---- main ----
# One city file's reverse pass: collect the eligible entries (reporting the
# coarse/implausible skips), group by coordinate so two spots in one building
# share a single reverse call, then fill each pending entry's address. Mutates
# the shared `state` (filled/skipped_coarse/skipped_wrong/missed/errored/
# changed_files tallies) and writes the file's data + progress via
# persist_then_mark. Returns nothing.
def reverse_file(path, city_key, reverse_provider:, done:, progress_file:, dry_run:, sleeper:, failures:, state:)
  entries = load_jsonl(path)
  changed = false
  tried_keys = []

  # The reverse call is paced by `need_sleep` (the defer idiom shared with
  # backfill_websites/refresh_yelp_fields): a sleep fires before a request only
  # when a previous request already ran, so the pause after the final request is
  # dropped while pacing stays >= 1 req/s between actual requests.
  need_sleep = false
  pending_coordinate_groups(entries, city_key, done) do |entry, reason|
    if reason == :coarse
      state[:skipped_coarse] += 1
    else
      state[:skipped_wrong] << "#{entry['name']} (#{city_key})"
    end
  end.each do |lat, lon, pending|
    need_sleep = defer_sleep(sleeper, NOMINATIM_SLEEP, need_sleep)

    place = reverse_provider.call(lat.to_f, lon.to_f)
    need_sleep = true

    place = guard_result(failures, place, pending.first[0]['name'], city_key)
    if place.nil?
      state[:errored] += 1
      next
    end

    address = derive_street_address(place)

    pending.each do |entry, _lat, _lon|
      key = geocode_progress_key(city_key, entry['name'], lat, lon)
      if address.nil? || address.empty?
        state[:missed] << "#{entry['name']} (#{city_key})"
        tried_keys << key
        next
      end

      puts "  #{entry['name']} (#{city_key}): #{address}"
      unless dry_run
        entry['address'] = address
        changed = true
      end
      state[:filled] += 1
      tried_keys << key
    end
  end

  state[:changed_files] += 1 if persist_then_mark(changed, path, entries, progress_file, tried_keys)
end

# Print the run summary and return the result hash (filled + the missed/errored
# counts). Reads the shared `state` built by the per-file step, so the report
# lives in one place.
def report_reverse_run(state, file_count, dry_run:)
  print_run_summary(state, file_count, dry_run: dry_run, labels: {
    filled: 'addresses',
    sections: [
      { heading: 'Skipped', key: :skipped_coarse, detail: 'city-centre placeholder coords' },
      { heading: 'Skipped', key: :skipped_wrong, detail: "implausible, > #{MAX_CENTER_KM} km from centre" },
      { heading: 'Missed', key: :missed, detail: 'no reverse result' },
      { heading: 'Errored', key: :errored, detail: 'request failed — not marked tried' }
    ]
  })

  { filled: state[:filled], missed: state[:missed].size, errored: state[:errored] }
end

# Fill missing `address` fields by reverse geocoding coordinates. Collaborators
# are injected so the orchestration is testable off-network: `reverse_provider`
# is the Nominatim reverse client (nil | {} | place), `data_dir`/`progress_path`
# isolate every file read/write, and `sleeper` lets tests suppress the real
# rate-limit pauses. Defaults keep the CLI path identical to before.
def reverse_geocode_addresses(reverse_provider: method(:nominatim_reverse),
                              data_dir: DATA_DIR,
                              progress_path: REVERSE_GEOCODE_PROGRESS,
                              city_arg: nil, dry_run: false,
                              sleeper: ->(secs) { sleep(secs) })
  done = load_progress_with_resume(progress_path)

  files = data_filenames(data_dir)
  files = select_city_files(files, city_arg)
  puts "Scanning #{files.size} file(s)"

  # A dry run still reverse-geocodes: every eligible coordinate group issues a
  # Nominatim reverse call. Count those groups (deduped by coordinate, matching
  # the group_by below) before any request, so a "check first" run sees its cost.
  if dry_run
    print_distinct_units_estimate(
      files, dedup_across_files: false,
      summary: ->(count) { "#{count} reverse geocode call(s) expected" },
      provider: 'Nominatim'
    ) do |filename|
      path = File.join(data_dir, filename)
      city_key = city_key_for(filename)
      pending_coordinate_groups(load_jsonl(path), city_key, done).map { |lat, lon, _pending| [lat, lon] }
    end
  end

  # Shared mutable run state the per-file step accumulates.
  state = { filled: 0, skipped_coarse: 0, skipped_wrong: [], missed: [], errored: 0, changed_files: 0 }
  failures = build_failure_guard(
    warn_text: ->(name, city) { "#{name} (#{city}): reverse geocode failed" },
    abort_text: 'reverse geocode failures (rate limit or network).'
  )
  progress_file = open_progress(progress_path, dry_run: dry_run)

  files.each do |filename|
    path = File.join(data_dir, filename)
    city_key = city_key_for(filename)
    reverse_file(path, city_key, reverse_provider: reverse_provider, done: done,
                 progress_file: progress_file, dry_run: dry_run, sleeper: sleeper,
                 failures: failures, state: state)
  end

  close_progress(progress_file)

  report_reverse_run(state, files.size, dry_run: dry_run)
end

if __FILE__ == $PROGRAM_NAME
  flags = parse_common_flags(ARGV)
  if flags.help
    print_usage('reverse_geocode_addresses.rb',
                'Fill missing addresses by Nominatim reverse geocoding.',
                [['--dry-run', 'Print the plan, write nothing (still calls Nominatim).'],
                 ['--validate', 'Sample known-good spots and report the match rate.']],
                '[city]')
    exit 0
  end
  if flags.validate
    run_validation
    exit 0
  end
  result = reverse_geocode_addresses(city_arg: flags.city, dry_run: flags.dry_run)
  exit 1 if result[:errored].positive? && result[:filled].zero?
end
