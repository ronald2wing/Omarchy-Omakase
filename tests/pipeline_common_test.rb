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
require_relative 'test_helper'

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

class NormalizedNameOrNilTest < Minitest::Test
  def test_returns_normalized_name_when_matchable
    assert_equal 'sushisaito', normalized_name_or_nil('Sushi Saito')
  end

  def test_purely_cjk_name_is_nil
    assert_nil normalized_name_or_nil('鮨 さいとう')
  end

  def test_nil_name_is_nil
    assert_nil normalized_name_or_nil(nil)
  end

  def test_whitespace_only_name_is_nil
    assert_nil normalized_name_or_nil('   ')
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

class PersistThenMarkTest < Minitest::Test
  def test_writes_data_before_marking_tried
    Dir.mktmpdir do |dir|
      data_path = File.join(dir, 'city.jsonl')
      progress_path = File.join(dir, 'progress')
      progress_file = File.open(progress_path, 'a')

      result = nil
      progress_at_write = capture_progress_marker_at_write(
        progress_path, ->(progress) { progress.include?('key') }
      ) do
        result = persist_then_mark(true, data_path, [{ 'name' => 'A' }], progress_file, ['key'])
      end
      progress_file.close

      assert_equal false, progress_at_write, 'the key is not yet marked when the data file is written'
      assert_equal true, result, 'a write is reported as changed'
      assert_includes load_progress(progress_path), 'key', 'the key is marked after the fill'
      assert_equal [{ 'name' => 'A' }], load_jsonl(data_path), 'the data reached disk'
    end
  end

  def test_skips_data_write_but_still_marks_when_unchanged
    Dir.mktmpdir do |dir|
      data_path = File.join(dir, 'city.jsonl')
      write_atomic(data_path, [{ 'name' => 'A' }])
      before = File.read(data_path)
      progress_path = File.join(dir, 'progress')
      progress_file = File.open(progress_path, 'a')

      result = persist_then_mark(false, data_path, [], progress_file, ['key'])
      progress_file.close

      assert_equal false, result, 'no write is reported as unchanged'
      assert_equal before, File.read(data_path), 'the data file is untouched when unchanged'
      assert_includes load_progress(progress_path), 'key',
                      'an unchanged batch is still marked tried (empty success is tried)'
    end
  end

  def test_nil_progress_file_is_a_no_op
    Dir.mktmpdir do |dir|
      data_path = File.join(dir, 'city.jsonl')

      result = persist_then_mark(true, data_path, [{ 'name' => 'A' }], nil, ['key'])

      assert_equal true, result
      assert_equal [{ 'name' => 'A' }], load_jsonl(data_path)
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
    assert_equal 'https://www.yelp.com/biz/sushi-saito',
                 canonical_yelp_url('https://www.yelp.com/biz/sushi-saito?a?b=c')
  end

  def test_rejects_non_https_scheme_and_non_yelp_host
    assert_nil canonical_yelp_url('javascript:alert(1)'), 'javascript: scheme is dropped'
    assert_nil canonical_yelp_url('file:///etc/passwd'), 'file: scheme is dropped'
    assert_nil canonical_yelp_url('http://www.yelp.com/biz/sushi-saito'), 'cleartext http is dropped'
    assert_nil canonical_yelp_url('https://evil.com/biz/sushi-saito'), 'a foreign host is dropped'
    assert_nil canonical_yelp_url('https://yelp.com.evil.com/biz/x'), 'a lookalike suffix host is dropped'
    assert_nil canonical_yelp_url('not a url'), 'a malformed URL is dropped'
  end

  def test_accepts_bare_and_www_yelp_hosts
    assert_equal 'https://yelp.com/biz/sushi-saito',
                 canonical_yelp_url('https://yelp.com/biz/sushi-saito')
    assert_equal 'https://www.yelp.com/biz/sushi-saito',
                 canonical_yelp_url('https://www.yelp.com/biz/sushi-saito?utm_source=x')
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

