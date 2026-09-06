#!/usr/bin/env ruby
# frozen_string_literal: true

# Unit tests for website_sources.rb and backfill_websites.rb: host cleaning,
# aggregator detection, the Foursquare batch, distinctive tokens, and the
# website-crawl orchestration + resume loops (no API calls).

require 'minitest/autorun'
require_relative '../bin/backfill_websites'
require_relative '../bin/website_sources'
require_relative 'test_helper'

# Stubs the Foursquare seam for one test. foursquare_api_key is always stubbed,
# and exactly one of the two modes is used: `http:` (a callable receiving the
# response-sink block and returning the status code, so the real foursquare_batch
# runs against a fake transport) or `batch:` (stubs foursquare_batch to return
# that result, counting each call in @batch_calls). unstub_foursquare restores
# the real methods.
def stub_foursquare(http: nil, batch: nil)
  @batch_calls = 0
  define_singleton_method(:foursquare_api_key) { 'test-key' }
  if http
    define_singleton_method(:http_request) do |_uri, _req, **_opts, &block|
      http.call(block)
    end
  else
    define_singleton_method(:foursquare_batch) do |_center, _names|
      @batch_calls += 1
      batch
    end
  end
end

def unstub_foursquare
  %i[foursquare_api_key http_request foursquare_batch].each do |name|
    singleton_class.send(:remove_method, name) if singleton_class.method_defined?(name)
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

  def test_purely_cjk_name_is_unmatchable
    name = 'くら寿司福岡飯倉店'
    assert_equal '', normalize_name(name), 'no Latin alphanumerics => empty normalized form'
    assert_empty distinctive_tokens(name), 'no distinctive token => skipped, never matched'
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

class FoursquareBatchTest < Minitest::Test
  # A response whose body crosses MAX_BODY_BYTES, so the real read_capped_body
  # raises BodyTooLarge exactly as a capped Foursquare response would.
  class OversizedResponse
    def read_body
      yield 'x' * (MAX_BODY_BYTES + 1)
      ''
    end
  end

  # A Net::HTTPSuccess double that yields a pre-built body through read_body, so
  # foursquare_batch's `res.is_a?(Net::HTTPSuccess)` gate passes and the body
  # parses. (Net::HTTPResponse's own body= marks the body already-read, so a real
  # instance cannot be re-streamed through read_body's block form.)
  class SuccessfulResponse < Net::HTTPSuccess
    def initialize(body)
      super('1.1', '200', 'OK')
      @fake_body = body
    end

    def read_body
      yield @fake_body
      @fake_body
    end
  end

  # A non-2xx response double for the nil-vs-empty contract path: yields an
  # error body through read_body but is not a Net::HTTPSuccess, so
  # foursquare_batch's success gate rejects it and (after the fix) the method
  # returns nil rather than an empty hash.
  class ErrorResponse < Net::HTTPClientError
    def initialize(code, body = '')
      super('1.1', code, 'Error')
      @fake_body = body
    end

    def read_body
      yield @fake_body
      @fake_body
    end
  end

  # A body cap is a hard failure, not a clean miss: the method's contract is nil
  # on hard failure, so a capped page must not surface the partial result built
  # from earlier pages (which the caller would record as "permanently tried").
  # Two pages prove that: page 1 is a full page that builds a partial result,
  # page 2 is oversized, so the cap aborts and the partial must be discarded.
  def test_body_too_large_returns_nil_not_partial
    # A full page (size == FOURSQUARE_PAGE_SIZE) keeps the loop paging; one
    # result matches a pending name so a partial result really exists. A second
    # pending name ('unmatched') never resolves on page 1, so the early-exit
    # can't fire and the loop must page on to the oversized page 2.
    successful_page = SuccessfulResponse.new(
      JSON.generate('results' => Array.new(FOURSQUARE_PAGE_SIZE) do |i|
        if i.zero?
          { 'name' => 'Sushi Edo', 'website' => 'https://sushiedo.com.au' }
        else
          { 'name' => "Filler #{i}" }
        end
      end)
    )
    pages = [successful_page, OversizedResponse.new]

    stub_foursquare(http: ->(block) { block&.call(pages.shift); 200 })

    assert_nil foursquare_batch([35.0, 139.0], Set.new(['sushiedo', 'unmatched']))
  ensure
    unstub_foursquare
  end

  # A non-2xx status (429 quota, 401 bad key) is a hard failure, not a
  # successful-but-empty page: the method must return nil, never the empty {}
  # a caller would read as "success" and mark every pending name tried.
  def test_non_2xx_returns_nil
    [429, 401].each do |status|
      stub_foursquare(http: lambda do |block|
        block&.call(ErrorResponse.new(status.to_s, JSON.generate('error' => 'no credits')))
        status
      end)

      assert_nil foursquare_batch([35.0, 139.0], Set.new(['sushiedo'])),
                 "a #{status} response must return nil, not an empty hash"
    ensure
      unstub_foursquare
    end
  end

  def test_early_exit_after_every_pending_name_resolves
    # A full page (size == FOURSQUARE_PAGE_SIZE) resolves every pending name, so
    # the short-page break never fires — only the early exit can stop the loop.
    full_page = SuccessfulResponse.new(
      JSON.generate('results' => Array.new(FOURSQUARE_PAGE_SIZE) do |i|
        case i
        when 0 then { 'name' => 'Sushi Edo', 'website' => 'https://sushiedo.com.au' }
        when 1 then { 'name' => 'Sushi Saito', 'website' => 'https://sushisaito.com' }
        else { 'name' => "Filler #{i}" }
        end
      end)
    )
    pages_requested = 0
    stub_foursquare(http: lambda do |block|
      pages_requested += 1
      block&.call(full_page)
      200
    end)

    result = foursquare_batch([35.0, 139.0], Set.new(['sushiedo', 'sushisaito']))

    assert_equal 1, pages_requested,
                 'every name resolved on a full page, so the early exit stops paging'
    assert_equal %w[sushiedo sushisaito].to_set, result.keys.to_set
  ensure
    unstub_foursquare
  end

  def test_empty_pending_set_still_runs_first_page
    # A full page keeps the short-page break from firing, so an empty pending set
    # proves the early exit (not max pages) stops the loop after the first page —
    # the empty set must not short-circuit before that first request.
    full_page = SuccessfulResponse.new(
      JSON.generate('results' => Array.new(FOURSQUARE_PAGE_SIZE) { |i| { 'name' => "Filler #{i}" } })
    )
    pages_requested = 0
    stub_foursquare(http: lambda do |block|
      pages_requested += 1
      block&.call(full_page)
      200
    end)

    result = foursquare_batch([35.0, 139.0], Set.new)

    assert_equal 1, pages_requested, 'an empty pending set must still run the first page'
    assert_empty result
  ensure
    unstub_foursquare
  end
