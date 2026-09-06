#!/usr/bin/env ruby
# frozen_string_literal: true

# Find and backfill official websites for spots missing one, using only
# official APIs (no search-engine scraping, no browser spoofing):
#
# - Nominatim (OpenStreetMap): free, no key, accurate for well-known spots
# - Foursquare Places API: needs FOURSQUARE_API_KEY in .env / env
#
# Usage:
#   ruby bin/backfill_websites.rb              # all missing
#   ruby bin/backfill_websites.rb melbourne    # one city
#   ruby bin/backfill_websites.rb --dry-run melbourne  # print hits, write nothing
#
# Resume via .website-progress. ~1.2s between requests (Nominatim's polite rate).

require_relative 'pipeline_common'
require 'net/http'
require 'uri'
require 'json'
require 'set'

WEBSITES_PROGRESS = File.join(ROOT, '.website-progress')
NOMINATIM_SLEEP = 1.2

# Skip the crawl when nearly every spot already has a website: a full
# Nominatim/Foursquare pass (rate-limited, ~1.2s per request) isn't worth it
# for a handful of stragglers — coverage is already ~100%.
MIN_MISSING_TO_CRAWL = 20

# Generic brand/directory fragments that are never a restaurant's own site,
# matched as SUBSTRINGS (`host.include?`). These are deliberately NOT domains:
# a brand stem spans many TLDs and subdomains (google.com, google.co.uk,
# googleusercontent.com), so an exact/suffix-domain match would miss most of
# them. A dotted entry here (e.g. "booking.com") is still a substring — it
# catches the bare host and any deeper path/prefix it appears in.
BLOCKED_FRAGMENTS = %w[
  facebook instagram linkedin yelp tripadvisor twitter x.com youtube reddit
  opentable foursquare zomato tiktok pinterest snapchat whatsapp booking.com
  google gstatic duckduckgo broadsheet grubbio restaurantsforkings bestjapanese
  menutotaste tablejourney eater timeout infatuation resy tock openrice
  tablecheck tabelog gurunavi gayot finedininglovers smh.com.au goodfood theage
  onlymelbourne sitchy urbanlist concreteplayground restaurantguru menuandprice
  allmenus menupix menuinfo seatme squareup.com wixsite godaddysites weebly
  yandex passport visitvictoria wikipedia github amazon tableall bing microsoft
  sluurpy pensador restaurantji menupages dineout salt7 gaultmillau doordash grubhub ubereats deliveroo
  thespruceeats obsproject ntlite phongnhaexplorer spotify fronteats menufy
].freeze

# Menu/ordering aggregators whose subdomains embed the restaurant name, so the
# distinctive-token check cannot reject them (e.g. ahisushi.kwickmenu.com).
# Unlike BLOCKED_FRAGMENTS, these are concrete domains matched EXACTLY or as a
# SUFFIX (`host == entry || host.end_with?(".#{entry}")`), never as substrings.
AGGREGATOR_HOSTS = %w[
  kwickmenu.com menufy.com toasttab.com seamless.com mainmenus.com menu-all.com
  menuhunterai.com menuph.com menusweb.com menutoeat.com menuweb.menu menuxp.com
  mymenuweb.com sagemenu.com speisekarte.menu restaurantmenu.us.com res-menu.net
  carta.menu hss.menu orderfattyfishsushi.com takumisushiorder.com
  terryinorder.com mjteriyakiorder.com
].freeze

# True when host contains a blocked generic fragment (substring match).
def blocked_fragment?(host)
  return false unless host

  BLOCKED_FRAGMENTS.any? { |fragment| host.include?(fragment) }
end

# True when host is an aggregator itself or a subdomain of one.
def aggregator_host?(host)
  return false unless host

  AGGREGATOR_HOSTS.any? { |entry| host == entry || host.end_with?(".#{entry}") }
end

# Extract + filter a domain from an absolute URL; nil when blocked/aggregator.
def clean_host(url)
  return nil unless url
  return nil unless url.start_with?('http')

  host = URI.parse(url).host.to_s.downcase.sub(/\Awww\./, '')
  return nil if host.empty?
  return nil if blocked_fragment?(host)
  return nil if aggregator_host?(host)

  host
