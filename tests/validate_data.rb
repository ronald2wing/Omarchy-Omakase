#!/usr/bin/env -S -u RUBYOPT -u RUBYLIB -u RUBYGEMS_GEMDEPS -u BUNDLE_GEMFILE -u BUNDLE_PATH -u BUNDLE_BIN_PATH -u GEM_HOME -u GEM_PATH /usr/bin/ruby
# frozen_string_literal: true

# Validate every line in data/*.jsonl is a parseable JSON object (seed data
# integrity).
#
# Usage: ruby tests/validate_data.rb

require 'json'

$stdout.sync = true

# Truncated one-line excerpt so a 5,000-entry corpus doesn't require manual
# bisection to find the offending line.
EXCERPT_MAX = 80

def excerpt(line, max)
  text = line.strip
  text.length > max ? "#{text[0, max]}…" : text
end

# Numeric-range fields hold either a single number ("250") or a dash range
# ("<lo>-<hi>"). A descending range (lo > hi) is a transcription typo. Only a
# pure integer dash range is inspected — a symbol ("AYCE", "$$"), a bare number,
# or a slash range ("7pm/10pm" lives in discount_window, not these fields) never
# matches the range pattern.
NUMERIC_RANGE_FIELDS = %w[price courses].freeze

def descending_range?(value)
  m = /\A(\d+)-(\d+)\z/.match(value.to_s)
  m && m[1].to_i > m[2].to_i
end

errors = 0
total = 0
data_dir = File.expand_path('../data', __dir__)

Dir.glob(File.join(data_dir, '*.jsonl')).sort.each do |file|
  puts "checking #{file}..."
  count = 0
  File.foreach(file, chomp: true).with_index(1) do |line, lineno|
    next if line.strip.empty?

    begin
      parsed = JSON.parse(line)
      unless parsed.is_a?(Hash)
        puts "  ERROR: valid JSON but not an object in #{file}:#{lineno}: #{excerpt(line, EXCERPT_MAX)}"
        errors += 1
        next
      end
      count += 1
      NUMERIC_RANGE_FIELDS.each do |field|
        value = parsed[field]
        next unless descending_range?(value)

        puts "  ERROR: descending #{field} range #{value.inspect} in #{file}:#{lineno}: #{excerpt(line, EXCERPT_MAX)}"
        errors += 1
      end
    rescue JSON::ParserError
      puts "  ERROR: invalid JSON line in #{file}:#{lineno}: #{excerpt(line, EXCERPT_MAX)}"
      errors += 1
    end
  end
  puts "  #{count} entries"
  total += count
end

if errors.positive?
  puts "FAIL: #{errors} invalid lines"
  exit 1
end

puts "OK: all data/*.jsonl files valid (#{total} entries)"
