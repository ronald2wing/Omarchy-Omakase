#!/usr/bin/env ruby
# frozen_string_literal: true

# Unit tests for the pure functions in the pipeline scripts — collect_cities,
# refresh_yelp_fields, normalize_locations, and backfill_websites (no API calls —
# main is guarded by `if __FILE__ == $PROGRAM_NAME`, so require only loads
# functions). The website provider adapters now live in website_sources.rb,
# required here so their pure helpers (clean_host, aggregator_host?) are
# exercised from their new home.

require 'minitest/autorun'
require 'tmpdir'
require_relative '../bin/refresh_yelp_fields'
require_relative '../bin/collect_cities'
require_relative '../bin/normalize_locations'
require_relative '../bin/website_sources'
require_relative '../bin/geocode_fallback'
require_relative '../bin/backfill_websites'

class FillIfAbsentTest < Minitest::Test
  def test_writes_and_returns_true_when_key_absent
    entry = {}

    assert fill_if_absent!(entry, 'yelp_rating', 4.5)
    assert_equal 4.5, entry['yelp_rating']
  end

  def test_rejects_nil_empty_string_and_empty_array
    entry = {}

    refute fill_if_absent!(entry, 'a', nil), 'nil is blank'
    refute fill_if_absent!(entry, 'b', ''), 'empty string is blank'
    refute fill_if_absent!(entry, 'c', []), 'empty array is blank (documented gotcha)'
    assert_empty entry, 'blank values are never written'
  end

  def test_false_boolean_is_written
    entry = {}

    assert fill_if_absent!(entry, 'is_closed', false),
           'false is a valid boolean, not blank'
    assert entry.key?('is_closed')
    assert_equal false, entry['is_closed']
  end

  def test_existing_key_is_preserved
    entry = { 'city' => 'NYC' }

    refute fill_if_absent!(entry, 'city', 'LA'), 'never overwrites'
    assert_equal 'NYC', entry['city']
  end
end

class RefreshYelpFieldsTest < Minitest::Test
  def test_merge_yelp_fills_missing_only
    entry = {}
    business = {
      'url' => 'https://yelp.com/biz/x', 'rating' => 4.5, 'review_count' => 10,
      'price' => '$$$', 'id' => 'abc123', 'is_closed' => false,
      'image_url' => 'https://img',
      'display_phone' => '+1 555', 'transactions' => ['delivery'],
      'location' => { 'address1' => '1 Main St', 'state' => 'NY',
                      'country' => 'US', 'display_address' => ['1 Main St'] },
      'coordinates' => { 'latitude' => 40.7, 'longitude' => -74.0 }
    }
    assert merge_yelp(entry, business), 'first merge should change'

    assert_equal 'https://yelp.com/biz/x', entry['yelp_url']
    assert_equal 4.5, entry['yelp_rating']
    assert_equal '$$$', entry['yelp_price']
    assert_equal 'abc123', entry['yelp_id']
    assert_equal false, entry['is_closed']
    assert_equal '1 Main St', entry['address']
    assert_equal ['1 Main St'], entry['display_address']
    assert_equal 40.7, entry['lat']
  end

  def test_merge_yelp_does_not_overwrite_existing
    entry = { 'yelp_rating' => 5.0 }
    business = { 'rating' => 3.0 }
    refute merge_yelp(entry, business), 'no change when field exists'
    assert_equal 5.0, entry['yelp_rating'], 'existing value preserved'
  end

  def test_merge_yelp_reports_no_change_when_coordinates_already_present
    entry = { 'lat' => 40.7, 'lon' => -74.0 }
    business = { 'coordinates' => { 'latitude' => 40.7, 'longitude' => -74.0 } }
    refute merge_yelp(entry, business), 'coordinates already set must not report a change'
    assert_equal 40.7, entry['lat']
    assert_equal(-74.0, entry['lon'])
  end

  def test_merge_yelp_fills_missing_coordinate_and_reports_change
    entry = { 'lat' => 40.7 }
    business = { 'coordinates' => { 'latitude' => 40.7, 'longitude' => -74.0 } }
    assert merge_yelp(entry, business), 'a missing coordinate must report a change'
    assert_equal 40.7, entry['lat']
    assert_equal(-74.0, entry['lon'])
  end

  def test_needs_fill_core_fields
    assert needs_fill({ 'name' => 'X' }), 'bare entry needs fill'
    refute needs_fill(nil), 'nil needs no fill'
    refute needs_fill({ 'time' => '8pm', 'discount' => '50%' }), 'discount skipped'

    full = { 'yelp_url' => 'u', 'yelp_rating' => 4.0, 'is_closed' => false,
             'address' => 'a', 'state' => 's', 'display_address' => ['a'] }
    refute needs_fill(full), 'core-complete entry needs no fill (image_url/phone optional)'
  end
