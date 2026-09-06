#!/usr/bin/env -S -u RUBYOPT -u RUBYLIB -u RUBYGEMS_GEMDEPS -u BUNDLE_GEMFILE -u BUNDLE_PATH -u BUNDLE_BIN_PATH -u GEM_HOME -u GEM_PATH /usr/bin/ruby
# frozen_string_literal: true

# Website providers for backfill_websites: Nominatim (OpenStreetMap) and the
# Foursquare Places API. Kept in one file so the two adapters share their
# host-cleaning/filtering and can't drift apart. Like yelp_client.rb, this file
# is loaded through backfill_websites.rb (which requires pipeline_common first)
# and relies on http_request/read_capped_body/MAX_BODY_BYTES/BodyTooLarge/
# HTTP_TRANSPORT_ERRORS (yelp_client), normalize_name (jsonl), and load_env_key
# (pipeline_common) being defined by then.

require 'net/http'
require 'uri'
require 'json'

# Host fragments that are never a restaurant's own site, matched as SUBSTRINGS
# (`host.include?`). These are deliberately NOT domains: a brand stem spans many
# TLDs and subdomains (google.com, google.co.uk, googleusercontent.com), so an
# exact/suffix-domain match would miss most of them. A dotted entry here (e.g.
# "squareup.com") is still a substring — it catches the bare host and any deeper
# path/prefix it appears in. `blocked_fragment?` rejects a host matching either
# list below, so this split is a reviewability change only — the matched set is
# unchanged.
#
# Generic social/brand/platform hosts: social networks, search engines,
# reference sites, DIY website builders (a wix/godaddy/weebly restaurant still
# has a builder URL, not its own domain), and a tour operator.
# One-off brand entries kept only so filtering behaviour is unchanged:
# obsproject (screen-recording software) and ntlite (a Windows tool) are not
# restaurant/social/ordering hosts — probable accidental matches — and
# phongnhaexplorer is a Vietnam tour operator, never a restaurant's own domain.
BLOCKED_BRANDS = %w[
  facebook instagram linkedin twitter x.com youtube reddit tiktok pinterest
  snapchat whatsapp google gstatic duckduckgo bing microsoft yandex wikipedia
  github amazon spotify passport wixsite godaddysites weebly squareup.com
  visitvictoria obsproject ntlite phongnhaexplorer
].freeze

# Restaurant directories, food media, and booking/ordering/menu aggregators —
# third-party sites a spot's "website" field may point at instead of its own
# domain.
# One-off directory entries kept only so filtering behaviour is unchanged:
# thespruceeats is a recipe/food-media site (never a restaurant's own domain);
# salt7 looks like a restaurant's own domain (Salt7), so blocking it is likely
# an accidental over-match.
# Marketplace/storefront hosts a spot points at instead of its own site: a
# Japanese grocer's web store, a food marketplace, or a menu/city directory.
# postcard.inc keeps its .inc suffix because the bare "postcard" stem is a
# common word and would over-match.
BLOCKED_DIRECTORIES = %w[
  yelp tripadvisor opentable foursquare zomato booking.com broadsheet grubbio
  restaurantsforkings bestjapanese menutotaste tablejourney eater timeout
  infatuation resy tock openrice tablecheck tabelog gurunavi gayot
  finedininglovers smh.com.au goodfood theage onlymelbourne sitchy urbanlist
  concreteplayground restaurantguru menuandprice allmenus menupix menuinfo
  seatme tableall sluurpy pensador restaurantji menupages dineout gaultmillau
  doordash grubhub ubereats deliveroo fronteats menufy thespruceeats salt7
  zmenu postcard.inc manhattan-nyc mogmog okimart137 sakuraofjapan
  shinjukuramen56 tenichimart
].freeze

# Combined, frozen lookup for blocked_fragment?: the two lists above are kept
# separate for reviewability, but a host check scans the union once instead of
# running two substring scans per host.
BLOCKED_FRAGMENTS = (BLOCKED_BRANDS + BLOCKED_DIRECTORIES).freeze

# Menu/ordering aggregators whose subdomains embed the restaurant name, so the
# distinctive-token check cannot reject them (e.g. ahisushi.kwickmenu.com).
# Unlike BLOCKED_BRANDS/BLOCKED_DIRECTORIES, these are concrete domains matched
# EXACTLY or as a SUFFIX (`host == entry || host.end_with?(".#{entry}")`), never
# as substrings.
AGGREGATOR_HOSTS = %w[
  kwickmenu.com menufy.com toasttab.com seamless.com mainmenus.com menu-all.com
  menuhunterai.com menuph.com menusweb.com menutoeat.com menuweb.menu menuxp.com
  mymenuweb.com sagemenu.com speisekarte.menu restaurantmenu.us.com res-menu.net
  carta.menu hss.menu
].freeze

# Individual restaurants' own online-order hosts. These are NOT an aggregator
# platform — each is a single restaurant's ordering page, grouped here only
# because the host embeds the restaurant name, which fools the distinctive-token
# check into accepting it. Matched exactly/as a suffix and rejected by the same
# check as AGGREGATOR_HOSTS.
ORDER_PAGE_HOSTS = %w[
  orderfattyfishsushi.com takumisushiorder.com terryinorder.com mjteriyakiorder.com
].freeze

# Frozen union of AGGREGATOR_HOSTS and ORDER_PAGE_HOSTS. The two lists stay
# separate for reviewability; aggregator_host? scans this single union so the
# exact/suffix check runs once per host, not twice.
AGGREGATOR_AND_ORDER_HOSTS = (AGGREGATOR_HOSTS + ORDER_PAGE_HOSTS).freeze