class LoadProgressWithResumeTest < Minitest::Test
  def test_prints_resume_line_and_returns_set
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'progress')
      File.write(path, "tokyo\nphiladelphia\n")

      result = nil
      stdout, _stderr = capture_io { result = load_progress_with_resume(path) }

      assert_equal Set.new(%w[tokyo philadelphia]), result
      assert_match(/Resuming: 2 spots already tried/, stdout)
    end
  end

  def test_silent_when_empty_and_returns_empty_set
    Dir.mktmpdir do |dir|
      result = nil
      stdout, _stderr = capture_io { result = load_progress_with_resume(File.join(dir, 'absent')) }

      assert_empty result
      assert_equal '', stdout, 'an empty progress file announces nothing'
    end
  end
end

class OpenCloseProgressTest < Minitest::Test
  def test_dry_run_returns_nil_and_close_is_a_no_op
    file = open_progress('/unused/path', dry_run: true)

    assert_nil file, 'a dry run opens no progress file'
    close_progress(file) # must not raise
  end

  def test_non_dry_run_opens_appendable_file
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'progress')
      file = open_progress(path, dry_run: false)
      refute_nil file
      append_progress(file, ['key'])
      close_progress(file)

      assert_equal Set.new(['key']), load_progress(path), 'the appended key reached disk'
    end
  end
end

class MarkProgressTest < Minitest::Test
  def test_appends_keys_in_one_open_append_close
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'progress')
      mark_progress(path, ['tokyo'])
      mark_progress(path, ['philadelphia'])

      assert_equal Set.new(%w[tokyo philadelphia]), load_progress(path),
                   'each call appends its keys without dropping earlier ones'
    end
  end
end

class CachedQueryTest < Minitest::Test
  def test_hit_returns_cached_value_without_yielding
    cache = { 'q' => 'cached' }
    calls = 0

    result = cached_query(cache, 'q') { calls += 1; 'fresh' }

    assert_equal 'cached', result
    assert_equal 0, calls, 'a cache hit never runs the block'
  end

  def test_miss_yields_and_stores_the_block_value
    cache = {}
    calls = 0

    result = cached_query(cache, 'q') { calls += 1; 'fresh' }

    assert_equal 'fresh', result
    assert_equal 1, calls
    assert_equal 'fresh', cache['q'], 'the block result is stored for the next lookup'

    assert_equal 'fresh', cached_query(cache, 'q') { calls += 1; 'other' }
    assert_equal 1, calls, 'the second lookup reuses the stored value'
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

class ReadCappedBodyTest < Minitest::Test
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
    with_response(ReadCappedBodyTest::FakeResponse.new('{}', code: 429, retry_after: '30')) do
      err = assert_raises(RateLimited) { yelp_search_once({}, 'test-key') }
      assert_equal '30', err.retry_after, 'Retry-After header carried on the error'
    end
  end

  def test_200_returns_businesses
    with_response(ReadCappedBodyTest::FakeResponse.new('{"businesses":[{"name":"Sushi Saito"}]}', code: 200)) do
      assert_equal [{ 'name' => 'Sushi Saito' }], yelp_search_once({}, 'test-key')
    end
  end

  def test_non_2xx_raises_standard_error
    with_response(ReadCappedBodyTest::FakeResponse.new('{"error":"boom"}', code: 500)) do
      assert_raises(StandardError) { yelp_search_once({}, 'test-key') }
    end
  end

  def test_location_not_found_raises_typed_error_carrying_code_and_status
    body = '{"error":{"code":"LOCATION_NOT_FOUND","description":"Could not execute search"}}'
    with_response(ReadCappedBodyTest::FakeResponse.new(body, code: 400)) do
      err = assert_raises(LocationNotFound) { yelp_search_once({}, 'test-key') }
      assert_equal 400, err.status
      assert_equal 'LOCATION_NOT_FOUND', err.error_code
    end
  end

  def test_non_json_non_2xx_body_raises_generic_error_not_a_parse_error
    with_response(ReadCappedBodyTest::FakeResponse.new('<html>gateway</html>', code: 400)) do
      err = assert_raises(StandardError) { yelp_search_once({}, 'test-key') }
      refute_instance_of LocationNotFound, err
      assert_match(/HTTP 400/, err.message)
    end
  end

  def test_absent_error_body_raises_generic_error_not_a_parse_error
    with_response(ReadCappedBodyTest::FakeResponse.new(code: 400)) do
      err = assert_raises(StandardError) { yelp_search_once({}, 'test-key') }
      refute_instance_of LocationNotFound, err
      assert_match(/HTTP 400/, err.message)
    end
  end