end

class BackfillWebsitesOrchestrationTest < Minitest::Test
  include TmpDataDirHelper

  def progress_files
    { progress: '.website-progress', foursquare_progress: '.foursquare-progress' }
  end

  # MIN_MISSING_TO_CRAWL missing spots: the crawl early-returns below that
  # count, so the fake city needs that many missing entries to reach the
  # provider loop. The fake key has no CITIES center, so the Foursquare batch
  # phase is skipped (no network) and only the injected per-spot provider runs.
  def write_missing_city
    entries = Array.new(MIN_MISSING_TO_CRAWL) { |i| { 'name' => "Sushi Edo #{i}" } }
    write_atomic(File.join(@data_dir, 'fakeville.jsonl'), entries)
  end

  def run_backfill(provider)
    run_pipeline(provider, via: method(:backfill_websites), provider_keyword: :search_provider,
                 foursquare_progress_path: @foursquare_progress)
  end

  def test_fill_writes_data_file_before_marking_tried
    write_missing_city
    key = 'Sushi Edo 0|fakeville'
    progress_at_write = capture_progress_marker_at_write(
      @progress, ->(progress) { progress.include?(key) }
    ) do
      run_backfill(->(_name, _city) { ['sushiedo.com.au'] })
    end

    assert_equal false, progress_at_write,
                 'the tried key is not yet written when the data file is persisted'
    assert_equal 'https://sushiedo.com.au',
                 load_jsonl(File.join(@data_dir, 'fakeville.jsonl')).first['website'],
                 'the fill reached disk'
    assert_includes load_progress(@progress), key, 'the key is marked after the fill'
  end

  def test_hard_failure_is_not_marked_tried
    write_missing_city
    # The first spot hard-fails; the rest succeed (which also resets the failure
    # counter so the run never trips the consecutive-failure abort).
    hard_failure = lambda do |name, _city|
      name == 'Sushi Edo 0' ? nil : ['sushiedo.com.au']
    end

    assert_marking_contract(
      ->(result) do
        write_missing_city
        # Reset the shared progress file so each half runs against a clean
        # "already tried" set — the nil half's Phase 2 marks the other spots,
        # which would otherwise make the success half early-return.
        File.delete(@progress) if File.exist?(@progress)
        run_backfill(result.nil? ? hard_failure : ->(_name, _city) { result })
      end,
      -> { load_progress(@progress) },
      ['Sushi Edo 0|fakeville']
    ) do |phase|
      case phase
      when :nil
        assert_nil load_jsonl(File.join(@data_dir, 'fakeville.jsonl')).first['website'],
                   'the hard-failed spot gains no website, so a re-run retries it'
      when :success
        assert_equal MIN_MISSING_TO_CRAWL, load_progress(@progress).size,
                     'every empty-but-successful spot is marked tried'
      end
    end
  end

  def test_aborts_on_consecutive_hard_failures
    write_missing_city
    assert_aborts_on_consecutive_failures do |hard_failure|
      run_backfill(hard_failure)
    end
  end

  def test_early_return_counts_only_untried_missing
    write_missing_city
    keys = (0...MIN_MISSING_TO_CRAWL).map { |i| "Sushi Edo #{i}|fakeville" }
    File.write(@progress, keys.map { |k| "#{k}\n" }.join)
    calls = 0
    result = backfill_websites(search_provider: ->(_name, _city) { calls += 1; [] },
                               data_dir: @data_dir, progress_path: @progress,
                               foursquare_progress_path: @foursquare_progress,
                               sleeper: NO_SLEEP)

    assert_equal({ filled: 0, skipped_empty: 0, errored: 0 }, result,
                 'the crawl early-returns when every missing spot is already tried')
    assert_equal 0, calls, 'no provider call is issued'
  end

  def test_filled_spots_in_done_do_not_suppress_the_guard
    # `done` holds keys for spots already filled (no longer missing), and more
    # of them than there are currently-missing spots. The old
    # `missing - done.size` subtraction understates the untried count (negative
    # here), so the guard would skip the crawl forever despite real untried
    # work. The fixed guard counts only missing spots whose key is absent from
    # `done`.
    missing_entries = Array.new(MIN_MISSING_TO_CRAWL) { |i| { 'name' => "Sushi Edo #{i}" } }
    filled_entries = Array.new(MIN_MISSING_TO_CRAWL + 1) do |i|
      { 'name' => "Sushi Saito #{i}", 'website' => 'https://sushisaito.com' }
    end
    write_atomic(File.join(@data_dir, 'fakeville.jsonl'), missing_entries + filled_entries)
    File.write(@progress, filled_entries.map { |entry| "#{entry['name']}|fakeville\n" }.join)

    calls = 0
    result = backfill_websites(search_provider: ->(_name, _city) { calls += 1; ['sushiedo.com.au'] },
                               data_dir: @data_dir, progress_path: @progress,
                               foursquare_progress_path: @foursquare_progress,
                               sleeper: NO_SLEEP)

    assert_equal MIN_MISSING_TO_CRAWL, calls,
                 'the MIN_MISSING_TO_CRAWL untried missing spots still crawl'
    assert_equal({ filled: MIN_MISSING_TO_CRAWL, skipped_empty: 0, errored: 0 }, result)
  end

  def test_duplicate_name_issues_one_request_and_one_sleep
    # Two spots with the identical name in one city form the same Nominatim query
    # ("name city"), so the per-run memo must collapse them to a single provider
    # call — and the rate-limit sleep must fire once per real request, not once
    # per spot. With one duplicated name among N spots, the run issues N-1
    # requests and N-1 sleeps.
    entries = Array.new(MIN_MISSING_TO_CRAWL - 2) { |i| { 'name' => "Filler #{i}" } }
    entries.concat([{ 'name' => 'Sushi Edo' }, { 'name' => 'Sushi Edo' }])
    write_atomic(File.join(@data_dir, 'fakeville.jsonl'), entries)

    calls = 0
    sleeps = 0
    backfill_websites(search_provider: ->(_name, _city) { calls += 1; ['sushiedo.com.au'] },
                      data_dir: @data_dir, progress_path: @progress,
                      foursquare_progress_path: @foursquare_progress,
                      sleeper: ->(_secs) { sleeps += 1 })

    assert_equal MIN_MISSING_TO_CRAWL - 1, calls,
                 'two identical names in one city collapse to a single request'
    assert_equal calls, sleeps, 'the sleep fires once per real request, not per spot'
  end

  def test_distinct_names_issue_distinct_requests
    # The memo must collapse only identical queries: two spots with different
    # names in one city are different queries and each issues its own request.
    entries = Array.new(MIN_MISSING_TO_CRAWL - 2) { |i| { 'name' => "Filler #{i}" } }
    entries.concat([{ 'name' => 'Sushi Edo' }, { 'name' => 'Sushi Saito' }])
    write_atomic(File.join(@data_dir, 'fakeville.jsonl'), entries)

    calls = 0
    backfill_websites(search_provider: lambda do |name, _city|
                        calls += 1
                        name == 'Sushi Edo' ? ['sushiedo.com.au'] : ['sushisaito.com']
                      end,
                      data_dir: @data_dir, progress_path: @progress,
                      foursquare_progress_path: @foursquare_progress,
                      sleeper: NO_SLEEP)

    assert_equal MIN_MISSING_TO_CRAWL, calls, 'distinct names each issue their own request'
  end
