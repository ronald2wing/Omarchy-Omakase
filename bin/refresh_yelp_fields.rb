#!/usr/bin/env -S -u RUBYOPT -u RUBYLIB -u RUBYGEMS_GEMDEPS -u BUNDLE_GEMFILE -u BUNDLE_PATH -u BUNDLE_BIN_PATH -u GEM_HOME -u GEM_PATH /usr/bin/ruby
# frozen_string_literal: true

# Unified Yelp refresh: fill missing Yelp fields for the whole directory.
#
# Two-phase strategy that minimizes API calls while guaranteeing coverage:
#
#   Phase 1 (bulk): per city, one `term=<t>&location=<city>` search run (50
#   results/call) for each term in BULK_SEARCH_TERMS, matched by `id` (then
#   normalized name) — cheap for the bulk of spots. The term list matters:
#   `term=omakase` alone returns none of kyoto's unfilled spots, while
#   `term=sushi` reaches them, so a spot found under any term fills.
#   Phase 2 (exact): spots the bulk pass missed get a `term=<name>` search,
#   matched by id, normalized name, a normalized-name substring (either name
#   contains the other), or (for pure-CJK titles) an exact raw-title
#   comparison — reliable for curated English names whose Yelp titles differ
#   (kanji, "Sushi Saito" vs "鮨 さいとう").
#
# Re-runnable: every field is guarded by fill-missing, so already-filled spots
# are skipped and only genuine gaps cost an API call. Spots a search proves are
# not on Yelp are recorded in .yelp-refresh-progress, so the unfillable tail is
# never re-searched.
#
# Usage:
#   ruby bin/refresh_yelp_fields.rb            # all cities
#   ruby bin/refresh_yelp_fields.rb tokyo      # one city

require_relative 'pipeline_common'

# Phase 1 search terms, tried in order per city. `omakase` alone reaches most
# spots, but the Japanese cities' unfilled tail lives under `sushi`: a bulk
# `term=omakase` search returns 0 of kyoto's unfilled spots by id or name, while
# `term=sushi` returns them by id. Each term pages independently within the same
# pending maps, so a business found under any term fills its spot.
BULK_SEARCH_TERMS = %w[omakase sushi].freeze

# Phase 1 caps each bulk term's search at this offset (20 pages), the upper bound
# of the window worth paying for per term. YELP_PAGE_SIZE lives in yelp_client.rb
# so collect/refresh can't drift. 1000 = 20 pages of 50. With the marginal-yield
# stop below this is a true safety bound, not the normal stop: a term's loop exits
# when the city's pending maps drain, on a short page, or once pages stop resolving
# pending spots — the offset cap only catches a run that never trips any of those.
YELP_SEARCH_MAX_OFFSET = 1000
# Phase 1 also stops once consecutive pages fail to shrink the pending maps: one
# page costs 1 call and covers up to 50 businesses, so paging pays while it keeps
# resolving pending spots; a leftover spot costs only 1 exact Phase-2 call, so an
# unproductive page is pure waste. A grace of 2 tolerates a single unlucky page
# without allowing a blind run to the cap.
YELP_BULK_UNPRODUCTIVE_PAGE_LIMIT = 2
# Phase 2 exact-name search result count — the matcher keeps only the first
# exact-name match (or the first substring match), so one business is all the
# call can use. A small margin (3) preserves robustness when Yelp's best_match
# returns an unrelated top hit before the real match. The Nominatim city lookup
# (geocode_fallback.rb / backfill_websites.rb) was reduced to limit: 1 for the
# same kind of single-result lookup.
EXACT_SEARCH_LIMIT = 3

# Resume marker for spots that a refresh proved are not on Yelp. Keyed PER SPOT
# via spot_progress_key (pipeline_common) as `name|city_key`: the city suffix is
# what keeps two same-named spots in different cities from colliding within this
# file. The file itself is distinct, so the key cannot collide with the other
# crawlers' shapes (collect_cities' bare city key, backfill_websites' `name|city`,
# reverse_geocode_addresses' `city|name|lat,lon`) even though it shares
# backfill_websites' delimiter.
REFRESH_YELP_PROGRESS = File.join(ROOT, '.yelp-refresh-progress')

