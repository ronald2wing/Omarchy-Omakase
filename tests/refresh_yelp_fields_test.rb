#!/usr/bin/env ruby
# frozen_string_literal: true

# Unit tests for refresh_yelp_fields.rb: the merge/fill pure helpers
# (merge_yelp!, needs_fill?, collapse_name) and the bulk/exact orchestration
# + resume loops (no API calls — main is guarded by
# `if __FILE__ == $PROGRAM_NAME`, so require only loads functions).

require 'minitest/autorun'
require_relative '../bin/refresh_yelp_fields'
require_relative 'test_helper'

class RefreshYelpFieldsTest < Minitest::Test
  def test_merge_yelp_fills_missing_only
    entry = {}
    business = yelp_business_fixture
    assert merge_yelp!(entry, business), 'first merge should change'

    # Assert every YELP_FILL_MAP row table-driven: this is the first and only
    # merge_yelp! fill test, so it covers all 12 rows — a fill regression in any
    # field (phone/transactions/country/region_code/image_url/review_count, …) is
    # caught here, not elsewhere. Expected values mirror the fixture's Yelp JSON;
    # the coverage assertion fails if a row is added to the map without a
    # matching expected value here.
    expected = {
      'yelp_url' => 'https://yelp.com/biz/abc123',
      'yelp_rating' => 4.5,
      'yelp_review_count' => 10,
      'yelp_price_level' => '$$$',
      'yelp_id' => 'abc123',
      'image_url' => 'https://img',
      'phone' => '+1 555',
      'transactions' => ['delivery'],
      'address' => '1 Main St',
      'region_code' => 'NY',
      'country' => 'US',
      'display_address' => ['1 Main St']
    }

    assert_equal YELP_FILL_MAP.keys.sort, expected.keys.sort,
                 'the expected table covers every YELP_FILL_MAP row'
    YELP_FILL_MAP.each_key do |key|
      assert_equal expected[key], entry[key], "merge_yelp! fills #{key} from the fixture"
    end

    # The two fields YELP_FILL_MAP cannot express are handled inline in merge_yelp!.
    assert_equal false, entry['is_closed']
    assert_equal 40.7, entry['lat']
  end

  def test_merge_yelp_does_not_overwrite_existing
    entry = { 'yelp_rating' => 5.0 }
    business = { 'rating' => 3.0 }
    refute merge_yelp!(entry, business), 'no change when field exists'
    assert_equal 5.0, entry['yelp_rating'], 'existing value preserved'
  end

  def test_merge_yelp_fills_missing_coordinate_and_reports_change
    entry = { 'lat' => 40.7 }
    business = { 'coordinates' => { 'latitude' => 40.7, 'longitude' => -74.0 } }
    assert merge_yelp!(entry, business), 'a missing coordinate must report a change'
    assert_equal 40.7, entry['lat']
    assert_equal(-74.0, entry['lon'])

    # The same branch reports no change when both coordinates are already set.
    already = { 'lat' => 40.7, 'lon' => -74.0 }
    refute merge_yelp!(already, business), 'coordinates already set must not report a change'
    assert_equal 40.7, already['lat']
    assert_equal(-74.0, already['lon'])
  end

  def test_fill_predicate_core_fields
    assert needs_fill?({ 'name' => 'X' }), 'bare entry needs fill'
    refute needs_fill?(nil), 'nil needs no fill'
    refute needs_fill?({ 'discount_window' => '8pm', 'discount' => '50%' }), 'discount skipped'

    full = { 'yelp_url' => 'u', 'yelp_rating' => 4.0, 'is_closed' => false,
             'address' => 'a', 'region_code' => 's', 'display_address' => ['a'],
             'yelp_id' => 'abc123' }
    refute needs_fill?(full), 'core-complete entry needs no fill (image_url/phone optional)'

    missing_id = full.reject { |key, _value| key == 'yelp_id' }
    assert needs_fill?(missing_id),
           'a spot missing only its yelp_id is re-searched so the id phase can fill it'
  end

  def test_collapse_name_folds_case_and_whitespace_but_keeps_non_latin
    assert_equal 'sushi saito', collapse_name('  Sushi   Saito  '), 'lowercase + whitespace collapse'
    assert_equal '鮨 さいとう', collapse_name('鮨 さいとう'), 'non-Latin title survives the fold'
    assert_equal 'くら寿司福岡飯倉店', collapse_name('くら寿司福岡飯倉店'), 'pure CJK keeps every character'
    assert_equal '', collapse_name('   '), 'blank collapses to empty'
    assert_equal '', collapse_name(nil), 'nil collapses to empty'
  end
