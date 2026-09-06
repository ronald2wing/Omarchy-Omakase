#!/usr/bin/env ruby
# frozen_string_literal: true

# Unit tests for reverse_geocode_addresses.rb: derive_street_address,
# match_level, and the reverse-geocode orchestration loop (no API calls).

require 'minitest/autorun'
require_relative '../bin/reverse_geocode_addresses'
require_relative 'test_helper'

class DeriveStreetAddressTest < Minitest::Test
  def test_nil_place_returns_nil
    assert_nil derive_street_address(nil)
  end

  def test_house_number_and_road_are_combined
    place = { 'address' => { 'house_number' => '1', 'road' => 'Main Street' } }
    assert_equal '1 Main Street', derive_street_address(place)
  end

  def test_road_alone_is_used_when_no_house_number
    place = { 'address' => { 'road' => 'Broadway' } }
    assert_equal 'Broadway', derive_street_address(place)
  end

  def test_neighbourhood_falls_back_when_no_road
    place = { 'address' => { 'neighbourhood' => 'Shibuya' } }
    assert_equal 'Shibuya', derive_street_address(place)
  end

  def test_quarter_falls_back_when_no_road_or_neighbourhood
    place = { 'address' => { 'quarter' => 'Ginza' } }
    assert_equal 'Ginza', derive_street_address(place)
  end

  def test_suburb_is_the_last_fallback
    place = { 'address' => { 'suburb' => 'Manly' } }
    assert_equal 'Manly', derive_street_address(place)
  end

  def test_empty_neighbourhood_is_skipped
    place = { 'address' => { 'neighbourhood' => '', 'suburb' => 'Manly' } }
    assert_equal 'Manly', derive_street_address(place)
  end

  def test_no_address_map_returns_nil
    assert_nil derive_street_address({})
    assert_nil derive_street_address({ 'address' => {} })
  end
end

class MatchLevelTest < Minitest::Test
  def test_exact_match_ignores_street_type_and_number
    assert_equal :exact, match_level('1 Main Street', '1 Main St')
  end

  def test_shared_distinctive_token_is_street_match
    assert_equal :street, match_level('1 High Holborn', 'Holborn Court')
  end

  def test_no_shared_token_is_miss
    assert_equal :miss, match_level('1 Main Street', '14 High Holborn')
  end

  def test_shared_cjk_district_is_street_match
    assert_equal :street, match_level('西区愛宕3-1-6', '愛宕三丁目')
  end

  def test_unrelated_cjk_addresses_are_miss
    assert_equal :miss, match_level('東京都渋谷区', '大阪府中央区')
  end

  def test_blank_stored_or_derived_is_miss
    assert_equal :miss, match_level(nil, '1 Main Street')
    assert_equal :miss, match_level('1 Main Street', '')
  end
end

class ReverseGeocodeOrchestrationTest < Minitest::Test
  include TmpDataDirHelper

  def progress_files
    { progress: '.reverse-geocode-progress' }
  end

  def write_city(entries)
    write_atomic(File.join(@data_dir, 'fakeville.jsonl'), entries)
  end

  # A precise (non-placeholder) coordinate: coarse_coord? rejects 4-or-fewer
  # decimal places, and the fake key has no CITIES center, so the > MAX_CENTER_KM
  # wrong-coord guard is skipped too.
  def spot(name, i = 0)
    { 'name' => name, 'lat' => 40.773812 + i * 0.000001, 'lon' => -73.958112 }
  end

  def run_reverse(provider)
    run_pipeline(provider, via: method(:reverse_geocode_addresses), provider_keyword: :reverse_provider)
  end

  def test_writes_address_file_before_marking_tried
    write_city([spot('Sushi Edo')])
    place = { 'address' => { 'house_number' => '1', 'road' => 'Main Street' } }
    progress_at_write = capture_progress_marker_at_write(
      @progress, ->(progress) { progress.empty? }
    ) do
      run_reverse(->(_lat, _lon) { place })
    end

    assert_equal true, progress_at_write, 'no key is marked when the data file is written'
    assert_equal '1 Main Street',
                 load_jsonl(File.join(@data_dir, 'fakeville.jsonl')).first['address'],
                 'the address reached disk'
    refute_empty load_progress(@progress), 'the spot is marked after the fill'
  end

  def test_hard_failure_is_not_marked_tried
    write_city([spot('Sushi Edo')])

    assert_marking_contract(
      ->(result) { run_reverse(->(_lat, _lon) { result }) },
      -> { load_progress(@progress) },
      ['fakeville|Sushi Edo|40.773812,-73.958112'],
      success_result: {}
    )
  end

  def test_aborts_on_consecutive_hard_failures
    write_city(Array.new(MAX_CONSECUTIVE_FAILURES) { |i| spot("Sushi Edo #{i}", i) })
    assert_aborts_on_consecutive_failures do |hard_failure|
      run_reverse(hard_failure)
    end
  end

  def test_two_entries_sharing_one_coordinate_issue_one_reverse_call
    write_city([spot('Sushi Edo'), spot('Sushi Saito')])
    calls = 0
    place = { 'address' => { 'house_number' => '1', 'road' => 'Main Street' } }
    run_reverse(->(_lat, _lon) { calls += 1; place })

    assert_equal 1, calls, 'two spots at one coordinate need one reverse call'
    entries = load_jsonl(File.join(@data_dir, 'fakeville.jsonl'))
    assert_equal ['1 Main Street', '1 Main Street'], entries.map { |e| e['address'] },
                 'both spots receive the shared derived address'
    assert_equal 2, load_progress(@progress).size, 'both spots are marked tried'
  end

  def test_two_entries_at_distinct_coordinates_issue_two_calls
    write_city([spot('Sushi Edo', 0), spot('Sushi Saito', 1)])
    calls = 0
    run_reverse(->(_lat, _lon) { calls += 1; {} })

    assert_equal 2, calls, 'two distinct coordinates need two reverse calls'
  end

  def test_nil_coordinate_result_is_not_marked_tried
    write_city([spot('Sushi Edo'), spot('Sushi Saito')])
    run_reverse(->(_lat, _lon) { nil })

    assert_empty load_progress(@progress),
                 'a nil coordinate result must not mark any entry at that coordinate tried'
  end
end
