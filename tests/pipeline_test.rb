#!/usr/bin/env ruby
# frozen_string_literal: true

# Unit tests for the pure functions in the pipeline scripts — collect_city,
# refresh_yelp_fields, and backfill_websites (no API calls — main is guarded by
# `if __FILE__ == $PROGRAM_NAME`, so require only loads functions).

require 'minitest/autorun'
require_relative '../bin/refresh_yelp_fields'
require_relative '../bin/collect_city'
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
      'location' => { 'city' => 'NYC', 'state' => 'NY',
                      'country' => 'US', 'display_address' => ['1 Main St'] },
      'coordinates' => { 'latitude' => 40.7, 'longitude' => -74.0 }
    }
    assert merge_yelp(entry, business), 'first merge should change'

    assert_equal 'https://yelp.com/biz/x', entry['yelp_url']
    assert_equal 4.5, entry['yelp_rating']
    assert_equal '$$$', entry['yelp_price']
    assert_equal 'abc123', entry['yelp_id']
    assert_equal false, entry['is_closed']
    assert_equal 'NYC', entry['city']
    assert_equal ['1 Main St'], entry['display_address']
    assert_equal 40.7, entry['lat']
  end

  def test_merge_yelp_does_not_overwrite_existing
    entry = { 'yelp_rating' => 5.0 }
    business = { 'rating' => 3.0 }
    refute merge_yelp(entry, business), 'no change when field exists'
    assert_equal 5.0, entry['yelp_rating'], 'existing value preserved'
  end

  def test_needs_fill_core_fields
    assert needs_fill({ 'name' => 'X' }), 'bare entry needs fill'
    refute needs_fill(nil), 'nil needs no fill'
    refute needs_fill({ 'time' => '8pm', 'discount' => '50%' }), 'discount skipped'

    full = { 'yelp_url' => 'u', 'yelp_rating' => 4.0, 'is_closed' => false,
             'city' => 'c', 'state' => 's', 'display_address' => ['a'] }
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
    assert_equal 1.234567, e['lat']
    expected_keys = %w[name currency neighborhood source yelp_id
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
