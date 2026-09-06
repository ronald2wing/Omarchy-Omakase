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

# A response double for read_capped_body: read_body yields the configured chunks
# in order and counts how many were yielded, so tests can assert the cap aborts
# mid-download (chunks after the crossing chunk are never read). It also carries
# a status code and the Retry-After header so it can stand in for the response
# http_request yields to yelp_search_once's block.
class FakeResponse
  attr_reader :chunks_read, :code

  def initialize(*chunks, code: 200, retry_after: nil)
    @chunks = chunks
    @chunks_read = 0
    @code = code
    @retry_after = retry_after
  end

  def read_body
    @chunks.each do |chunk|
      @chunks_read += 1
      yield chunk
    end
    @chunks.join
  end

  # Net::HTTPResponse#[] reads a header; only Retry-After matters to the client.
  def [](name)
    name == 'Retry-After' ? @retry_after : nil
  end
end

# A Net::HTTP double for http_client: request yields the configured response to
# the block (matching Net::HTTP's block form, which does not raise on non-2xx)
# and returns it.
class FakeHttp
  def initialize(response)
    @response = response
  end

  def request(_req)
    yield @response if block_given?
    @response
  end
end

class ReadCappedBodyTest < Minitest::Test
  def test_returns_accumulated_body_when_under_cap
    res = FakeResponse.new('{"a":', '1}')

    assert_equal '{"a":1}', read_capped_body(res, max_bytes: 100)
    assert_equal 2, res.chunks_read, 'reads every chunk to completion under the cap'
  end

  def test_raises_body_too_large_when_cap_crossed
    res = FakeResponse.new('aaaaa', 'aaaaa', 'aaaaa')

    assert_raises(BodyTooLarge) do
      read_capped_body(res, max_bytes: 10)
    end
  end

  def test_aborts_mid_download_without_reading_past_the_crossing_chunk
    res = FakeResponse.new('aaaaa', 'aaaaa', 'aaaaa', 'bbbbb', 'ccccc')

    assert_raises(BodyTooLarge) do
      read_capped_body(res, max_bytes: 10)
    end
    assert_equal 3, res.chunks_read,
                 'stops at the chunk that crosses the cap; later chunks are never read'
  end

  def test_exactly_at_cap_does_not_raise
    res = FakeResponse.new('aaaaa', 'aaaaa')

    assert_equal 'aaaaaaaaaa', read_capped_body(res, max_bytes: 10)
  end
end

class YelpSearchOnceTest < Minitest::Test
  # Route http_client to a fake connection that yields `res` back through
  # http_request, so the real status-capture and 429/parse logic run with no
  # network. Removed in ensure so later tests get the real method back.
  def with_response(res)
    define_singleton_method(:http_client) { |_uri, **_opts| FakeHttp.new(res) }
    yield
  ensure
    singleton_class.send(:remove_method, :http_client)
  end

  def test_429_raises_rate_limited_carrying_retry_after
    with_response(FakeResponse.new('{}', code: 429, retry_after: '30')) do
      err = assert_raises(RateLimited) { yelp_search_once({}, 'test-key') }
      assert_equal '30', err.retry_after, 'Retry-After header carried on the error'
    end
  end

  def test_200_returns_businesses
    with_response(FakeResponse.new('{"businesses":[{"name":"Sushi Saito"}]}', code: 200)) do
      assert_equal [{ 'name' => 'Sushi Saito' }], yelp_search_once({}, 'test-key')
    end
  end

  def test_non_2xx_raises_standard_error
    with_response(FakeResponse.new('{"error":"boom"}', code: 500)) do
      assert_raises(StandardError) { yelp_search_once({}, 'test-key') }
    end
  end
end

class SearchYelpRateLimitTest < Minitest::Test
  def test_waits_on_retry_after_before_retrying
    calls = 0
    sleeps = []
    define_singleton_method(:yelp_search_once) do |_params, _api_key|
      calls += 1
      raise RateLimited.new('30') if calls < 3

      [{ 'name' => 'Recovered' }]
    end
    define_singleton_method(:yelp_api_key) { 'test-key' }
    define_singleton_method(:sleep) { |secs| sleeps << secs }

    assert_equal [{ 'name' => 'Recovered' }], search_yelp({})
    assert_equal [30.0, 30.0], sleeps, 'each 429 waits the Retry-After duration'
    assert_equal 3, calls, 'retries before succeeding'
  ensure
    singleton_class.send(:remove_method, :yelp_search_once)
    singleton_class.send(:remove_method, :yelp_api_key)
    singleton_class.send(:remove_method, :sleep)
  end

  def test_returns_nil_after_three_rate_limited_attempts
    calls = 0
    define_singleton_method(:yelp_search_once) do |_params, _api_key|
      calls += 1
      raise RateLimited.new('30')
    end
    define_singleton_method(:yelp_api_key) { 'test-key' }
    define_singleton_method(:sleep) { |_secs| }

    assert_nil search_yelp({}), 'hard 429 aborts with nil after the cap'
    assert_equal 3, calls, 'MAX_RETRIES attempts, no more'
  ensure
    singleton_class.send(:remove_method, :yelp_search_once)
    singleton_class.send(:remove_method, :yelp_api_key)
    singleton_class.send(:remove_method, :sleep)
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

