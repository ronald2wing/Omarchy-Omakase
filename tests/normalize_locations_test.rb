#!/usr/bin/env ruby
# frozen_string_literal: true

# Unit tests for normalize_locations.rb: address_like? and normalize_entry.

require 'minitest/autorun'
require_relative '../bin/normalize_locations'
require_relative 'test_helper'

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