def merge_yelp!(entry, business)
  changed = fill_yelp_fields!(entry, business)

  latitude, longitude = rounded_coordinates(business)
  if latitude && longitude
    missing_lat = !entry['lat']
    missing_lon = !entry['lon']
    entry['lat'] ||= latitude
    entry['lon'] ||= longitude
    changed = true if missing_lat || missing_lon
  end
  changed
end

# Core fields Yelp reliably returns; only these trigger a search. image_url/phone
# are omitted: ~2-6% of spots lack them on Yelp itself, so requiring them would
# re-search the same unfillable spots on every run. `is_closed` is checked for
# key presence (false is a valid value), so it is handled separately in
# needs_fill? rather than listed here.
#
# `yelp_id` is included so a spot carrying every other core field but no id is
# still re-searched, letting the id-match phase fill it. Trade-off: a future
# refresh spends extra Yelp API calls on spots missing only their id. The effect
# is latent here — the Yelp API is HTTP-403-blocked from this network, so it
# only appears on another network.
SEARCH_TRIGGER_FIELDS = %w[yelp_url yelp_rating address region_code display_address yelp_id].freeze

# A discount spot (both `discount_window` and `discount` present — the `discount`
# spot kind, a happy-hour deal) is deliberately excluded from every Yelp fill:
# it is sourced from a discount listing, not Yelp, so its missing Yelp fields
# are expected and must never trigger a search.
def needs_fill?(entry)
  return false unless entry
  return false if entry['discount_window'] && entry['discount']

  SEARCH_TRIGGER_FIELDS.any? { |field| !entry[field] } || !entry.key?('is_closed')
end

# ---- main ----
# Phase 1 — bulk term searches matched by id (then name), one bounded page run
# per term. Terms share the pending maps (mutated in place), so a spot found under
# any term drains its keys and is never re-searched by a later term. Mutates the
# shared `state` (filled + need_sleep); returns whether any entry changed (driving
# the caller's single write).
def bulk_phase(pending_by_id:, pending_by_name:, entries:, city_key:, location:, search_counted:, sleeper:, state:)
  bulk_changed = false
  BULK_SEARCH_TERMS.each do |term|
    break if pending_by_id.empty? && pending_by_name.empty?

    offset = 0
    unproductive_pages = 0
    while offset < YELP_SEARCH_MAX_OFFSET && (!pending_by_id.empty? || !pending_by_name.empty?)
      state[:need_sleep] = defer_sleep(sleeper, YELP_SLEEP, state[:need_sleep])

      pending_before = pending_by_id.size + pending_by_name.size
      businesses = search_counted.call('term' => term, 'location' => location,
                                       'limit' => YELP_PAGE_SIZE, 'offset' => offset, 'sort_by' => 'best_match')
      break if businesses.nil? || businesses.empty?

      state[:need_sleep] = true

      businesses.each do |business|
        business_id = business['id']
        business_key = normalize_name(business['name'])
        index = (business_id && pending_by_id[business_id]) || pending_by_name[business_key]
        next unless index && needs_fill?(entries[index])

        if merge_yelp!(entries[index], business)
          state[:filled] += 1
          bulk_changed = true
          puts "  #{entries[index]['name']} (#{city_key}) -> #{business['name']}"
        end
        pending_by_id.delete(business_id) if business_id
        pending_by_name.delete(business_key)
      end
      break if businesses.size < YELP_PAGE_SIZE

      # Productivity is the pending-size delta, not the number of entries filled.
      # An id-matched entry that no longer needs a fill is skipped before its
      # pending key is deleted, so a page that matched such an entry leaves the
      # pending maps unshrunk and reads as unproductive even though it matched
      # something. That skip is exactly why the delta — which does not shrink —
      # is the measure here.
      if pending_by_id.size + pending_by_name.size < pending_before
        unproductive_pages = 0
      else
        unproductive_pages += 1
        break if unproductive_pages >= YELP_BULK_UNPRODUCTIVE_PAGE_LIMIT
      end

      offset += YELP_PAGE_SIZE
    end
  end
  bulk_changed