end

class CollectCityTest < Minitest::Test
  def test_relevant_omakase_business
    assert relevant_omakase_business?({ 'name' => 'Sushi Saito', 'categories' => [{ 'alias' => 'sushi' }] })
    assert relevant_omakase_business?({ 'name' => 'Omakase', 'categories' => [] })
    refute relevant_omakase_business?({ 'name' => 'Ramen Shop', 'categories' => [{ 'alias' => 'ramen' }] })
    refute relevant_omakase_business?({ 'name' => 'Supermarket', 'categories' => [{ 'alias' => 'sushi' }] })
  end

  def test_business_to_entry_shape
    business = {
      'name' => 'Test', 'id' => 'id1', 'rating' => 4.0, 'review_count' => 5,
      'price' => '$$', 'url' => 'https://yelp', 'display_phone' => '+1',
      'coordinates' => { 'latitude' => 1.234567, 'longitude' => 2.345678 },
      'location' => { 'address1' => '1 St' }
    }
    e = business_to_entry(business, 'USD')
    assert_equal 'Test', e['name']
    assert_equal 'USD', e['currency']
    assert_equal '1 St', e['address']
    assert_equal 1.234567, e['lat']
    expected_keys = %w[name currency address yelp_id
                       yelp_rating yelp_review_count yelp_price yelp_url lat lon phone]
    assert_equal expected_keys.sort, e.keys.sort, 'entry carries the canonical field set'
  end

  def test_within_city_rejects_cross_metro
    nyc_biz = { 'coordinates' => { 'latitude' => 40.726, 'longitude' => -73.992 } }
    refute within_city?('philadelphia', nyc_biz), 'NYC spot must not enter Philadelphia'
  end

  def test_within_city_keeps_local_suburbs
    sandy_springs = { 'coordinates' => { 'latitude' => 33.93, 'longitude' => -84.37 } }
    assert within_city?('atlanta', sandy_springs), 'Atlanta suburb stays'
  end

  def test_within_city_keeps_no_coord
    assert within_city?('philadelphia', {}), 'missing coords are not rejected (no info)'
  end

  def test_within_city_without_center_accepts_any_business
    far_away = { 'coordinates' => { 'latitude' => 0.0, 'longitude' => 0.0 } }

    assert within_city?('nyc', far_away),
           'curated city (no center) cannot distance-check, so accept'
    assert within_city?('nyc', {}), 'even without coordinates'
  end
end

class DedupKeyTest < Minitest::Test
  def test_strips_and_lowercases_name
    assert_equal ['sushi saito', 'tokyo'], dedup_key('  Sushi Saito  ', 'tokyo')
  end

  def test_same_name_in_different_cities_never_collides
    refute_equal dedup_key('Sushi Saito', 'tokyo'), dedup_key('Sushi Saito', 'osaka')
  end
end