end

class RefreshYelpFieldsOrchestrationTest < Minitest::Test
  include TmpDataDirHelper

  def progress_files
    { progress: '.yelp-refresh-progress' }
  end

  def write_city(city, entry)
    write_atomic(File.join(@data_dir, "#{city}.jsonl"), [entry])
  end

  def test_fills_missing_fields_and_reports_counts
    write_city('tokyo', { 'name' => 'Sushi Saito' })

    result = refresh_yelp_fields(search: ->(_params) { [yelp_business_fixture] },
                                 data_dir: @data_dir, progress_path: @progress, sleeper: NO_SLEEP)

    assert_equal({ filled: 1, calls: 1 }, result)
    entry = load_jsonl(File.join(@data_dir, 'tokyo.jsonl')).first
    assert_equal 'https://yelp.com/biz/abc123', entry['yelp_url']
    assert_equal 4.5, entry['yelp_rating']
    assert_equal false, entry['is_closed']
  end

  # A full page of fillers that match nothing pending: each term's bulk loop must
  # stop after YELP_BULK_UNPRODUCTIVE_PAGE_LIMIT unproductive pages, not run to
  # the offset cap — so every term in BULK_SEARCH_TERMS costs exactly the grace
  # limit, never a full crawl.
  def test_bulk_stops_after_unproductive_full_pages
    write_city('tokyo', { 'name' => 'Sushi Saito' })
    filler_page = Array.new(YELP_PAGE_SIZE) { |i| { 'name' => "Filler #{i}", 'id' => "filler-#{i}" } }
    bulk_calls = 0
    stub = lambda do |params|
      if BULK_SEARCH_TERMS.include?(params['term'])
        bulk_calls += 1
        filler_page
      else
        [] # exact Phase 2 misses, so the leftover stays unfilled
      end
    end

    result = refresh_yelp_fields(search: stub, data_dir: @data_dir, progress_path: @progress, sleeper: NO_SLEEP)

    assert_equal YELP_BULK_UNPRODUCTIVE_PAGE_LIMIT * BULK_SEARCH_TERMS.size, bulk_calls,
                 'unproductive full pages stop at the grace limit per term, not the offset cap'
    assert_equal({ filled: 0, calls: YELP_BULK_UNPRODUCTIVE_PAGE_LIMIT * BULK_SEARCH_TERMS.size + 1 }, result)
  end

  # A business reachable only under the second bulk term (sushi), not omakase,
  # still fills a pending spot: the terms share the pending maps, so a hit under
  # any term drains the spot's keys and skips the exact pass.
  def test_business_found_under_second_term_still_fills
    write_city('tokyo', { 'name' => 'Sushi Saito' })
    stub = lambda do |params|
      params['term'] == 'sushi' ? [yelp_business_fixture] : []
    end

    result = refresh_yelp_fields(search: stub, data_dir: @data_dir, progress_path: @progress, sleeper: NO_SLEEP)

    assert_equal({ filled: 1, calls: 2 }, result,
                 'omakase returns empty, sushi fills by name, and the drained maps skip the exact pass')
    assert_equal 'https://yelp.com/biz/abc123',
                 load_jsonl(File.join(@data_dir, 'tokyo.jsonl')).first['yelp_url']
  end

  # A pure-CJK title is no longer guarded out of Phase 2: it is issued as an
  # exact term and filled by the raw-title fallback. The returned business's id
  # differs from the spot's, so the id path cannot be what fills it.
  def test_cjk_name_is_not_skipped_from_phase_two
    name = 'くら寿司福岡飯倉店'
    write_city('tokyo', { 'name' => name, 'yelp_id' => 'stale-id' })
    cjk_business = { 'name' => name, 'id' => 'different-id',
                     'url' => 'https://yelp.com/biz/different-id', 'rating' => 4.5,
                     'is_closed' => false }
    terms = []
    result = refresh_yelp_fields(
      search: lambda do |params|
        terms << params['term']
        BULK_SEARCH_TERMS.include?(params['term']) ? [] : [cjk_business]
      end,
      data_dir: @data_dir, progress_path: @progress, sleeper: NO_SLEEP
    )

    assert_includes terms, name, 'the CJK name is issued as a Phase 2 term (the old guard is gone)'
    assert_equal({ filled: 1, calls: BULK_SEARCH_TERMS.size + 1 }, result)
    assert_equal 'https://yelp.com/biz/different-id',
                 load_jsonl(File.join(@data_dir, 'tokyo.jsonl')).first['yelp_url']
  end

  # An id match fills a spot whose normalized name is empty (pure CJK) even
  # though its name path is dead — the id is the acceptance path.
  def test_id_match_fills_spot_with_empty_normalized_name
    write_city('tokyo', { 'name' => 'くら寿司福岡飯倉店', 'yelp_id' => 'abc123' })
    stub = lambda do |params|
      BULK_SEARCH_TERMS.include?(params['term']) ? [] : [yelp_business_fixture]
    end

    result = refresh_yelp_fields(search: stub, data_dir: @data_dir, progress_path: @progress, sleeper: NO_SLEEP)

    assert_equal({ filled: 1, calls: BULK_SEARCH_TERMS.size + 1 }, result)
    assert_equal 'https://yelp.com/biz/abc123',
                 load_jsonl(File.join(@data_dir, 'tokyo.jsonl')).first['yelp_url']
  end

  # A productive first page (one pending spot resolved) followed by unproductive
  # full pages: the grace counter resets on the productive page, so paging stops
  # YELP_BULK_UNPRODUCTIVE_PAGE_LIMIT pages after it, not immediately.
  def test_productive_page_resets_the_unproductive_grace
    write_atomic(File.join(@data_dir, 'tokyo.jsonl'),
                 [{ 'name' => 'Sushi Saito' }, { 'name' => 'Sushi Edo' }])
    productive_page = Array.new(YELP_PAGE_SIZE) do |i|
      i.zero? ? yelp_business_fixture : { 'name' => "Filler #{i}", 'id' => "filler-#{i}" }
    end
    filler_page = Array.new(YELP_PAGE_SIZE) { |i| { 'name' => "Filler #{i}", 'id' => "filler-#{i}" } }
    bulk_calls = 0
    stub = lambda do |params|
      if params['term'] == 'omakase'
        bulk_calls += 1
        bulk_calls == 1 ? productive_page : filler_page
      else
        []
      end
    end

    refresh_yelp_fields(search: stub, data_dir: @data_dir, progress_path: @progress, sleeper: NO_SLEEP)

    assert_equal 1 + YELP_BULK_UNPRODUCTIVE_PAGE_LIMIT, bulk_calls,
                 'one productive page resets the grace, so paging stops two pages later'
  end

  # A full page that drains the pending maps must still exit after that single
  # page (regression guard for the pre-existing drain exit alongside the new
  # unproductive-page stop).
  def test_bulk_stops_immediately_when_pending_drains_on_a_full_page
    write_city('tokyo', { 'name' => 'Sushi Saito' })
    full_page = Array.new(YELP_PAGE_SIZE) do |i|
      i.zero? ? yelp_business_fixture : { 'name' => "Filler #{i}", 'id' => "filler-#{i}" }
    end
    calls = 0
    stub = ->(_params) { calls += 1; full_page }

    result = refresh_yelp_fields(search: stub, data_dir: @data_dir, progress_path: @progress, sleeper: NO_SLEEP)

    assert_equal 1, calls, 'pending drained on a full page, so the loop exits before a second page'
    assert_equal({ filled: 1, calls: 1 }, result)
  end

  def test_does_not_write_file_when_nothing_changed
    path = File.join(@data_dir, 'tokyo.jsonl')
    write_atomic(path, [{ 'name' => 'Sushi Saito' }])
    before = File.read(path)

    terms = []
    result = refresh_yelp_fields(
      search: lambda do |params|
        terms << params['term']
        [{ 'name' => 'Ramen House', 'id' => 'xyz', 'rating' => 3.0 }]
      end,
      data_dir: @data_dir, progress_path: @progress, sleeper: NO_SLEEP
    )

    assert_equal({ filled: 0, calls: BULK_SEARCH_TERMS.size + 1 }, result)
    # One call per bulk term plus one exact call for the single unfilled spot:
    # each bulk hit ("Ramen House") fails to match "Sushi Saito", then the exact
    # name search runs once.
    assert_equal BULK_SEARCH_TERMS + ['Sushi Saito'], terms
    assert_equal before, File.read(path), 'no write when nothing changed'
  end

  def test_abort_stops_after_consecutive_hard_failures
    # Each pending city file costs three hard-failure calls (one per bulk term,
    # then one exact), so four files (12 failures) reach MAX_CONSECUTIVE_FAILURES
    # (8) and trigger the abort.
    %w[tokyo osaka kyoto fukuoka].each { |city| write_city(city, { 'name' => 'Sushi Saito' }) }
    assert_aborts_on_consecutive_failures do |hard_failure|
      refresh_yelp_fields(search: hard_failure, data_dir: @data_dir, progress_path: @progress, sleeper: NO_SLEEP)
    end
  end

  # A LOCATION_NOT_FOUND city spends one call, skips both phases, and is not fed
  # to the consecutive-failure guard — the next city is still processed and the
  # run completes instead of aborting.
  def test_location_not_found_skips_city_without_tripping_the_guard
    write_city('seoul', { 'name' => 'Sushi Seoul' })
    write_city('tokyo', { 'name' => 'Sushi Saito' })

    seoul_calls = 0
    stub = lambda do |params|
      if params['location'] == 'Seoul, South Korea'
        seoul_calls += 1
        raise LocationNotFound.new(400, 'LOCATION_NOT_FOUND')
      end
      [yelp_business_fixture]
    end

    result = nil
    _stdout, stderr = capture_io do
      result = refresh_yelp_fields(search: stub, data_dir: @data_dir,
                                   progress_path: @progress, sleeper: NO_SLEEP)
    end

    assert_equal 1, seoul_calls, 'one call spent on the unresolvable city, then it is skipped'
    assert_equal({ filled: 1, calls: 1 }, result,
                 'the next city is still processed; the skipped city counts as neither a call nor a failure')
    assert_match(/seoul/, stderr, 'the warning names the city')
    assert_match(/Seoul, South Korea/, stderr, 'the warning names the location string')

    seoul_entry = load_jsonl(File.join(@data_dir, 'seoul.jsonl')).first
    refute seoul_entry.key?('yelp_url'), 'the unresolvable city gains no fields'
    assert_equal 'https://yelp.com/biz/abc123',
                 load_jsonl(File.join(@data_dir, 'tokyo.jsonl')).first['yelp_url'],
                 'the following city still fills'
  end