end

# Phase 2 — exact name search for the leftovers (dedup by entry index, so a spot
# pending under both its id and its name is searched exactly once). The matcher
# accepts by id, by normalized name, by a normalized-name substring (either name
# contains the other), or — for a pure-CJK title that normalizes to "" — by an
# exact raw-title comparison. Mutates the shared `state` (filled + need_sleep);
# returns [changed, tried_keys] for the caller's persist_then_mark.
def exact_phase(pending_by_id:, pending_by_name:, entries:, city_key:, location:, search_counted:, sleeper:, state:)
  changed = false
  tried_keys = []
  (pending_by_id.values + pending_by_name.values).uniq.each do |index|
    next unless needs_fill?(entries[index])

    state[:need_sleep] = defer_sleep(sleeper, YELP_SLEEP, state[:need_sleep])

    name = entries[index]['name'].to_s

    businesses = search_counted.call('term' => name, 'location' => location, 'limit' => EXACT_SEARCH_LIMIT)
    state[:need_sleep] = true
    next if businesses.nil?

    # An empty exact result means the spot is genuinely not on Yelp — record it
    # as tried so a repeat run never re-pays this search. A non-empty result
    # that still fails to match is deliberately NOT marked: the spot may exist
    # under a title the matcher missed, so the next run retries it.
    if businesses.empty?
      tried_keys << spot_progress_key(entries[index]['name'], city_key)
      next
    end

    spot_id = entries[index]['yelp_id']
    target = normalize_name(name)
    raw_target = collapse_name(name)
    best = nil
    businesses.each do |business|
      # id match: exact identity, the strongest signal — accepts a CJK-titled
      # spot (normalized name "") and a Latin spot whose Yelp title drifted.
      if spot_id && business['id'] == spot_id
        best = business
        break
      end
      candidate_key = normalize_name(business['name'])
      if target != '' && candidate_key == target
        best = business
        break
      end
      if target != '' && candidate_key != '' && (target.include?(candidate_key) || candidate_key.include?(target))
        best ||= business
      end
      # CJK fallback: a pure-CJK title normalizes to "", so the name paths
      # above can never fire. An exact raw-title match (case/whitespace folded)
      # only — unrelated names can't collide.
      if target == '' && collapse_name(business['name']) == raw_target
        best = business
        break
      end
    end
    if best && merge_yelp!(entries[index], best)
      state[:filled] += 1
      puts "  #{name} (#{city_key}) -> #{best['name']}"
      changed = true
    end
  end
  [changed, tried_keys]
end