class AddressLikeTest < Minitest::Test
  def test_digit_marks_address
    assert address_like?('14 High Holborn')
    assert address_like?('渋谷1-6-4')
    assert address_like?('Suite 101')
  end

  def test_us_street_suffix_marks_address
    assert address_like?('123 Main Street')
    assert address_like?('Main St')
    assert address_like?('Park Avenue')
  end

  def test_eu_street_prefix_marks_address
    assert address_like?('Via Veneto')
    assert address_like?('Rue de Rivoli')
    assert address_like?('Calle Mayor')
  end

  def test_suite_and_floor_words_mark_address
    assert address_like?('Suite 4')
    assert address_like?('Ste B')
    assert address_like?('Ground Floor')
    assert address_like?('Shop 12')
  end

  def test_real_neighborhood_names_are_not_addresses
    refute address_like?('Brooklyn')
    refute address_like?('Midtown Manhattan')
    refute address_like?('Lower Manhattan')
    refute address_like?('Ginza')
  end

  def test_blank_is_not_an_address
    refute address_like?(nil)
    refute address_like?('')
    refute address_like?('   ')
  end
end

class NormalizeEntryTest < Minitest::Test
  def test_address_from_address_like_neighborhood
    entry = { 'name' => 'A', 'neighborhood' => '14 High Holborn', 'city' => 'London' }
    result = normalize_entry(entry)
    assert_equal '14 High Holborn', result['address']
    refute result.key?('neighborhood')
    refute result.key?('city')
  end

  def test_address_from_display_address
    entry = { 'name' => 'B', 'display_address' => ['1 Main St', 'NYC, NY'], 'city' => 'New York' }
    result = normalize_entry(entry)
    assert_equal '1 Main St', result['address']
    refute result.key?('city')
  end

  def test_real_neighborhood_kept
    entry = { 'name' => 'C', 'neighborhood' => 'Brooklyn' }
    result = normalize_entry(entry)
    assert_equal 'Brooklyn', result['neighborhood']
    refute result.key?('address')
  end

  def test_address_inserted_immediately_before_neighborhood
    entry = { 'name' => 'D', 'display_address' => ['1 Main St'], 'neighborhood' => 'Brooklyn' }
    result = normalize_entry(entry)
    assert_equal %w[name display_address address neighborhood], result.keys
    assert_equal '1 Main St', result['address']
    assert_equal 'Brooklyn', result['neighborhood']
  end

  def test_idempotent_preserves_key_order
    entry = { 'name' => 'A', 'neighborhood' => '14 High Holborn', 'city' => 'London' }
    once = normalize_entry(entry)
    twice = normalize_entry(once)
    assert_equal once, twice
    assert_equal once.keys, twice.keys
  end
end

class BackfillWebsitesTest < Minitest::Test
  def test_clean_host_extracts_domain
    assert_equal 'example.com', clean_host('https://example.com/foo')
    assert_equal 'example.com', clean_host('https://www.example.com')
    assert_nil clean_host(nil)
    assert_nil clean_host('https://yelp.com/biz/x'), 'aggregator blocked'
    assert_nil clean_host('https://facebook.com/x'), 'social blocked'
  end
end

class DistinctiveTokensTest < Minitest::Test
  def test_docstring_examples
    assert_equal ['edo'], distinctive_tokens('Sushi Edo')
    assert_equal ['osushi'], distinctive_tokens('Osushi')
    assert_equal ['minamishima'], distinctive_tokens('Minamishima')
    assert_equal [], distinctive_tokens('L.A Sushi')
  end

  def test_strips_stopwords_and_generic_sushi_words
    assert_equal [], distinctive_tokens('The Sushi Bar')
    assert_equal ['edo'], distinctive_tokens('Sushi Edo Kitchen')
  end

  def test_drops_short_words
    assert_equal [], distinctive_tokens('A Sushi')
  end
end

class AggregatorHostTest < Minitest::Test
  def test_exact_and_subdomain_hosts_are_rejected
    assert aggregator_host?('kwickmenu.com'), 'exact aggregator host rejected'
    assert aggregator_host?('ahisushi.kwickmenu.com'), 'aggregator subdomain rejected'
  end

  def test_unrelated_host_and_nil_are_accepted
    refute aggregator_host?('sushiedo.com.au'), 'own domain accepted'
    refute aggregator_host?(nil), 'nil host accepted (nothing to reject)'
  end