# The empty-array-is-not-data rule (an empty `[]` is "no data") is a field-value
# concern handled by fill_if_absent! in refresh_yelp_fields.rb, not a line-level
# concern here: load_jsonl parses whatever valid JSON a line holds and returns it
# as-is. That rule is exercised in bin_pipeline_test.rb (FillIfAbsentTest).
class LoadJsonlTest < Minitest::Test
  def test_parses_valid_lines
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'city.jsonl')
      File.write(path, %({"name":"A","lat":1.0}\n{"name":"B"}\n))

      assert_equal [{ 'name' => 'A', 'lat' => 1.0 }, { 'name' => 'B' }], load_jsonl(path)
    end
  end

  def test_skips_blank_and_whitespace_lines
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'city.jsonl')
      File.write(path, %({"name":"A"}\n\n   \n\t\n{"name":"B"}\n))

      assert_equal [{ 'name' => 'A' }, { 'name' => 'B' }], load_jsonl(path)
    end
  end

  def test_malformed_line_warns_and_is_skipped_not_aborted
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'city.jsonl')
      File.write(path, %({"name":"A"}\nnot json\n{"name":"B"}\n))

      result = nil
      _stdout, stderr = capture_io { result = load_jsonl(path) }

      assert_equal [{ 'name' => 'A' }, { 'name' => 'B' }], result,
                   'malformed line is skipped, remaining lines still load'
      assert_match(/skipping malformed JSON line/, stderr, 'a warning names the bad line')
      assert_match(/city\.jsonl/, stderr, 'warning names the file')
    end
  end
end

class SelectCityFilesTest < Minitest::Test
  FILES = %w[nyc.jsonl tokyo.jsonl osaka.jsonl].freeze

  def test_nil_returns_all_files
    assert_equal FILES, select_city_files(FILES, nil)
  end

  def test_stem_and_suffixed_arg_both_select_the_city
    assert_equal ['nyc.jsonl'], select_city_files(FILES, 'nyc')
    assert_equal ['nyc.jsonl'], select_city_files(FILES, 'nyc.jsonl')
  end

  def test_unknown_city_selects_nothing
    assert_empty select_city_files(FILES, 'paris')
  end
end

class EntrySortKeyTest < Minitest::Test
  # Arrays don't define `<`; compare the keys' spaceship result against 0.
  def assert_sorts_before(a, b, msg = nil)
    assert_operator entry_sort_key(a) <=> entry_sort_key(b), :<, 0, msg
  end

  def test_case_insensitive_name_order
    assert_sorts_before({ 'name' => 'apple' }, { 'name' => 'Banana' },
                        'lowercase apple sorts before capitalized Banana')
  end

  def test_lat_then_lon_break_name_ties
    a = { 'name' => 'Sushi', 'lat' => 1.0, 'lon' => 2.0 }
    b = { 'name' => 'Sushi', 'lat' => 1.0, 'lon' => 3.0 }
    c = { 'name' => 'Sushi', 'lat' => 2.0, 'lon' => 0.0 }

    assert_sorts_before(a, b, 'same lat: lower lon first')
    assert_sorts_before(b, c, 'lower lat wins regardless of lon')
  end

  def test_missing_coordinates_sort_last
    assert_sorts_before({ 'name' => 'Sushi', 'lat' => 1.0, 'lon' => 1.0 },
                        { 'name' => 'Sushi' },
                        'same name: a spot without coordinates sorts after one with them')
  end

  def test_total_order_with_missing_coordinates
    full = { 'name' => 'Sushi', 'lat' => 1.0, 'lon' => 1.0 }
    partial = { 'name' => 'Sushi', 'lat' => 1.0 } # lat present, lon missing
    none = { 'name' => 'Sushi' }                  # both missing

    assert_sorts_before(full, partial, 'missing lon sorts after')
    assert_sorts_before(partial, none, 'missing lat sorts after')
  end

  def test_sort_entries_orders_by_the_key
    entries = [
      { 'name' => 'B' },
      { 'name' => 'a', 'lat' => 2.0, 'lon' => 2.0 },
      { 'name' => 'A', 'lat' => 1.0, 'lon' => 2.0 },
      { 'name' => 'A', 'lat' => 1.0, 'lon' => 1.0 }
    ]

    sort_entries!(entries)

    assert_equal [
      { 'name' => 'A', 'lat' => 1.0, 'lon' => 1.0 },
      { 'name' => 'A', 'lat' => 1.0, 'lon' => 2.0 },
      { 'name' => 'a', 'lat' => 2.0, 'lon' => 2.0 },
      { 'name' => 'B' }
    ], entries
  end
end
