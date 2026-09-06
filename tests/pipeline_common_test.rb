#!/usr/bin/env ruby
# frozen_string_literal: true

# Unit tests for the shared helpers across bin/ (no API calls): the JSONL and
# progress IO (jsonl.rb), the city table (cities.rb), the Yelp client's pure
# helpers (yelp_client.rb), and the hub's small utilities (pipeline_common.rb).
# The bin scripts guard main with `if __FILE__ == $PROGRAM_NAME`, so requiring
# them only defines constants/methods. yelp_client.rb reads the Yelp API key
# lazily (on first use), so requiring it never touches the real .env.

require 'minitest/autorun'
require 'tmpdir'
require 'json'
require 'set'
require_relative '../bin/pipeline_common'

class NormalizeNameTest < Minitest::Test
  def test_strips_spaces_and_lowercases
    assert_equal 'sushisaito', normalize_name('Sushi Saito')
  end

  def test_strips_punctuation
    assert_equal 'abc', normalize_name('A.B-C')
  end

  def test_non_ascii_only_is_empty
    assert_equal '', normalize_name('鮨 さいとう')
  end

  def test_nil_is_empty
    assert_equal '', normalize_name(nil)
  end
end

class WriteAtomicTest < Minitest::Test
  def test_writes_one_line_per_entry_and_round_trips
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'out.jsonl')
      entries = [{ 'name' => 'A' }, { 'name' => 'B', 'rating' => 5 }]

      write_atomic(path, entries)

      assert File.exist?(path), 'file should be created'
      lines = File.readlines(path, chomp: true)
      assert_equal entries.size, lines.size, 'one line per entry'
      assert_equal entries, lines.map { |line| JSON.parse(line) },
                   'each line round-trips to the original object'
      refute File.exist?("#{path}.tmp"), 'temp file should be removed after rename'
    end
  end

  def test_nil_entry_writes_blank_line_without_crashing
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'out.jsonl')

      write_atomic(path, [{ 'name' => 'A' }, nil, { 'name' => 'B' }])

      lines = File.readlines(path, chomp: true)
      assert_equal ['{"name":"A"}', '', '{"name":"B"}'], lines
      assert_equal([{ 'name' => 'A' }, { 'name' => 'B' }],
                   lines.reject(&:empty?).map { |line| JSON.parse(line) })
      refute File.exist?("#{path}.tmp")
    end
  end
end

class CanonicalYelpUrlTest < Minitest::Test
  def test_strips_query_string
    assert_equal 'https://www.yelp.com/biz/sushi-saito',
                 canonical_yelp_url('https://www.yelp.com/biz/sushi-saito?adjust_creative=abc&utm_source=xyz')
  end

  def test_bare_url_passes_through
    assert_equal 'https://www.yelp.com/biz/sushi-saito',
                 canonical_yelp_url('https://www.yelp.com/biz/sushi-saito')
  end

  def test_non_string_passes_through
    assert_nil canonical_yelp_url(nil)
    assert_equal 42, canonical_yelp_url(42)
    assert_equal :symbol, canonical_yelp_url(:symbol)
  end

  def test_strips_only_from_first_question_mark
    assert_equal 'https://x/y', canonical_yelp_url('https://x/y?a?b=c')
  end
end

class LoadProgressTest < Minitest::Test
  def test_missing_file_returns_empty_set
    Dir.mktmpdir do |dir|
      result = load_progress(File.join(dir, 'absent-progress'))

      assert_instance_of Set, result
      assert_empty result
    end
  end

  def test_blank_and_whitespace_lines_are_rejected
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'progress')
      File.write(path, "tokyo\n\n   \nphiladelphia\ntokyo\n")

      assert_equal Set.new(%w[tokyo philadelphia]), load_progress(path),
                   'blank lines dropped and duplicates collapsed'
    end
  end
end

class LoadEnvKeyTest < Minitest::Test
  # Yields a temp .env path so the parser never touches the real project .env.
  def with_env_file(contents)
    Dir.mktmpdir do |dir|
      path = File.join(dir, '.env')
      File.write(path, contents)
      yield path
    end
  end

  def test_parses_plain_and_quoted_values
    with_env_file(%(PLAIN=value\nDOUBLE="quoted value"\nSINGLE='single value'\n)) do |path|
      assert_equal 'value', load_env_key('PLAIN', path)
      assert_equal 'quoted value', load_env_key('DOUBLE', path)
      assert_equal 'single value', load_env_key('SINGLE', path)
    end
  end

  def test_ignores_comment_lines_and_returns_nil_for_missing_keys
    with_env_file("# COMMENT=ignored\nOTHER=present\n") do |path|
      assert_nil load_env_key('COMMENT', path)
      assert_equal 'present', load_env_key('OTHER', path)
    end
  end

  def test_environment_takes_precedence_over_file
    with_env_file("OMAKASE_PRECEDENCE_KEY=from_file\n") do |path|
      ENV['OMAKASE_PRECEDENCE_KEY'] = 'from_env'
      begin
        assert_equal 'from_env', load_env_key('OMAKASE_PRECEDENCE_KEY', path)
      ensure
        ENV.delete('OMAKASE_PRECEDENCE_KEY')
      end
    end
  end

  def test_missing_file_returns_nil
    Dir.mktmpdir do |dir|
      assert_nil load_env_key('OMAKASE_ABSENT_KEY', File.join(dir, 'missing'))
    end
  end
end

class RetryWaitTest < Minitest::Test
  def test_uses_retry_after_header_when_present
    assert_in_delta 30.0, retry_wait('30', 0), 0.0001
    assert_in_delta 30.5, retry_wait('30.5', 2), 0.0001
  end

  def test_falls_back_to_exponential_backoff
    assert_equal 1, retry_wait(nil, 0)
    assert_equal 2, retry_wait(nil, 1)
    assert_equal 4, retry_wait(nil, 2)
  end

  def test_empty_retry_after_header_coerces_to_zero
    assert_equal 0.0, retry_wait('', 0)
  end
end

class CollectableTest < Minitest::Test
  def test_requires_both_center_and_currency
    assert collectable?({ center: [1.0, 2.0], currency: 'USD' })
    refute collectable?({ currency: 'USD' }), 'no center'
    refute collectable?({ center: [1.0, 2.0] }), 'no currency'
    refute collectable?({}), 'neither'
  end

  def test_matches_real_city_table
    assert collectable?(CITIES['tokyo'])
    refute collectable?(CITIES['nyc']), 'curated city is refresh-only'
    refute collectable?(CITIES['australia']), 'country-level key has no center'
  end

  def test_collectable_cities_is_derived_from_the_rule
    assert_equal CITIES.select { |_, city| collectable?(city) }, COLLECTABLE_CITIES
  end
end

class HaversineTest < Minitest::Test
  def test_same_point_is_zero_distance
    assert_in_delta 0.0, haversine_km(35.68, 139.69, 35.68, 139.69), 0.0001
  end

  def test_one_degree_latitude_is_about_111_km
    assert_in_delta 111.2, haversine_km(0, 0, 1, 0), 0.5
  end
end