end

class GeocodeFallbackTest < Minitest::Test
  def test_decimal_places_counts_fraction_digits
    assert_equal 4, decimal_places(40.7738)
    assert_equal 6, decimal_places(40.773812)
    assert_equal 0, decimal_places(40), 'integer coordinate has no fraction'
  end

  def test_coarse_coord_requires_both_values_coarse
    assert coarse_coord?(40.7738, -73.9581), 'both values at 4 decimal places'
    refute coarse_coord?(40.773812, -73.958112), 'both values at 6 decimal places'
    refute coarse_coord?(40.773812, -73.9581), 'one precise value defeats coarseness'
  end

  def test_city_label_prefers_display_name
    assert_equal 'Tokyo', city_label('tokyo')
  end

  def test_city_label_falls_back_to_location
    assert_equal 'Sydney, Australia', city_label('australia'), 'country-level key has no name'
    assert_equal 'New York, NY', city_label('nyc'), 'curated city has no name'
  end

  def test_city_label_title_cases_unknown_keys
    assert_equal 'Some Unknown City', city_label('some-unknown-city')
  end
end

class CollectCitiesOrchestrationTest < Minitest::Test
  # A single fake city drives the orchestration loop without touching the real
  # COLLECTABLE_CITIES table. The fake key has no CITIES center, so within_city?
  # accepts every business — these tests exercise resume/dedup/write-gate/failure
  # rules, not the radius guard (which has its own pure-function tests above).
  FAKE_CITIES = { 'fakeville' => { location: 'Fakeville', currency: 'USD' } }.freeze
  NO_SLEEP = ->(_secs) {}

  def setup
    @dir = Dir.mktmpdir
    @data_dir = File.join(@dir, 'data')
    Dir.mkdir(@data_dir)
    @progress = File.join(@dir, '.fetch-progress')
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def collect(search:)
    collect_cities(search: search, data_dir: @data_dir, progress_path: @progress,
                   cities: FAKE_CITIES, sleeper: NO_SLEEP)
  end

  def business(id, name)
    { 'id' => id, 'name' => name, 'categories' => [{ 'alias' => 'sushi' }],
      'rating' => 4.5, 'review_count' => 10, 'price' => '$$',
      'url' => "https://yelp.com/biz/#{id}", 'display_phone' => '+1',
      'location' => { 'address1' => '1 St' } }
  end

  def test_hard_failed_city_is_not_recorded_as_complete
    total = collect(search: ->(_params) { nil })

    assert_equal 0, total
    assert_empty load_progress(@progress), 'a hard-failed city must not be marked complete'
  end

  def test_zero_result_city_is_recorded_as_complete
    total = collect(search: ->(_params) { [] })

    assert_equal 0, total
    assert_includes load_progress(@progress), 'fakeville',
                    'a completed-but-empty city is complete ([] vs nil)'
  end

  def test_rerun_skips_completed_city_without_duplicates
    stub = ->(_params) { [business('id1', 'Sushi Saito')] }

    assert_equal 1, collect(search: stub)
    assert_equal 0, collect(search: stub), 'completed city is skipped on re-run'
    assert_equal 1, load_jsonl(File.join(@data_dir, 'fakeville.jsonl')).size,
                 're-run never duplicates a collected spot'
  end

  def test_data_file_written_only_when_new_entries_arrive
    path = File.join(@data_dir, 'fakeville.jsonl')
    write_atomic(path, [{ 'name' => 'Sushi Saito' }])
    before = File.read(path)

    total = collect(search: ->(_params) { [business('id1', 'Sushi Saito')] })

    assert_equal 0, total, 'the already-present spot dedups to nothing new'
    assert_equal before, File.read(path), 'no write when nothing new arrived'
  end

  def test_aborted_city_persists_partial_but_is_not_marked_complete
    # Page 1 returns a full page so the loop pages on; page 2 hard-fails.
    full_page = (1..YELP_PAGE_SIZE).map { |i| business("id#{i}", "Sushi Place #{i}") }
    calls = 0
    stub = lambda do |_params|
      result = calls.zero? ? full_page : nil
      calls += 1
      result
    end

    collect(search: stub)

    assert_equal YELP_PAGE_SIZE, load_jsonl(File.join(@data_dir, 'fakeville.jsonl')).size,
                 'partial work is persisted'
    assert_empty load_progress(@progress), 'an aborted city is never marked complete'
  end