# Fill missing Yelp fields for every city file under `data_dir` (or just
# `city_arg`). Collaborators are injected so the orchestration is testable
# off-network: `search` is the Yelp client (a stub can be passed), `data_dir`
# isolates every file read/write to a temp dir, `progress_path` records
# successfully-empty spots so a repeat run never re-searches the unfillable
# tail, and `sleeper` lets tests suppress the real rate-limit pauses. `dry_run`
# guards the writes (progress + data files) but still calls the Yelp API, so a
# preview fetches for real and persists nothing. Defaults keep the CLI path
# identical.
def refresh_yelp_fields(search: method(:search_yelp), data_dir: DATA_DIR,
                        progress_path: REFRESH_YELP_PROGRESS,
                        city_arg: nil, dry_run: false,
                        sleeper: ->(secs) { sleep(secs) })
  files = select_city_files(data_filenames(data_dir), city_arg)

  done = load_progress(progress_path)

  calls = 0
  # Shared mutable run state both phases accumulate. Threaded as a hash so the
  # tallies survive a LocationNotFound raised mid-phase: the per-city rescue
  # skips to the next city without losing the sleep pacing or fills already
  # counted in this one.
  state = { filled: 0, need_sleep: false }
  failures = build_failure_guard(
    abort_text: 'failed searches (rate limit, bad key, or network).'
  )

  # One counted search attempt: `calls` increments before the nil check, so a
  # failed search (nil — rate limit exhausted, bad key, network) still counts
  # toward the reported "API calls". Only a raised LocationNotFound (an
  # unresolvable city) skips the count, since the raise never reaches it.
  search_counted = lambda do |params|
    businesses = search.call(params)
    calls += 1
    guard_result(failures, businesses)
  end

  progress_file = open_progress(progress_path, dry_run: dry_run)
  # `state[:need_sleep]` is one flag for the whole run: set after a request that
  # would previously have been followed by a sleep, cleared by the sleep itself.
  # The sleep therefore fires only when another request actually follows (never
  # after the final request of the run), while inter-phase and inter-city pacing
  # is preserved.

  files.each do |filename|
    city_key = city_key_for(filename)
    location = CITIES.dig(city_key, :location)
    next unless location

    begin
      path = File.join(data_dir, filename)
      entries = load_jsonl(path)

      pending_by_id = {}
      pending_by_name = {}
      entries.each_with_index do |entry, index|
        next unless needs_fill?(entry)
        next if done.include?(spot_progress_key(entry['name'], city_key))

        pending_by_id[entry['yelp_id']] = index if entry['yelp_id']
        normalized = normalized_name_or_nil(entry['name'])
        pending_by_name[normalized] = index if normalized
      end
      next if pending_by_id.empty? && pending_by_name.empty?

      puts "\n#{city_key}: #{pending_by_id.size + pending_by_name.size} keys to fill"

      # Phase 1 — bulk term searches matched by id (then name), one bounded page
      # run per term.
      bulk_changed = bulk_phase(pending_by_id: pending_by_id, pending_by_name: pending_by_name,
                                entries: entries, city_key: city_key, location: location,
                                search_counted: search_counted, sleeper: sleeper, state: state)
      write_atomic(path, entries) if bulk_changed && !dry_run

      # Phase 2 — exact name search for the leftovers.
      changed, tried_keys = exact_phase(pending_by_id: pending_by_id, pending_by_name: pending_by_name,
                                        entries: entries, city_key: city_key, location: location,
                                        search_counted: search_counted, sleeper: sleeper, state: state)

      # Persist-then-mark: a fill reaches disk before the tried key is recorded, so
      # a crash between the two leaves an unwritten fill unmarked and retried.
      # Marks only record successfully-empty searches (nil is never marked), so a
      # transient outage retries instead of a permanent skip.
      persist_then_mark(changed && !dry_run, path, entries, progress_file, tried_keys)
    rescue LocationNotFound
      # Yelp cannot resolve this city's location string at all — city-level,
      # deterministic, and permanent, so retrying any of its searches can never
      # succeed. Warn once (naming the city and the location string) and move on,
      # without feeding the consecutive-failure guard: this is an unsearchable
      # city, not a dead key/network.
      warn_unresolvable_city(city_key, location)
    end
  end

  close_progress(progress_file)

  puts "\nDone: #{state[:filled]} spots gained fields (#{calls} API calls)"
  { filled: state[:filled], calls: calls }
end

if __FILE__ == $PROGRAM_NAME
  flags = parse_common_flags(ARGV, supported: %w[--dry-run --help -h])
  if flags.help
    print_usage('refresh_yelp_fields.rb',
                'Fill missing Yelp fields for the whole directory.',
                [['--dry-run', 'Write nothing (still calls the Yelp API).']],
                '[city]')
    exit 0
  end
  result = refresh_yelp_fields(city_arg: flags.city, dry_run: flags.dry_run)
  # A run that made API calls but filled nothing failed (the consecutive-failure
  # guard only aborts after 8 in a row, so a short all-nil run reaches here).
  exit 1 if result[:calls].positive? && result[:filled].zero?
end
