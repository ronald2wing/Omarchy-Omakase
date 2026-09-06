#!/usr/bin/env -S -u RUBYOPT -u RUBYLIB -u RUBYGEMS_GEMDEPS -u BUNDLE_GEMFILE -u BUNDLE_PATH -u BUNDLE_BIN_PATH -u GEM_HOME -u GEM_PATH /usr/bin/ruby
# frozen_string_literal: true

# Yelp Fusion HTTP client: persistent connections, retry/backoff, and the search
# endpoint wrapper. Kept in one file so fetch/refresh don't drift apart.

require 'net/http'
require 'uri'
require 'json'

YELP_BASE = 'https://api.yelp.com/v3'
YELP_SLEEP = 1.1
# Page size for Yelp search calls, shared by collect_cities.rb and
# refresh_yelp_fields.rb so their pagination loops can't drift apart.
YELP_PAGE_SIZE = 50
MAX_RETRIES = 3
HTTP_TIMEOUT = 20
# Cap on a Yelp response body, enforced while the body is streamed in chunks:
# read_capped_body aborts the instant the running byte count crosses it, so a
# chunked or Content-Length-less response cannot balloon memory. A few MB is far
# above any legitimate search response.
MAX_BODY_BYTES = 5_000_000

# Transport-level errors http_request may still raise after its single reconnect
# attempt (a second failure propagates). Adapters that present a network failure
# as "no result" rescue exactly this set; leaving programming errors
# (NoMethodError, typos) out means bugs propagate instead of being swallowed.
HTTP_TRANSPORT_ERRORS = [
  Net::OpenTimeout, Net::ReadTimeout, EOFError, IOError, SystemCallError, Net::HTTPBadResponse
].freeze

# Raised by read_capped_body the moment a streamed body crosses MAX_BODY_BYTES,
# leaving the response half-read. http_request drops the connection and re-raises.
class BodyTooLarge < StandardError; end

# Raised by yelp_search_once on a 429 response, carrying the server's Retry-After
# header (seconds, or nil when absent) so search_yelp can back off by the server's
# hint instead of the default exponential backoff.
class RateLimited < StandardError
  attr_reader :retry_after

  def initialize(retry_after)
    @retry_after = retry_after
    super(retry_after ? "429 rate limited (Retry-After: #{retry_after})" : '429 rate limited')
  end
end

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
  # Best-effort teardown: a close error (already-closed socket, reset peer) is
  # ignorable — the connection is being dropped regardless, so the next request
  # re-establishes it.
  http.finish if http && http.started?
rescue IOError, EOFError, SystemCallError
  nil
end

# Stream a response body in chunks into one String, raising BodyTooLarge the
# instant the running byte count crosses max_bytes. This bounds the download
# itself (unlike res.body, which buffers the whole transfer before it can be
# checked), so a chunked response without a Content-Length cannot balloon memory.
def read_capped_body(response, max_bytes:)
  body = +''
  response.read_body do |chunk|
    body << chunk
    raise BodyTooLarge if body.bytesize > max_bytes
  end
  body
end

# Send `req` over the persistent connection for `uri`, yielding the response to
# the block in streaming mode so the block can read the body in chunks (and cap
# it mid-download). Reconnects once when a reused socket turns out stale (server
# closed it while idle between calls). Only transport-level errors trigger the
# reconnect; a BodyTooLarge abort drops the connection and re-raises. Returns the
# numeric HTTP status code, captured from the response before the body is read —
# Net::HTTP's block form does not raise on non-2xx, so callers keep their own
# status/429/retry handling.
def http_request(uri, req, open_timeout:, read_timeout:, &block)
  status = nil
  send = lambda do
    http_client(uri, open_timeout: open_timeout, read_timeout: read_timeout).request(req) do |res|
      status = res.code.to_i
      block&.call(res)
    end
  end
  send.call
  status
rescue BodyTooLarge
  # A mid-download cap abort leaves the body half-read on the persistent
  # connection; drop it so the next request re-establishes a clean socket.
  drop_http_client(uri)
  raise
rescue *HTTP_TRANSPORT_ERRORS => e
  warn "http_request: #{e.class} on reused connection; reconnecting once"
  drop_http_client(uri)
  send.call
  status
end

# One Yelp search request: build the URI, stream the body capped at
# MAX_BODY_BYTES, and return the "businesses" array. A 429 raises RateLimited
# (carrying the Retry-After hint); any other non-2xx raises StandardError,
# mirroring backfill_websites's Net::HTTPSuccess guard so an error body is never
# parsed as businesses. Returns [] when the streamed body exceeds the cap (a
# too-large body is not transient, so it is not retried); transport/parse
# failures raise StandardError, which the retry loop handles.
def yelp_search_once(params, api_key)
  uri = URI("#{YELP_BASE}/businesses/search")
  uri.query = URI.encode_www_form(params)
  req = Net::HTTP::Get.new(uri)
  req['Authorization'] = "Bearer #{api_key}"
  body = nil
  retry_after = nil
  status = http_request(uri, req, open_timeout: HTTP_TIMEOUT, read_timeout: HTTP_TIMEOUT) do |res|
    retry_after = res['Retry-After']
    body = read_capped_body(res, max_bytes: MAX_BODY_BYTES)
  end
  raise RateLimited.new(retry_after) if status == 429
  raise "Yelp search returned HTTP #{status}" unless (200..299).cover?(status)

  JSON.parse(body).fetch('businesses', [])
rescue BodyTooLarge
  warn "search_yelp: response body exceeds #{MAX_BODY_BYTES} cap; skipping"
  []
end

# One Yelp search call with retry/backoff. Returns the "businesses" array, or
# nil on a hard failure: a 429 that exhausted its retries, or any persistent
# error (missing/invalid key, non-retryable HTTP status, transport failure).
# `[]` is reserved for a request that completed with no usable businesses, so
# callers can tell "no results" from "the call never got through" — the
# difference between a genuinely empty city and a poisoned resume marker.
def search_yelp(params)
  api_key = yelp_api_key
  MAX_RETRIES.times do |attempt|
    return yelp_search_once(params, api_key)
  rescue RateLimited => e
    if attempt < MAX_RETRIES - 1
      sleep(retry_wait(e.retry_after, attempt))
      next
    end
    return nil
  rescue StandardError => e
    warn "search_yelp attempt #{attempt + 1}/#{MAX_RETRIES} failed: #{e.class}: #{e.message}"
    sleep(retry_wait(nil, attempt)) if attempt < MAX_RETRIES - 1
  end
  nil
end
