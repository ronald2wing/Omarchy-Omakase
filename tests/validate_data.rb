#!/usr/bin/env ruby
# frozen_string_literal: true

# Validate every line in data/*.jsonl is parseable JSON (seed data integrity).
#
# Usage: ruby tests/validate_data.rb

require 'json'

$stdout.sync = true

errors = 0
total = 0
data_dir = File.expand_path('../data', __dir__)

Dir.glob(File.join(data_dir, '*.jsonl')).sort.each do |file|
  puts "checking #{file}..."
  count = 0
  File.foreach(file, chomp: true) do |line|
    next if line.strip.empty?

    begin
      JSON.parse(line)
      count += 1
    rescue JSON::ParserError
      puts "  ERROR: invalid JSON line in #{file}"
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
