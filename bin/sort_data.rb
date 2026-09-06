#!/usr/bin/env -S -u RUBYOPT -u RUBYLIB -u RUBYGEMS_GEMDEPS -u BUNDLE_GEMFILE -u BUNDLE_PATH -u BUNDLE_BIN_PATH -u GEM_HOME -u GEM_PATH /usr/bin/ruby
# frozen_string_literal: true

# Sort every data/*.jsonl file by name (case-insensitive), tie-broken by lat then
# lon, so a hand-edit that appends a line out of order doesn't churn the whole
# file in git. The pipeline (collect_cities.rb) keeps files sorted automatically;
# run this after editing data/ by hand. Idempotent: an already-sorted file is
# left untouched.
#
# Usage:
#   ruby bin/sort_data.rb              # all cities
#   ruby bin/sort_data.rb tokyo paris  # only those cities

require_relative 'pipeline_common'

# ---- main ----
if __FILE__ == $PROGRAM_NAME
  flags = parse_common_flags(ARGV, supported: %w[--dry-run --help -h])
  if flags.help
    print_usage('sort_data.rb',
                'Sort every data/*.jsonl file by name (case-insensitive).',
                [], '[city ...]')
    exit 0
  end

  files = data_paths(DATA_DIR)
  cities = flags.positionals
  unless cities.empty?
    # Validate every name up front (warn + exit on the first unknown, matching
    # select_city_files' message) and select the matching files in one pass.
    basenames = files.map { |path| File.basename(path) }
    targets = cities.map { |arg| arg.end_with?('.jsonl') ? arg : "#{arg}.jsonl" }
    cities.zip(targets).each do |arg, target|
      next if basenames.include?(target)

      available = files.map { |path| city_key_for(path) }.sort.join(', ')
      warn "no data file for #{arg} (available: #{available})"
      exit 1
    end
    files = files.select { |path| targets.include?(File.basename(path)) }
  end

  changed = 0
  files.each do |path|
    filename = File.basename(path)
    entries = load_jsonl(path)
    original = entries.dup
    sort_entries!(entries)

    if entries == original
      puts "#{filename}: already sorted (#{entries.size} entries)"
    else
      write_atomic(path, entries)
      changed += 1
      puts "#{filename}: sorted (#{entries.size} entries)"
    end
  end

  puts "\nChanged #{changed} of #{files.size} files"
end
