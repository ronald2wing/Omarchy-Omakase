#!/usr/bin/env -S -u RUBYOPT -u RUBYLIB -u RUBYGEMS_GEMDEPS -u BUNDLE_GEMFILE -u BUNDLE_PATH -u BUNDLE_BIN_PATH -u GEM_HOME -u GEM_PATH /usr/bin/ruby
# frozen_string_literal: true

# Yelp Fusion HTTP client: persistent connections, retry/backoff, and the search
# endpoint wrapper. Kept in one file so fetch/refresh don't drift apart.

require 'net/http'
require 'uri'
require 'json'

YELP_BASE = 'https://api.yelp.com/v3'
# Seconds to pause between Yelp API calls (collect_cities.rb and
# refresh_yelp_fields.rb hand this to their sleeper). 1.1 is load-bearing for
# rate-limit safety: it paces a run below Yelp Fusion's throttle, and lowering
# it invites 429s whose Retry-After backoff (see search_yelp) stalls the run
# far longer than the pause ever saved.
YELP_SLEEP = 1.1
# Page size for Yelp search calls, shared by collect_cities.rb and
# refresh_yelp_fields.rb so their pagination loops can't drift apart.
YELP_PAGE_SIZE = 50
# Total attempts per search call (1 initial + 2 retries) — `search_yelp` runs
# `YELP_MAX_ATTEMPTS.times`. Named for attempts, not retries: "max retries" read
# as 3 retries (4 attempts), which is off by one.
YELP_MAX_ATTEMPTS = 3
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
# SystemCallError is deliberately broad: it spans local Errno faults (ENOSPC
# disk-full, EACCES, EMFILE, …) as well as socket errors, so a disk-full or
# permission failure during a request is misread as a transport problem and
# retried. Only this set and a 429 are retryable (see search_yelp); every other
# error — a permanent HTTP status or a parse failure — fails fast, so the
# occasional wasted retry is bounded to genuine transport faults.
HTTP_TRANSPORT_ERRORS = [
  Net::OpenTimeout, Net::ReadTimeout, IOError, SystemCallError, Net::HTTPBadResponse
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

# Raised by yelp_search_once when a non-2xx body carries error.code
# "LOCATION_NOT_FOUND" — Yelp cannot resolve the request's `location` string at
# all. Unlike a 429 or a transport error this is city-level, deterministic, and
# permanent: re-sending the same location can never succeed, so the orchestrator
# catches it to spend one call per unresolvable city and skip the rest, rather
# than feeding it into the consecutive-failure guard (which would misread an
# unsearchable city as a dead key/network). Carries the HTTP status and the
# parsed error.code, mirroring RateLimited's Retry-After payload.
class LocationNotFound < StandardError
  attr_reader :status, :error_code

  def initialize(status, error_code)
    @status = status
    @error_code = error_code
    super("Yelp could not resolve the location (HTTP #{status}, #{error_code})")
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
rescue IOError, SystemCallError
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
  warn "http_request: #{e.class}; reconnecting once"
  drop_http_client(uri)
  send.call
  status
end

# Parse the `error.code` out of a non-2xx response body, defensively: the body
# may be absent (nil), empty, or non-JSON, and none of those may raise a parse
# error of their own — they simply carry no code. Only a Hash body whose `error`
# is a Hash with a `code` yields one, so `nil` means "no typed error".
def yelp_error_code(body)
  parsed = JSON.parse(body.to_s)
  return nil unless parsed.is_a?(Hash)

  error = parsed['error']
  error.is_a?(Hash) ? error['code'] : nil
rescue JSON::ParserError
  nil
end

# One Yelp search request: build the URI, stream the body capped at
# MAX_BODY_BYTES, and return the "businesses" array. A 429 raises RateLimited
# (carrying the Retry-After hint); a non-2xx body whose error.code is
# LOCATION_NOT_FOUND raises LocationNotFound (carrying status + code); any other
# non-2xx raises StandardError, mirroring backfill_websites's Net::HTTPSuccess
# guard so an error body is never parsed as businesses. Returns nil when the
# streamed body exceeds the cap — a too-large body is a hard failure, not a
# successful-but-empty result, so it is not retried. A transport failure raises
# and is retried by search_yelp; a non-2xx non-429 status and a parse failure
# also raise, and search_yelp treats them as permanent — it fails fast instead
# of re-sending them.
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
  unless (200..299).cover?(status)
    code = yelp_error_code(body)
    raise LocationNotFound.new(status, code) if code == 'LOCATION_NOT_FOUND'

    raise "Yelp search returned HTTP #{status}"
  end

  JSON.parse(body).fetch('businesses', [])
rescue BodyTooLarge
  warn "yelp_search_once: response body exceeds #{MAX_BODY_BYTES} cap; skipping"
  nil
end

# One Yelp search call with retry/backoff. Retries only what is transient — a
# 429 (backing off by its Retry-After hint) and transport errors — because a
# permanent HTTP status (401/403/400) is rejected the same way on every attempt,
# so re-sending it only multiplies wasted calls. A LOCATION_NOT_FOUND is
# re-raised, not retried and not folded into nil: it is city-level and permanent,
# so the orchestrator needs the typed error to skip the city rather than treat it
# as a hard failure. Returns the "businesses" array, or nil on a hard failure: a
# 429 that exhausted its retries, a transport failure that exhausted its retries,
# or any non-retryable error (a permanent HTTP status or a parse failure). `[]`
# is reserved for a request that completed with no usable businesses, so callers
# can tell "no results" from "the call never got through" — the difference
# between a genuinely empty city and a poisoned resume marker.
def search_yelp(params)
  api_key = yelp_api_key
  YELP_MAX_ATTEMPTS.times do |attempt|
    return yelp_search_once(params, api_key)
  rescue RateLimited => e
    if attempt < YELP_MAX_ATTEMPTS - 1
      sleep(retry_wait(e.retry_after, attempt))
      next
    end
    return nil
  rescue *HTTP_TRANSPORT_ERRORS => e
    warn "search_yelp attempt #{attempt + 1}/#{YELP_MAX_ATTEMPTS} failed: #{e.class}: #{e.message}"
    sleep(retry_wait(nil, attempt)) if attempt < YELP_MAX_ATTEMPTS - 1
  rescue LocationNotFound
    # Permanent and city-level — propagate the typed error to the orchestrator so
    # it can skip the city instead of counting a hard failure toward the guard.
    raise
  rescue StandardError => e
    warn "search_yelp: #{e.class}: #{e.message} (non-retryable — failing fast)"
    return nil
  end
  nil
end