end

class SearchYelpRateLimitTest < Minitest::Test
  def test_waits_on_retry_after_before_retrying
    calls = 0
    sleeps = []
    define_singleton_method(:yelp_search_once) do |_params, _api_key|
      calls += 1
      raise RateLimited.new('30') if calls < YELP_MAX_ATTEMPTS

      [{ 'name' => 'Recovered' }]
    end
    define_singleton_method(:yelp_api_key) { 'test-key' }
    define_singleton_method(:sleep) { |secs| sleeps << secs }

    assert_equal [{ 'name' => 'Recovered' }], search_yelp({})
    assert_equal [30.0, 30.0], sleeps, 'each 429 waits the Retry-After duration'
    assert_equal YELP_MAX_ATTEMPTS, calls, 'retries before succeeding'
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
    assert_equal YELP_MAX_ATTEMPTS, calls, 'YELP_MAX_ATTEMPTS attempts, no more'
  ensure
    singleton_class.send(:remove_method, :yelp_search_once)
    singleton_class.send(:remove_method, :yelp_api_key)
    singleton_class.send(:remove_method, :sleep)
  end

  def test_retries_transport_errors
    calls = 0
    define_singleton_method(:yelp_search_once) do |_params, _api_key|
      calls += 1
      raise Net::OpenTimeout if calls < YELP_MAX_ATTEMPTS

      [{ 'name' => 'Recovered' }]
    end
    define_singleton_method(:yelp_api_key) { 'test-key' }
    define_singleton_method(:sleep) { |_secs| }

    assert_equal [{ 'name' => 'Recovered' }], search_yelp({})
    assert_equal YELP_MAX_ATTEMPTS, calls, 'transport errors are retried'
  ensure
    singleton_class.send(:remove_method, :yelp_search_once)
    singleton_class.send(:remove_method, :yelp_api_key)
    singleton_class.send(:remove_method, :sleep)
  end

  def test_returns_nil_immediately_on_permanent_http_status
    calls = 0
    define_singleton_method(:yelp_search_once) do |_params, _api_key|
      calls += 1
      raise StandardError, 'Yelp search returned HTTP 403'
    end
    define_singleton_method(:yelp_api_key) { 'test-key' }
    define_singleton_method(:sleep) { |_secs| }

    assert_nil search_yelp({}), 'a permanent HTTP status fails fast with nil, no retry'
    assert_equal 1, calls, 'a permanent status is never re-sent'
  ensure
    singleton_class.send(:remove_method, :yelp_search_once)
    singleton_class.send(:remove_method, :yelp_api_key)
    singleton_class.send(:remove_method, :sleep)
  end

  def test_propagates_location_not_found_instead_of_folding_into_nil
    calls = 0
    define_singleton_method(:yelp_search_once) do |_params, _api_key|
      calls += 1
      raise LocationNotFound.new(400, 'LOCATION_NOT_FOUND')
    end
    define_singleton_method(:yelp_api_key) { 'test-key' }
    define_singleton_method(:sleep) { |_secs| }

    err = assert_raises(LocationNotFound) { search_yelp({}) }
    assert_equal 'LOCATION_NOT_FOUND', err.error_code
    assert_equal 1, calls, 'a permanent location error is never re-sent'
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

  def test_collectable_cities_includes_collectable_and_excludes_curated
    assert_includes COLLECTABLE_CITIES, 'tokyo', 'center+currency city is collectable'
    refute_includes COLLECTABLE_CITIES, 'nyc', 'curated city (no center/currency) is excluded'
    refute_includes COLLECTABLE_CITIES, 'australia', 'country-level key (no center) is excluded'
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
# concern handled by fill_if_absent! in pipeline_common.rb, not a line-level
# concern here: load_jsonl parses whatever valid JSON a line holds and returns it
# as-is. That rule is exercised in collect_cities_test.rb (FillIfAbsentTest).
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

  def test_unknown_city_warns_and_exits
    _stdout, stderr = capture_io do
      assert_raises(SystemExit) { select_city_files(FILES, 'paris') }
    end
    assert_match(/no data file for paris/, stderr, 'the warning names the unknown city')
    assert_match(/nyc/, stderr, 'the warning lists the available cities')
  end
