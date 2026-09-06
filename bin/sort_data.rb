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
require 'set'

# ---- main ----
if __FILE__ == $PROGRAM_NAME
  stems = ARGV.map { |arg| arg.sub(/\.jsonl\z/, '') }
  files = Dir.glob(File.join(DATA_DIR, '*.jsonl')).sort
  unless stems.empty?
    known_stems = files.map { |path| File.basename(path, '.jsonl') }.to_set
    unknown = stems.reject { |stem| known_stems.include?(stem) }
    unless unknown.empty?
      warn "sort_data: no data file for #{unknown.sort.join(', ')} (available: #{known_stems.sort.join(', ')})"
      exit 1
    end
    files.select! { |path| stems.include?(File.basename(path, '.jsonl')) }
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
