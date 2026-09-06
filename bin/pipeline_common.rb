#!/usr/bin/env ruby
# frozen_string_literal: true

# Require hub for the data pipeline: pulls in the city table (cities.rb), the
# JSONL/progress IO (jsonl.rb), and the Yelp client (yelp_client.rb), then
# defines the small shared helpers — project paths, env-key loading, haversine
# distance, URL normalization, and the on-disk sort key — that don't warrant a
# file of their own.

ROOT = File.expand_path('..', __dir__)
DATA_DIR = File.join(ROOT, 'data')
ENV_FILE = File.join(ROOT, '.env')

$stdout.sync = true

require_relative 'cities'
require_relative 'jsonl'
require_relative 'yelp_client'

# Look up `name` in the environment, then fall back to a `NAME=value` line in
# the .env file at `path` (defaults to the gitignored project .env; the
# argument is for tests). Returns nil when neither source has it.
def load_env_key(name, path = ENV_FILE)
  key = ENV[name]
  return key if key

  return nil unless File.exist?(path)

  File.foreach(path) do |line|
    return line.strip.split('=', 2)[1].strip.gsub(/\A["']|["']\z/, '') if line.strip.start_with?("#{name}=")
  end
  nil
end

# Strip Yelp's analytics query string (`?adjust_creative=...&utm_...`) from a
# business URL, keeping the base https://www.yelp.com/biz/<slug> link the Yelp
# button and Yelp's display terms require. Non-strings pass through unchanged.
def canonical_yelp_url(url)
  return url unless url.is_a?(String)

  url.split('?', 2).first
end

# Great-circle distance in km between two (lat, lon) points. The single Ruby
# implementation; collect_city's radius guard calls this (the JS copy lives in
# spot-utils.js for a different runtime).
def haversine_km(lat1, lon1, lat2, lon2)
  d_lat = (lat2 - lat1) * Math::PI / 180
  d_lon = (lon2 - lon1) * Math::PI / 180
  a = Math.sin(d_lat / 2)**2 +
      Math.cos(lat1 * Math::PI / 180) * Math.cos(lat2 * Math::PI / 180) *
      Math.sin(d_lon / 2)**2
  6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
end

# Deterministic on-disk sort key for a data/*.jsonl entry: name case-insensitively
# (locale-independent fold), tie-broken by lat then lon. Missing coordinates sort
# last (Infinity), so the order is total and reproducible regardless of Ruby's
# sort stability. `name` is always present in seed data, but `to_s` keeps the key
# total if it ever is absent.
def entry_sort_key(entry)
  lat = entry['lat']
  lon = entry['lon']
  [
    entry['name'].to_s.downcase,
    lat.nil? ? Float::INFINITY : lat.to_f,
    lon.nil? ? Float::INFINITY : lon.to_f
  ]
end

# Sort JSONL entries in place by entry_sort_key, so every file on disk shares the
# same order and a line reorder never churns git diffs.
def sort_entries!(entries)
  entries.sort_by! { |entry| entry_sort_key(entry) }
end
