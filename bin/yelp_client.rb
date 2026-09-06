#!/usr/bin/env ruby
# frozen_string_literal: true

# Yelp Fusion HTTP client: persistent connections, retry/backoff, and the search
# endpoint wrapper. Kept in one file so fetch/refresh don't drift apart.

require 'net/http'
require 'uri'
require 'json'

YELP_BASE = 'https://api.yelp.com/v3'
YELP_SLEEP = 1.1
MAX_RETRIES = 3
HTTP_TIMEOUT = 20
# Cap on a Yelp response body, checked after the body is fully buffered but
# before JSON.parse. A few MB is far above any legitimate search response. This
# bounds the parse and its allocations only — it does NOT bound the download,
# whose full body is already in memory by the time it is checked.
MAX_BODY_BYTES = 5_000_000

# Lazy Yelp API key: read from the environment/.env on first use, not at require
# time, so requiring this file (tests) never touches the real .env. Memoized so
# the key is read at most once per process.
def yelp_api_key
  @yelp_api_key ||= load_env_key('YELP_API_KEY')
end

# Seconds to wait before retrying a failed API call. `retry_after` is the raw
# Retry-After header value (or nil when the server gave no hint), coerced to a
# float; otherwise fall back to exponential backoff on the zero-based attempt
# index.
def retry_wait(retry_after, attempt)
  retry_after ? retry_after.to_f : (2**attempt)
end

# One persistent Net::HTTP connection per (scheme, host, port), so repeated
# requests to the same API reuse a single TLS handshake instead of paying one per
# call. Opened eagerly (start without a block) so `request` does not stamp
# `Connection: close` and tear the socket down after each response; a stale socket
# is detected by http_request and re-established there. Connections are never
# closed — the pipeline scripts are single-run, so process exit reclaims them.
def http_client(uri, open_timeout:, read_timeout:)
  key = [uri.scheme, uri.host, uri.port]
  clients = (@http_clients ||= {})
  clients[key] ||= begin
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = open_timeout
    http.read_timeout = read_timeout
    http.start
    http
  end
end

# Drop the persistent connection for `uri` so the next request re-establishes it.
def drop_http_client(uri)
  key = [uri.scheme, uri.host, uri.port]
  http = (@http_clients || {}).delete(key)
  http.finish if http && http.started?
rescue StandardError
  nil
end

# Send `req` over the persistent connection for `uri`, reconnecting once when a
# reused socket turns out stale (server closed it while idle between calls). Only
# transport-level errors trigger the reconnect; HTTP status errors (4xx/5xx)
# propagate unchanged so callers keep their own 429/retry handling.
def http_request(uri, req, open_timeout:, read_timeout:)
  http_client(uri, open_timeout: open_timeout, read_timeout: read_timeout).request(req)
rescue Net::OpenTimeout, Net::ReadTimeout, EOFError, IOError, SystemCallError, Net::HTTPBadResponse => e
  warn "http_request: #{e.class} on reused connection; reconnecting once"
  drop_http_client(uri)
  http_client(uri, open_timeout: open_timeout, read_timeout: read_timeout).request(req)
end

# One Yelp search request: build the URI, make the call, cap the parse of the
# (fully-buffered) body, and return the "businesses" array. Returns [] when the
# body exceeds MAX_BODY_BYTES; raises Net::HTTPClientException on 4xx and
# StandardError on transport/parse failures, which the retry loop handles.
def yelp_search_once(params, api_key)
  uri = URI("#{YELP_BASE}/businesses/search")
  uri.query = URI.encode_www_form(params)
  req = Net::HTTP::Get.new(uri)
  req['Authorization'] = "Bearer #{api_key}"
  res = http_request(uri, req, open_timeout: HTTP_TIMEOUT, read_timeout: HTTP_TIMEOUT)
  body = res.body.to_s
  if body.bytesize > MAX_BODY_BYTES
    warn "search_yelp: response body #{body.bytesize} bytes exceeds #{MAX_BODY_BYTES} cap; skipping"
    return []
  end
  JSON.parse(body).fetch('businesses', [])
end

# One Yelp search call with retry/backoff. Returns the "businesses" array, or
# nil after a hard 429 (3 retries exhausted) so callers can abort gracefully.
def search_yelp(params)
  api_key = yelp_api_key
  MAX_RETRIES.times do |attempt|
    return yelp_search_once(params, api_key)
  rescue Net::HTTPClientException => e
    if e.response.code.to_i == 429
      if attempt < MAX_RETRIES - 1
        sleep(retry_wait(e.response['Retry-After'], attempt))
        next
      end
      return nil
    end
    sleep(retry_wait(nil, attempt)) if attempt < MAX_RETRIES - 1
  rescue StandardError => e
    warn "search_yelp attempt #{attempt + 1}/#{MAX_RETRIES} failed: #{e.class}: #{e.message}"
    sleep(retry_wait(nil, attempt)) if attempt < MAX_RETRIES - 1
  end
  []
end