# True when host contains a blocked brand or directory fragment (substring
# match). Consulted by clean_host to reject third-party sites.
def blocked_fragment?(host)
  return false unless host

  BLOCKED_FRAGMENTS.any? { |fragment| host.include?(fragment) }
end

# True when host is an aggregator itself or a subdomain of one, or is one of the
# individual restaurants' own order-page hosts. Both lists reject identically,
# via an exact/suffix match (`host == entry || host.end_with?(".#{entry}")`) —
# never substring.
def aggregator_host?(host)
  return false unless host

  AGGREGATOR_AND_ORDER_HOSTS.any? { |entry| host == entry || host.end_with?(".#{entry}") }
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

# Errors a provider call treats as a hard failure: the transport-level set from
# yelp_client's http_request plus the JSON parse error a malformed provider
# payload raises. (URI::InvalidURIError is deliberately absent: the only
# URI.parse in this file, inside clean_host, already rescues it, so it never
# reaches a provider rescue.) nominatim_get and foursquare_batch rescue exactly
# this set and surface the failure as nil, so a transient network fault is never
# recorded as a permanent "tried".
PROVIDER_ERRORS = [*HTTP_TRANSPORT_ERRORS, JSON::ParserError].freeze

# One Nominatim GET for `path` ("search" or "reverse") with the given query
# params. Streams the body capped at MAX_BODY_BYTES and parses it only on an
# HTTPSuccess response, so a non-2xx yields nil without ever parsing an error
# body. Returns the parsed JSON on success, nil on any hard failure — a non-2xx
# status, a transport/parse error, or an invalid URI. `label` names the caller
# in the warn messages so a failed request is traceable to its query/coords.
def nominatim_get(path, params, label)
  uri = URI("https://nominatim.openstreetmap.org/#{path}")
  uri.query = URI.encode_www_form(params)
  req = Net::HTTP::Get.new(uri)
  req['User-Agent'] = NOMINATIM_USER_AGENT
  results = nil
  http_request(uri, req, open_timeout: PROVIDER_TIMEOUT, read_timeout: PROVIDER_TIMEOUT) do |res|
    body = read_capped_body(res, max_bytes: MAX_BODY_BYTES)
    results = JSON.parse(body) if res.is_a?(Net::HTTPSuccess)
  end
  results
rescue BodyTooLarge
  warn "#{label}: response body exceeds #{MAX_BODY_BYTES} cap; skipping"
  nil
rescue *PROVIDER_ERRORS => e
  warn "#{label}: #{e.class}: #{e.message}"
  nil
end

# One Nominatim search. `query` is the free-text search string and `limit` caps
# how many results are returned, each carrying `lat`/`lon` and — with
# `extratags` requested — an `extratags` map that may hold a `website`.
# Contract: nil on a hard failure (transport/parse/non-2xx); an empty Array ([])
# when the request succeeded and found nothing. Callers rate-limit with
# NOMINATIM_SLEEP, as Nominatim asks for ~1 req/s.
def nominatim_search(query, limit:)
  nominatim_get('search',
                { 'q' => query, 'format' => 'jsonv2', 'extratags' => '1',
                  'limit' => limit.to_s },
                "nominatim_search(#{query.inspect})")
end

# One Nominatim reverse lookup (the reverse sibling of nominatim_search).
# Contract: nil on a hard failure (transport/parse/non-2xx); an empty Hash ({})
# when the request succeeded and found no place. Callers rate-limit with
# NOMINATIM_SLEEP.
def nominatim_reverse(lat, lon)
  nominatim_get('reverse',
                { 'lat' => lat.to_s, 'lon' => lon.to_s, 'format' => 'jsonv2',
                  'addressdetails' => '1', 'zoom' => '18' },
                "nominatim_reverse(#{lat}, #{lon})")
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
# Pause between Foursquare batch calls (one per city) in backfill_websites.rb's
# Phase 1. A separate constant from NOMINATIM_SLEEP so a Foursquare pause is never
# misread as Nominatim's ~1 req/s polite rate; the two share a value today but
# pace different providers, so they stay independent.
FOURSQUARE_SLEEP = 1.2

# Batch Foursquare nearby search for a whole city: one call returns up to
# FOURSQUARE_PAGE_SIZE sushi spots near the city center, so many spots are
# resolved per call instead of one call each. Returns { normalized_name => host }.
# Contract: nil on a hard failure (missing API key, transport/parse/invalid URI);
# an empty Hash ({}) when the requests succeeded but no spot resolved to a usable
# website. Callers distinguish the two so a transient failure is not recorded as
# permanently tried.
def foursquare_batch(center, pending_names)
  key = foursquare_api_key
  return nil unless key

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
      return nil
    end
    # A non-2xx response leaves `results` nil (the HTTPSuccess gate never
    # assigns it). That is a hard failure, not a successful-but-empty page:
    # return nil so the caller never records the pending names as permanently
    # tried, and never surfaces a partial result built from earlier pages.
    return nil if results.nil?

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
    # Early-exit once every pending name is matched: a further page can't add
    # anything. Placed after the first page's request + processing, so an empty
    # pending set still runs that first page instead of short-circuiting before
    # any request.
    break if (pending_names - result.keys).empty?
    break if results.size < FOURSQUARE_PAGE_SIZE
  end
  result
rescue *PROVIDER_ERRORS => e
  warn "foursquare_batch(#{center.inspect}): #{e.class}: #{e.message}"
  nil
end