end

# Nominatim (OpenStreetMap) — free, no key, accurate website when OSM has it.
# Coverage is good for well-known spots, sparse for small ones.
def nominatim_fetch(name, city)
  query = "#{name} #{city}"
  uri = URI('https://nominatim.openstreetmap.org/search')
  uri.query = URI.encode_www_form('q' => query, 'format' => 'jsonv2',
                                  'extratags' => '1', 'limit' => '3')
  req = Net::HTTP::Get.new(uri)
  req['User-Agent'] = 'OmakaseDataPipeline/1.0'
  res = http_request(uri, req, open_timeout: 12, read_timeout: 12)
  return nil unless res.is_a?(Net::HTTPSuccess)

  body = res.body.to_s
  if body.bytesize > MAX_BODY_BYTES
    warn "nominatim_fetch: response body #{body.bytesize} bytes exceeds #{MAX_BODY_BYTES} cap; skipping"
    return nil
  end
  places = JSON.parse(body)
  places.each do |place|
    website = (place['extratags'] || {})['website'].to_s
    next if website.empty?

    host = clean_host(website)
    return host if host
  end
  nil
rescue StandardError => e
  warn "nominatim_fetch(#{name.inspect}, #{city.inspect}): #{e.class}: #{e.message}"
  nil
end

# Lazy Foursquare API key (like yelp_api_key): read from the environment/.env on
# first use, not at require time, so tests requiring this file never touch the
# real .env. Memoized so the key is read at most once per process.
def foursquare_api_key
  @foursquare_api_key ||= load_env_key('FOURSQUARE_API_KEY')
end

# Batch Foursquare nearby search for a whole city: one call returns up to 50
# sushi spots near the city center, so many spots are resolved per call instead
# of one call each. Returns { normalized_name => host }.
def foursquare_batch(center, pending_names)
  key = foursquare_api_key
  return {} unless key

  result = {}
  [0, 50, 100, 150].each do |offset|
    uri = URI('https://places-api.foursquare.com/places/search')
    uri.query = URI.encode_www_form('ll' => center.join(','), 'query' => 'sushi',
                                    'limit' => '50', 'offset' => offset)
    req = Net::HTTP::Get.new(uri)
    req['Authorization'] = "Bearer #{key}"
    req['Accept'] = 'application/json'
    req['X-Places-Api-Version'] = '2025-06-17'
    res = http_request(uri, req, open_timeout: 12, read_timeout: 12)
    break unless res.is_a?(Net::HTTPSuccess)

    body = res.body.to_s
    if body.bytesize > MAX_BODY_BYTES
      warn "foursquare_batch: response body #{body.bytesize} bytes exceeds #{MAX_BODY_BYTES} cap; skipping"
      break
    end
    results = JSON.parse(body)['results'] || []
    break if results.empty?

    results.each do |place|
      normalized = normalize_name(place['name'])
      next unless pending_names.include?(normalized)
      next if result.key?(normalized)

      website = place['website'].to_s
      next if website.empty?

      host = clean_host(website)
      result[normalized] = host if host
    end
    break if results.size < 50
  end
  result
rescue StandardError => e
  warn "foursquare_batch(#{center.inspect}): #{e.class}: #{e.message}"
  {}
end

# Words that never identify a specific restaurant's domain.
STOPWORDS = %w[
  the and of for a an restaurant bar cafe grill house kitchen table lounge
  express garden fresh market japanese sashimi sake ramen noodle bistro dining
].freeze

# Generic sushi-world words that appear in nearly every sushi domain, so they
# can't distinguish one restaurant from another (biansushi.co.nz vs sushiedo
# .com.au both contain "sushi").
GENERIC_TOKENS = %w[sushi omakase izakaya robata teppanyaki hibachi].freeze

