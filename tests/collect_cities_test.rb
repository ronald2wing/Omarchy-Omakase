#!/usr/bin/env ruby
# frozen_string_literal: true

# Unit tests for collect_cities.rb and the shared fill_if_absent! primitive
# it consumes: relevance, business_to_entry, dedup identity, and the collect
# orchestration loop (no API calls).

require 'minitest/autorun'
require_relative '../bin/collect_cities'
require_relative 'test_helper'

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

class CollectCityTest < Minitest::Test
  def test_relevant_omakase_business
    assert relevant_omakase_business?({ 'name' => 'Sushi Saito', 'categories' => [{ 'alias' => 'sushi' }] })
    assert relevant_omakase_business?({ 'name' => 'Omakase', 'categories' => [] })
    refute relevant_omakase_business?({ 'name' => 'Ramen Shop', 'categories' => [{ 'alias' => 'ramen' }] })
    refute relevant_omakase_business?({ 'name' => 'Supermarket', 'categories' => [{ 'alias' => 'sushi' }] })
  end

  def test_buffet_is_not_a_reject_term
    # `buffet` in a host is an AYCE signal (spot-utils.js), so the collector
    # must keep a sushi buffet rather than dropping it at collection time.
    assert relevant_omakase_business?({ 'name' => 'Sushi Buffet',
                                        'categories' => [{ 'alias' => 'sushi' }] }),
           'a sushi buffet is collectable — buffet is an AYCE signal, not a reject'
    refute relevant_omakase_business?({ 'name' => 'Golden Corral Buffet',
                                        'categories' => [{ 'alias' => 'buffets' }] }),
           'a non-sushi buffet still fails the sushi/omakase/Japanese guard'
  end

  def test_business_to_entry_shape
    business = {
      'name' => 'Test', 'id' => 'id1', 'rating' => 4.0, 'review_count' => 5,
      'price' => '$$', 'url' => 'https://www.yelp.com/biz/id1', 'display_phone' => '+1',
      'coordinates' => { 'latitude' => 1.234567, 'longitude' => 2.345678 },
      'location' => { 'address1' => '1 St' }
    }
    e = business_to_entry(business, 'USD')
    assert_equal 'Test', e['name']
    assert_equal 'USD', e['currency']
    expected_keys = %w[name currency address yelp_id
                       yelp_rating yelp_review_count yelp_price_level yelp_url lat lon phone]
    assert_equal expected_keys.sort, e.keys.sort, 'entry carries the canonical field set'
  end

  def test_business_to_entry_fills_remaining_yelp_fields
    # The fields refresh_yelp_fields would otherwise re-fetch are written at
    # collection time, mirroring YELP_FILL_MAP's source paths (and transforms).
    # The no-overwrite guarantee comes from fill_if_absent!
    # (unit-tested in FillIfAbsentTest); this asserts the field values land.
    # The shared fixture already carries the remaining fields; only the location
    # is overridden so its two-entry display_address proves the array round-trips.
    business = yelp_business_fixture.merge(
      'location' => { 'address1' => '1 St', 'state' => 'NY', 'country' => 'US',
                      'display_address' => ['1 St', 'New York, NY'] }
    )
    e = business_to_entry(business, 'USD')
    assert_equal 'NY', e['region_code'], 'region_code mirrors location.state'
    assert_equal 'US', e['country'], 'country mirrors location.country'
    assert_equal ['1 St', 'New York, NY'], e['display_address']
    assert_equal 'https://img', e['image_url']
    assert_equal ['delivery'], e['transactions']
    assert_equal false, e['is_closed'], 'false is a valid value, not blank'
  end

  def test_business_to_entry_blank_values_are_absent
    # The fill guard treats nil/""/[] as absent — the [] case is the gotcha, since
    # `[].to_s == "[]"` is truthy and would otherwise be persisted. The same
    # fill_if_absent! path never overwrites, so the direct writes business_to_entry
    # performs (address, yelp_url, ...) are untouched by the fill pass.
    business = {
      'name' => 'Sushi Saito', 'id' => 'id1', 'rating' => 4.5, 'review_count' => 10,
      'price' => '$$', 'url' => 'https://yelp.com/biz/id1', 'display_phone' => '+1',
      'image_url' => '', 'transactions' => [], 'display_address' => [],
      'location' => { 'address1' => '1 St', 'state' => '', 'country' => nil }
    }
    e = business_to_entry(business, 'USD')
    refute e.key?('image_url'), '"" is absent'
    refute e.key?('transactions'), '[] is absent (the documented gotcha)'
    refute e.key?('display_address'), '[] is absent'
    refute e.key?('region_code'), '"" is absent'
    refute e.key?('country'), 'nil is absent'
    refute e.key?('is_closed'), 'unreported is_closed is absent'
    assert_equal '1 St', e['address'], 'the direct address write survives the fill pass'
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
    assert_nil CITIES.dig('nyc', :center),
               "the test's premise: nyc is a curated city with no center, so the radius guard is skipped"
    far_away = { 'coordinates' => { 'latitude' => 0.0, 'longitude' => 0.0 } }

    assert within_city?('nyc', far_away),
           'curated city (no center) cannot distance-check, so accept'
    assert within_city?('nyc', {}), 'even without coordinates'
  end