end

class CityKeyForTest < Minitest::Test
  def test_strips_jsonl_suffix_from_basename
    assert_equal 'nyc', city_key_for('nyc.jsonl')
  end

  def test_strips_directory_from_a_full_path
    assert_equal 'nyc', city_key_for('/data/nyc.jsonl')
  end

  def test_stem_with_dots_keeps_them
    # Only the trailing ".jsonl" is stripped, so a stem carrying dots survives
    # intact — pinned to the current `File.basename(filename, '.jsonl')`
    # behaviour.
    assert_equal 'new.york', city_key_for('new.york.jsonl')
    assert_equal 'new.york', city_key_for('/a/b/new.york.jsonl')
  end
end

class DataFilenamesTest < Minitest::Test
  def test_returns_sorted_jsonl_basenames_only
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'b.jsonl'), '')
      File.write(File.join(dir, 'a.jsonl'), '')
      File.write(File.join(dir, 'c.txt'), '')

      assert_equal ['a.jsonl', 'b.jsonl'], data_filenames(dir),
                   'jsonl basenames sorted, non-jsonl ignored'
    end
  end

  def test_absent_dir_is_empty
    Dir.mktmpdir do |dir|
      assert_empty data_filenames(File.join(dir, 'missing'))
    end
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

class ParseCommonFlagsTest < Minitest::Test
  def test_defaults_all_false_with_no_city
    flags = parse_common_flags([])

    refute flags.dry_run
    refute flags.validate
    refute flags.help
    assert_nil flags.city
  end

  def test_parses_every_flag_and_first_city
    flags = parse_common_flags(['--dry-run', '--validate', 'tokyo', '--help'])

    assert flags.dry_run
    assert flags.validate
    assert flags.help
    assert_equal 'tokyo', flags.city
  end

  def test_short_help_alias
    assert parse_common_flags(['-h']).help
  end

  def test_leaves_only_positionals_in_argv
    argv = ['--dry-run', 'tokyo', 'osaka']

    flags = parse_common_flags(argv)

    assert_equal ['tokyo', 'osaka'], argv, 'flags are stripped; positionals remain for multi-city callers'
    assert_equal 'tokyo', flags.city
  end

  def test_unknown_flag_rejected_with_uniform_message_and_exit_1
    _stdout, stderr = capture_io do
      err = assert_raises(SystemExit) { parse_common_flags(['--dryrun']) }
      assert_equal 1, err.status
    end

    assert_match(/Unknown option: --dryrun/, stderr)
  end

  def test_unknown_flag_rejected_before_positional_is_misread
    _stdout, stderr = capture_io do
      assert_raises(SystemExit) { parse_common_flags(['--bogus', 'tokyo']) }
    end

    assert_match(/Unknown option: --bogus/, stderr)
  end

  def test_recognized_flag_excluded_from_supported_is_rejected
    # A CLI that does not honour --validate passes `supported:` without it, so
    # the flag is rejected as unknown (not silently ignored).
    _stdout, stderr = capture_io do
      err = assert_raises(SystemExit) { parse_common_flags(['--validate'], supported: %w[--dry-run --help -h]) }
      assert_equal 1, err.status
    end

    assert_match(/Unknown option: --validate/, stderr)
  end