# Distinctive words from a restaurant name — strip stopwords, generic sushi
# words, and short words (< 3 chars). "Sushi Edo" -> ["edo"], "Osushi" ->
# ["osushi"], "Minamishima" -> ["minamishima"], "L.A Sushi" -> [].
def distinctive_tokens(name)
  name.to_s.downcase.gsub(/[^a-z0-9\s]/, ' ').split
      .reject { |word| word.length < 3 }
      .reject { |word| STOPWORDS.include?(word) }
      .reject { |word| GENERIC_TOKENS.include?(word) }
end

# ---- main ----
if __FILE__ == $PROGRAM_NAME
  dry_run = ARGV.delete('--dry-run')
  city_arg = ARGV[0]

  done = load_progress(WEBSITES_PROGRESS)
  puts "Resuming: #{done.size} spots already tried" unless done.empty?

  files = Dir.glob(File.join(DATA_DIR, '*.jsonl')).map { |path| File.basename(path) }.sort
  files = files.select { |file| file == (city_arg&.end_with?('.jsonl') ? city_arg : "#{city_arg}.jsonl") } if city_arg

  missing = 0
  file_data = {}

  files.each do |filename|
    path = File.join(DATA_DIR, filename)
    entries = load_jsonl(path)
    file_data[filename] = { path: path, entries: entries }
    entries.each { |entry| missing += 1 if entry && !entry['website'] && entry['name'] }
  end

  puts "#{missing} entries missing website"

  if missing < MIN_MISSING_TO_CRAWL && !dry_run
    puts "Only #{missing} missing — skipping crawl (coverage already ~100%)."
    exit 0
  end

  filled = 0
  progress_file = dry_run ? nil : File.open(WEBSITES_PROGRESS, 'a')

  # Phase 1 — batch Foursquare per city (one call resolves ~50 spots).
  if foursquare_api_key
    file_data.each do |filename, record|
      city_key = filename.sub(/\.jsonl\z/, '')
      center = city_center(city_key)
      next unless center

      pending = record[:entries].each_with_index.select do |entry, _i|
        entry && !entry['website'] && entry['name']
      end
      next if pending.empty?

      # normalized_name => entry index, built once so each batch hit resolves
      # in O(1) instead of re-normalizing every candidate inside the loop.
      # `||=` keeps first-wins semantics when two entries share a normalized name.
      pending_by_name = pending.each_with_object({}) do |(entry, idx), map|
        map[normalize_name(entry['name'])] ||= idx
      end

      pending_names = pending_by_name.keys.to_set
      batch = foursquare_batch(center, pending_names)
      next if batch.empty?

      changed = false
      batch.each do |normalized, host|
        idx = pending_by_name[normalized]
        next unless idx

        entry = record[:entries][idx]
        next if entry['website']

        puts "  [batch] #{entry['name']} (#{city_key}) -> #{host}"
        unless dry_run
          entry['website'] = "https://#{host}"
          changed = true
        end
        filled += 1
      end
      # One write per city per phase: mutating in the loop and writing once after
      # keeps the file on disk a single rewrite instead of one full rewrite per
      # filled spot.
      write_atomic(record[:path], record[:entries]) if changed
      sleep(NOMINATIM_SLEEP)
    end
  end

  # Phase 2 — Nominatim fallback for spots the batch missed.
  file_data.each do |filename, record|
    city_key = filename.sub(/\.jsonl\z/, '')
    changed = false
    record[:entries].each do |entry|
      next unless entry && !entry['website'] && entry['name']

      key = "#{entry['name']}|#{city_key}"
      next if done.include?(key)

      host = nominatim_fetch(entry['name'], entry['city'] || city_key)
      # Require the domain to echo a distinctive name token.
      tokens = distinctive_tokens(entry['name'])
      host = nil if host && !tokens.empty? && !tokens.any? { |token| host.include?(token) }

      if host && !host.empty?
        puts "  #{entry['name']} (#{city_key}) -> #{host}"
        unless dry_run
          entry['website'] = "https://#{host}"
          changed = true
        end
        filled += 1
      end
      progress_file&.write(key + "\n")
      progress_file&.flush
      sleep(NOMINATIM_SLEEP)
    end
    write_atomic(record[:path], record[:entries]) if changed
  end

  progress_file&.close
  puts "\nDone: filled #{filled} websites"
end