end

class RefreshYelpFieldsResumeTest < Minitest::Test
  include TmpDataDirHelper

  def progress_files
    { progress: '.yelp-refresh-progress' }
  end

  def write_city(entry)
    write_atomic(File.join(@data_dir, 'tokyo.jsonl'), [entry])
  end

  def run_refresh(provider)
    run_pipeline(provider, via: method(:refresh_yelp_fields), provider_keyword: :search)
  end

  def test_hard_failure_is_not_marked_tried
    assert_marking_contract(
      ->(result) do
        write_city({ 'name' => 'Sushi Saito' })
        run_refresh(->(_params) { result })
      end,
      -> { load_progress(@progress) },
      ['Sushi Saito|tokyo']
    )
  end

  def test_fill_writes_data_file_before_marking_tried
    write_atomic(File.join(@data_dir, 'tokyo.jsonl'),
                 [{ 'name' => 'Sushi Saito' }, { 'name' => 'Sushi Edo' }])
    key = 'Sushi Edo|tokyo'
    provider = lambda do |params|
      params['term'] == 'Sushi Saito' ? [yelp_business_fixture] : []
    end
    progress_at_write = capture_progress_marker_at_write(
      @progress, ->(progress) { progress.include?(key) }
    ) do
      run_refresh(provider)
    end

    assert_equal false, progress_at_write,
                 'the tried key is not yet written when the data file is persisted'
    assert_includes load_progress(@progress), key, 'the key is marked after the fill'
  end

  def test_fully_marked_spot_issues_no_search
    write_city({ 'name' => 'Sushi Saito' })
    File.write(@progress, "Sushi Saito|tokyo\n")
    calls = 0
    run_refresh(->(_params) { calls += 1; [] })

    assert_equal 0, calls, 'a fully-marked spot issues no Yelp call'
  end

  # A nil exact result must skip only that spot, not abort the whole city's
  # exact pass: the later spot is still searched and filled, and the failed
  # spot is never marked tried.
  def test_failed_exact_search_does_not_abort_the_rest_of_the_city
    write_atomic(File.join(@data_dir, 'tokyo.jsonl'),
                 [{ 'name' => 'Sushi Saito' }, { 'name' => 'Sushi Edo' }])
    edo = yelp_business_fixture.merge('name' => 'Sushi Edo', 'id' => 'edo1',
                                      'url' => 'https://yelp.com/biz/edo1')
    provider = lambda do |params|
      case params['term']
      when 'Sushi Saito' then nil
      when 'Sushi Edo' then [edo]
      else []
      end
    end

    result = refresh_yelp_fields(search: provider, data_dir: @data_dir,
                                 progress_path: @progress, sleeper: NO_SLEEP)

    assert_equal({ filled: 1, calls: 4 }, result,
                 '2 bulk + 1 failed exact + 1 successful exact; the failed attempt counts as a call')
    entries = load_jsonl(File.join(@data_dir, 'tokyo.jsonl'))
    assert_equal 'https://yelp.com/biz/edo1',
                 entries.find { |e| e['name'] == 'Sushi Edo' }['yelp_url'],
                 'the pass continued past the failed spot and filled the later one'
    refute_includes load_progress(@progress), 'Sushi Saito|tokyo',
                    'a failed exact search never marks the spot tried'
  end

  # A successful-but-empty [] result still marks the spot tried, even when the
  # spot follows a hard failure in the same pass.
  def test_empty_exact_result_is_still_marked_after_a_failure
    write_atomic(File.join(@data_dir, 'tokyo.jsonl'),
                 [{ 'name' => 'Sushi Saito' }, { 'name' => 'Sushi Edo' }])
    provider = lambda do |params|
      params['term'] == 'Sushi Saito' ? nil : []
    end

    refresh_yelp_fields(search: provider, data_dir: @data_dir,
                        progress_path: @progress, sleeper: NO_SLEEP)

    refute_includes load_progress(@progress), 'Sushi Saito|tokyo',
                    'a failed exact search never marks the spot tried'
    assert_includes load_progress(@progress), 'Sushi Edo|tokyo',
                   'a successful-but-empty [] result still marks the spot'
  end
end