end

class FoursquareResumeTest < Minitest::Test
  include TmpDataDirHelper

  # A real CITIES key with a center, so Phase 1's `next unless center` doesn't
  # skip the Foursquare batch (the orchestrator tests above use a centerless key).
  CITY = 'tokyo'

  def progress_files
    { progress: '.website-progress', foursquare_progress: '.foursquare-progress' }
  end

  def setup
    super
    entries = Array.new(MIN_MISSING_TO_CRAWL) { |i| { 'name' => "Sushi Edo #{i}" } }
    write_atomic(File.join(@data_dir, "#{CITY}.jsonl"), entries)
  end

  def attempted_keys
    (0...MIN_MISSING_TO_CRAWL).map { |i| "Sushi Edo #{i}|#{CITY}" }
  end

  def run_backfill
    # Phase 2 provider succeeds-empty for every spot, so it never trips the
    # consecutive-failure abort while Phase 1's marking is what's under test.
    run_pipeline(->(_name, _city) { [] }, via: method(:backfill_websites),
                 provider_keyword: :search_provider,
                 foursquare_progress_path: @foursquare_progress)
  end

  def test_nil_batch_is_never_marked
    assert_marking_contract(
      ->(result) do
        # Reset the shared website progress so each half runs against a clean
        # "already tried" set — the nil half's Phase 2 marks every spot, which
        # would otherwise make the success half early-return before the batch.
        File.delete(@progress) if File.exist?(@progress)
        stub_foursquare(batch: result)
        run_backfill
      end,
      -> { load_progress(@foursquare_progress) },
      [attempted_keys.first],
      success_result: {} # success-but-empty still marks, matching .website-progress
    ) do |phase|
      case phase
      when :nil
        assert_equal 1, @batch_calls, 'the batch was attempted once'
        assert_empty load_progress(@foursquare_progress),
                     'a nil (hard-failure) batch must not mark any name tried'
      when :success
        assert_equal attempted_keys.sort, load_progress(@foursquare_progress).to_a.sort,
                     'a non-nil batch records every pending name it attempted'
      end
    end
  ensure
    unstub_foursquare
  end

  # End-to-end nil-vs-empty chain: the real foursquare_batch against a stubbed
  # HTTP transport returning 429 must return nil, so backfill_websites does not
  # record the pending names in .foursquare-progress. Before the fix the 429
  # left `results` nil, the loop broke, and foursquare_batch returned {} —
  # permanently marking the city's spots tried after a request that did nothing.
  def test_non_2xx_batch_is_not_marked_tried
    define_singleton_method(:foursquare_api_key) { 'test-key' }
    define_singleton_method(:http_request) do |_uri, _req, **_opts, &block|
      block&.call(FoursquareBatchTest::ErrorResponse.new('429', JSON.generate('error' => 'no credits')))
      429
    end

    run_backfill

    assert_empty load_progress(@foursquare_progress),
                 'a 429 (non-2xx) batch must not mark any pending name tried'
  ensure
    singleton_class.send(:remove_method, :foursquare_api_key)
    singleton_class.send(:remove_method, :http_request)
  end

  def test_skip_batch_when_every_pending_name_marked
    File.write(@foursquare_progress, attempted_keys.map { |key| "#{key}\n" }.join)
    stub_foursquare(batch: {})
    run_backfill
    assert_equal 0, @batch_calls,
                 'no batch is issued when every pending name is already marked'
  ensure
    unstub_foursquare
  end
end
