#!/usr/bin/env ruby
# frozen_string_literal: true

# Unit tests for geocode_fallback.rb: decimal_places/coarse_coord?, the
# Nominatim city query, and the geocode orchestration loop (no API calls).

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../bin/geocode_fallback'
require_relative 'test_helper'

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

  def test_missing_coordinates_group_as_one_coarse_placeholder
    # Entries with no lat/lon share the [nil, nil] group, and coarse_coord?(nil, nil)
    # is true (decimal_places(nil) is 0), so that group passes the placeholder
    # filter and its entries are geocoded from their address.
    entries = [{ 'name' => 'A', 'address' => '1 Main St' },
               { 'name' => 'B', 'address' => '2 Main St' }]
    groups = entries.group_by { |e| [e['lat'], e['lon']] }

    assert_equal [[nil, nil]], groups.keys, 'coordinate-less entries collapse onto one [nil, nil] group'
    assert_equal 2, groups[[nil, nil]].size, 'both entries share the single group'
    assert coarse_coord?(nil, nil), 'nil coordinates count as a coarse placeholder'
    assert_equal 0, decimal_places(nil), 'nil has no fractional digits'
  end

  def test_nominatim_city_query_prefers_display_name
    assert_equal 'Tokyo', nominatim_city_query('tokyo')
  end

  def test_nominatim_city_query_falls_back_to_location
    assert_equal 'Sydney, Australia', nominatim_city_query('australia'), 'country-level key has no name'
    assert_equal 'New York, NY', nominatim_city_query('nyc'), 'curated city has no name'
  end

  def test_nominatim_city_query_title_cases_unknown_keys
    assert_equal 'Some Unknown City', nominatim_city_query('some-unknown-city')
  end

  def test_default_search_provider_is_a_one_argument_callable
    # The call site invokes search_provider.call(query) with a single argument.
    # The pre-fix default was method(:nominatim_search), whose required `limit:`
    # keyword gives it a -2 arity — calling it with one positional argument
    # raises ArgumentError on the first placeholder. Assert the default accepts
    # exactly the one argument the call site passes.
    assert_equal 1, NOMINATIM_SEARCH_PROVIDER.arity,
                 'the default provider must accept exactly one argument (the query)'
  end
end

class GeocodeFallbackOrchestrationTest < Minitest::Test
  include TmpDataDirHelper

  def progress_files
    { progress: '.geocode-progress' }
  end

  # Two entries sharing one coarse (4-decimal) coordinate form a placeholder
  # group; both carry an address, so both are Nominatim-search candidates. The
  # fake key has no CITIES center, so the > MAX_CENTER_KM guard is skipped.
  def write_placeholder_group
    write_atomic(File.join(@data_dir, 'fakeville.jsonl'), [
      { 'name' => 'Sushi A', 'address' => '1 Main St', 'lat' => 40.7738, 'lon' => -73.9581 },
      { 'name' => 'Sushi B', 'address' => '2 Main St', 'lat' => 40.7738, 'lon' => -73.9581 }
    ])
  end

  def run_geocode(provider)
    run_pipeline(provider, via: method(:geocode_fallback), provider_keyword: :search_provider)
  end

  def test_nil_result_is_not_marked_tried
    write_placeholder_group
    assert_marking_contract(
      ->(result) { run_geocode(->(_query) { result }) },
      -> { load_progress(@progress) },
      ['fakeville|Sushi A|40.7738,-73.9581', 'fakeville|Sushi B|40.7738,-73.9581'],
      success_result: [{ 'lat' => '40.773812', 'lon' => '-73.958112' }]
    )
  end

  def test_fully_marked_set_issues_no_call
    write_placeholder_group
    File.write(@progress, "fakeville|Sushi A|40.7738,-73.9581\nfakeville|Sushi B|40.7738,-73.9581\n")
    calls = 0
    run_geocode(->(_query) { calls += 1; [] })
    assert_equal 0, calls, 'a fully-marked set must issue no provider call'
  end
end