end

class GuardResultTest < Minitest::Test
  # A recording stand-in for ConsecutiveFailureGuard, so guard_result's contract
  # can be asserted without driving the real abort counter.
  class FakeGuard
    attr_reader :failures, :resets

    def initialize
      @failures = []
      @resets = 0
    end

    def note_failure(*context)
      @failures << context
      nil
    end

    def reset
      @resets += 1
    end
  end

  def test_nil_result_notes_the_failure_and_returns_nil
    guard = FakeGuard.new

    assert_nil guard_result(guard, nil)
    assert_equal [[]], guard.failures, 'a nil result notes one failure'
    assert_equal 0, guard.resets, 'a nil result never resets the guard'
  end

  def test_nil_result_passes_context_to_note_failure
    guard = FakeGuard.new

    guard_result(guard, nil, 'nominatim', 'tokyo')

    assert_equal [['nominatim', 'tokyo']], guard.failures,
                 'the note_failure context threads through'
  end

  def test_non_nil_result_resets_the_guard_and_returns_it
    guard = FakeGuard.new

    assert_equal [], guard_result(guard, []), 'an empty [] is a success and passes through'
    assert_equal({}, guard_result(guard, {}), 'an empty {} is a success and passes through')
    assert_equal ['host'], guard_result(guard, ['host'])
    assert_equal 3, guard.resets, 'each non-nil result resets the guard'
    assert_empty guard.failures, 'a non-nil result never notes a failure'
  end
end

class RoundedCoordinatesTest < Minitest::Test
  def test_rounds_lat_and_lon_to_six_decimals
    business = { 'coordinates' => { 'latitude' => 40.7123456789, 'longitude' => -74.00654321 } }

    lat, lon = rounded_coordinates(business)

    assert_in_delta 40.712346, lat, 1e-9
    assert_in_delta(-74.006543, lon, 1e-9)
  end

  def test_missing_coordinates_hash_yields_nil_pair
    assert_equal [nil, nil], rounded_coordinates({})
  end

  def test_empty_coordinates_hash_yields_nil_pair
    assert_equal [nil, nil], rounded_coordinates({ 'coordinates' => {} })
  end

  def test_partial_coordinates_round_present_and_nil_missing
    assert_equal [40.7, nil], rounded_coordinates({ 'coordinates' => { 'latitude' => 40.7 } })
    assert_equal [nil, -74.0], rounded_coordinates({ 'coordinates' => { 'longitude' => -74.0 } })
  end
end

class DeferSleepTest < Minitest::Test
  def test_sleeps_when_pending_and_reports_cleared
    slept = []
    sleeper = ->(secs) { slept << secs }

    assert_equal false, defer_sleep(sleeper, 1.5, true), 'returns the cleared flag'
    assert_equal [1.5], slept, 'a pending flag triggers the sleep'
  end

  def test_no_sleep_when_not_pending
    slept = []
    sleeper = ->(secs) { slept << secs }

    assert_equal false, defer_sleep(sleeper, 1.5, false)
    assert_empty slept, 'a clear flag never sleeps'
  end
end

class WarnUnresolvableCityTest < Minitest::Test
  def test_warns_with_city_key_and_location
    _stdout, stderr = capture_io do
      warn_unresolvable_city('seoul', 'Seoul, South Korea')
    end

    assert_equal "  seoul: Yelp could not resolve location \"Seoul, South Korea\"; skipping city\n",
                 stderr
  end
end
