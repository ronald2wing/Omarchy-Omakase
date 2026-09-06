#!/usr/bin/env -S -u RUBYOPT -u RUBYLIB -u RUBYGEMS_GEMDEPS -u BUNDLE_GEMFILE -u BUNDLE_PATH -u BUNDLE_BIN_PATH -u GEM_HOME -u GEM_PATH /usr/bin/ruby
# frozen_string_literal: true

# Website providers for backfill_websites: Nominatim (OpenStreetMap) and the
# Foursquare Places API. Kept in one file so the two adapters share their
# host-cleaning/filtering and can't drift apart. Like yelp_client.rb, this file
# is loaded through backfill_websites.rb (which requires pipeline_common first)
# and relies on http_request/read_capped_body/MAX_BODY_BYTES/BodyTooLarge
# (yelp_client), normalize_name (jsonl), and load_env_key (pipeline_common)
# being defined by then.

require 'net/http'
require 'uri'
require 'json'

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
rescue URI::InvalidURIError
  # Malformed website value from a provider degrades to "no host", not an abort.
  nil
end

# Nominatim (OpenStreetMap) — free, no key, accurate website when OSM has it.
# Coverage is good for well-known spots, sparse for small ones. The shared search
# below also powers geocode_fallback.rb's coordinate lookup; both callers sleep
# NOMINATIM_SLEEP between requests to stay within Nominatim's polite rate.
NOMINATIM_SLEEP = 1.2
NOMINATIM_USER_AGENT = 'OmakaseDataPipeline/1.0'
# Shared open/read timeout for the Nominatim and Foursquare provider calls.
# Slower free-tier APIs than Yelp (HTTP_TIMEOUT 20s in yelp_client.rb), but a
# request that hangs any longer is a lost cause worth giving up on.
PROVIDER_TIMEOUT = 12

# One Nominatim search. `query` is the free-text search string and `limit` caps
# how many results are returned. Returns the parsed JSON array of places (nil on
# error), each carrying `lat`/`lon` and — with `extratags` requested — an
# `extratags` map that may hold a `website`. Callers rate-limit with
# NOMINATIM_SLEEP, as Nominatim asks for ~1 req/s.
def nominatim_search(query, limit:)
  uri = URI('https://nominatim.openstreetmap.org/search')
  uri.query = URI.encode_www_form('q' => query, 'format' => 'jsonv2',
                                  'extratags' => '1', 'limit' => limit.to_s)
  req = Net::HTTP::Get.new(uri)
  req['User-Agent'] = NOMINATIM_USER_AGENT
  results = nil
  http_request(uri, req, open_timeout: PROVIDER_TIMEOUT, read_timeout: PROVIDER_TIMEOUT) do |res|
    body = read_capped_body(res, max_bytes: MAX_BODY_BYTES)
    results = JSON.parse(body) if res.is_a?(Net::HTTPSuccess)
  end
  results
rescue BodyTooLarge
  warn "nominatim_search: response body exceeds #{MAX_BODY_BYTES} cap; skipping"
  nil
rescue *HTTP_TRANSPORT_ERRORS, JSON::ParserError, URI::InvalidURIError => e
  warn "nominatim_search(#{query.inspect}): #{e.class}: #{e.message}"
  nil
end

# Resolve a spot's official website from Nominatim: search "<name> <city>" and
# return the first result whose extratags carry a non-blocked website host.
def nominatim_fetch(name, city)
  places = nominatim_search("#{name} #{city}", limit: 3)
  return nil unless places

  places.each do |place|
    website = (place['extratags'] || {})['website'].to_s
    next if website.empty?

    host = clean_host(website)
    return host if host
  end
  nil
end

# Lazy Foursquare API key (like yelp_api_key): read from the environment/.env on
# first use, not at require time, so tests requiring this file never touch the
# real .env. Memoized so the key is read at most once per process.
def foursquare_api_key
  @foursquare_api_key ||= load_env_key('FOURSQUARE_API_KEY')
end

# Foursquare's max `limit` per /places/search call, and the number of pages
# fetched per city (200 results max). Mirrors the Yelp pagination concept
# (YELP_PAGE_SIZE in yelp_client.rb / YELP_MAX_PAGES in collect_cities.rb) — one
# call resolves up to this many spots near the city center, paginated by
# `offset = page * FOURSQUARE_PAGE_SIZE`.
FOURSQUARE_PAGE_SIZE = 50
FOURSQUARE_MAX_PAGES = 4

# Batch Foursquare nearby search for a whole city: one call returns up to
# FOURSQUARE_PAGE_SIZE sushi spots near the city center, so many spots are
# resolved per call instead of one call each. Returns { normalized_name => host }.
def foursquare_batch(center, pending_names)
  key = foursquare_api_key
  return {} unless key

  result = {}
  FOURSQUARE_MAX_PAGES.times do |page|
    uri = URI('https://places-api.foursquare.com/places/search')
    uri.query = URI.encode_www_form('ll' => center.join(','), 'query' => 'sushi',
                                    'limit' => FOURSQUARE_PAGE_SIZE,
                                    'offset' => page * FOURSQUARE_PAGE_SIZE)
    req = Net::HTTP::Get.new(uri)
    req['Authorization'] = "Bearer #{key}"
    req['Accept'] = 'application/json'
    req['X-Places-Api-Version'] = '2025-06-17'
    results = nil
    begin
      http_request(uri, req, open_timeout: PROVIDER_TIMEOUT, read_timeout: PROVIDER_TIMEOUT) do |res|
        body = read_capped_body(res, max_bytes: MAX_BODY_BYTES)
        results = JSON.parse(body)['results'] || [] if res.is_a?(Net::HTTPSuccess)
      end
    rescue BodyTooLarge
      warn "foursquare_batch: response body exceeds #{MAX_BODY_BYTES} cap; skipping"
      break
    end
    break if results.nil? || results.empty?

    results.each do |place|
      normalized = normalize_name(place['name'])
      next unless pending_names.include?(normalized)
      next if result.key?(normalized)

      website = place['website'].to_s
      next if website.empty?

      host = clean_host(website)
      result[normalized] = host if host
    end
    break if results.size < FOURSQUARE_PAGE_SIZE
  end
  result
rescue *HTTP_TRANSPORT_ERRORS, JSON::ParserError, URI::InvalidURIError => e
  warn "foursquare_batch(#{center.inspect}): #{e.class}: #{e.message}"
  {}
end