end

class DedupIdentityTest < Minitest::Test
  def test_dedup_key_strips_and_lowercases_name
    assert_equal ['sushi saito', 'tokyo'], dedup_key('  Sushi Saito  ', 'tokyo')
  end

  def test_dedup_key_same_name_in_different_cities_never_collides
    refute_equal dedup_key('Sushi Saito', 'tokyo'), dedup_key('Sushi Saito', 'osaka')
  end
end

class CollectCitiesOrchestrationTest < Minitest::Test
  include TmpDataDirHelper

  # A single fake city drives the orchestration loop without touching the real
  # COLLECTABLE_CITIES table. The fake key has no CITIES center, so within_city?
  # accepts every business — these tests exercise resume/dedup/write-gate/failure
  # rules, not the radius guard (which has its own pure-function tests above).
  FAKE_COLLECTABLE_CITIES = { 'fakeville' => { location: 'Fakeville', currency: 'USD' } }.freeze

  def progress_files
    { progress: '.fetch-progress' }
  end

  def collect(search:)
    run_pipeline(search, via: method(:collect_cities), provider_keyword: :search,
                 cities: FAKE_COLLECTABLE_CITIES)
  end

  def business(id, name)
    { 'id' => id, 'name' => name, 'categories' => [{ 'alias' => 'sushi' }],
      'rating' => 4.5, 'review_count' => 10, 'price' => '$$',
      'url' => "https://yelp.com/biz/#{id}", 'display_phone' => '+1',
      'location' => { 'address1' => '1 St' } }
  end

  def test_hard_failed_city_is_not_recorded_as_complete
    result = collect(search: ->(_params) { nil })

    assert_equal 0, result[:total]
    assert_equal 1, result[:incomplete]
    assert_empty load_progress(@progress), 'a hard-failed city must not be marked complete'
  end

  def test_zero_result_city_is_recorded_as_complete
    result = collect(search: ->(_params) { [] })

    assert_equal 0, result[:total]
    assert_equal 0, result[:incomplete]
    assert_includes load_progress(@progress), 'fakeville',
                    'a completed-but-empty city is complete ([] vs nil)'
  end

  def test_rerun_skips_completed_city_without_duplicates
    stub = ->(_params) { [business('id1', 'Sushi Saito')] }

    assert_equal 1, collect(search: stub)[:total]
    assert_equal 0, collect(search: stub)[:total], 'completed city is skipped on re-run'
    assert_equal 1, load_jsonl(File.join(@data_dir, 'fakeville.jsonl')).size,
                 're-run never duplicates a collected spot'
  end

  def test_data_file_written_only_when_new_entries_arrive
    path = File.join(@data_dir, 'fakeville.jsonl')
    write_atomic(path, [{ 'name' => 'Sushi Saito' }])
    before = File.read(path)

    result = collect(search: ->(_params) { [business('id1', 'Sushi Saito')] })

    assert_equal 0, result[:total], 'the already-present spot dedups to nothing new'
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

    result = collect(search: stub)

    assert_equal 1, result[:incomplete]
    assert_equal YELP_PAGE_SIZE, load_jsonl(File.join(@data_dir, 'fakeville.jsonl')).size,
                 'partial work is persisted'
    assert_empty load_progress(@progress), 'an aborted city is never marked complete'
  end

  def test_location_not_found_spends_one_call_and_is_not_marked_complete
    calls = 0
    result = nil
    _stdout, stderr = capture_io do
      result = collect(search: lambda do |_params|
        calls += 1
        raise LocationNotFound.new(400, 'LOCATION_NOT_FOUND')
      end)
    end

    assert_equal 0, result[:total]
    assert_equal 1, result[:incomplete]
    assert_equal 1, calls, 'one call spent on the unresolvable city; remaining pages skipped'
    assert_empty load_progress(@progress), 'an unresolvable city is never marked complete'
    refute File.exist?(File.join(@data_dir, 'fakeville.jsonl')), 'no data file is written'
    assert_match(/fakeville/, stderr, 'the warning names the city')
    assert_match(/Fakeville/, stderr, 'the warning names the location string')
  end
end