end

class RefreshYelpFieldsOrchestrationTest < Minitest::Test
  NO_SLEEP = ->(_secs) {}

  def setup
    @dir = Dir.mktmpdir
    @data_dir = File.join(@dir, 'data')
    Dir.mkdir(@data_dir)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def write_city(city, entry)
    write_atomic(File.join(@data_dir, "#{city}.jsonl"), [entry])
  end

  def yelp_business
    {
      'name' => 'Sushi Saito', 'id' => 'abc123',
      'url' => 'https://yelp.com/biz/abc123', 'rating' => 4.5,
      'review_count' => 10, 'price' => '$$$', 'image_url' => 'https://img',
      'display_phone' => '+1 555', 'transactions' => ['delivery'],
      'is_closed' => false,
      'location' => { 'address1' => '1 Main St', 'state' => 'NY',
                      'country' => 'US', 'display_address' => ['1 Main St'] },
      'coordinates' => { 'latitude' => 40.7, 'longitude' => -74.0 }
    }
  end

  def test_fills_missing_fields_and_reports_counts
    write_city('tokyo', { 'name' => 'Sushi Saito' })

    result = refresh_yelp_fields(search: ->(_params) { [yelp_business] },
                                 data_dir: @data_dir, sleeper: NO_SLEEP)

    assert_equal({ filled: 1, calls: 1 }, result)
    entry = load_jsonl(File.join(@data_dir, 'tokyo.jsonl')).first
    assert_equal 'https://yelp.com/biz/abc123', entry['yelp_url']
    assert_equal 4.5, entry['yelp_rating']
    assert_equal false, entry['is_closed']
  end

  def test_does_not_write_file_when_nothing_changed
    path = File.join(@data_dir, 'tokyo.jsonl')
    write_atomic(path, [{ 'name' => 'Sushi Saito' }])
    before = File.read(path)

    result = refresh_yelp_fields(
      search: ->(_params) { [{ 'name' => 'Ramen House', 'id' => 'xyz', 'rating' => 3.0 }] },
      data_dir: @data_dir, sleeper: NO_SLEEP
    )

    assert_equal({ filled: 0, calls: 2 }, result)
    assert_equal before, File.read(path), 'no write when nothing changed'
  end

  def test_429_abort_stops_after_consecutive_hard_failures
    # Each pending city file costs two hard-failure calls (one bulk, one exact),
    # so four files reach MAX_CONSECUTIVE_429 (8) and trigger the abort.
    %w[tokyo osaka kyoto fukuoka].each { |city| write_city(city, { 'name' => 'Sushi Saito' }) }
    calls = 0
    stub = ->(_params) { calls += 1; nil }

    abort_message = nil
    define_singleton_method(:abort) { |msg| abort_message = msg; raise SystemExit }
    begin
      assert_raises(SystemExit) do
        capture_io do
          refresh_yelp_fields(search: stub, data_dir: @data_dir, sleeper: NO_SLEEP)
        end
      end
    ensure
      singleton_class.send(:remove_method, :abort)
    end

    assert_equal "\nAbort: consecutive 429s.", abort_message
    assert_equal MAX_CONSECUTIVE_429, calls, 'aborts exactly on the Nth consecutive failure'
  end
end
