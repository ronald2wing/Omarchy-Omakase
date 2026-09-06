# frozen_string_literal: true

# Shared scaffolding for the Ruby pipeline tests. pipeline_common_test.rb and the
# per-script bin_*_test.rb files all require this after loading bin/ (which
# defines the top-level write_atomic/load_progress and the
# MAX_CONSECUTIVE_FAILURES constant), so the helper can reach those methods.

require 'tmpdir'
require 'fileutils'

# A no-op sleeper shared by every orchestration test, so a test never pays a
# real rate-limit pause while exercising the crawler loops.
NO_SLEEP = ->(_secs) {}

# One canonical Yelp business fixture shared by the merge and orchestration
# tests, so the copies of this hash cannot drift apart.
def yelp_business_fixture
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

# Captures the shared abort-on-consecutive-failures scaffolding used by the
# orchestration tests: overrides `abort` to record the message and raise
# SystemExit, runs the block (expecting the guard to abort), then asserts the
# `/consecutive/` message and that at least MAX_CONSECUTIVE_FAILURES hard-failure
# calls ran. The block receives a hard-failing provider (counts every call,
# returns nil) so each test only wires it into its orchestrator's keyword.
def assert_aborts_on_consecutive_failures(&run_body)
  abort_message = nil
  calls = 0
  hard_failure = ->(*_args) { calls += 1; nil }
  define_singleton_method(:abort) { |msg| abort_message = msg; raise SystemExit }
  begin
    assert_raises(SystemExit) { capture_io { run_body.call(hard_failure) } }
  ensure
    singleton_class.send(:remove_method, :abort)
  end

  assert_match(/consecutive/, abort_message,
               'the guard aborted with its consecutive-failure message')
  assert_operator calls, :>=, MAX_CONSECUTIVE_FAILURES,
                  'the guard aborts on the Nth consecutive failure, so at least that many calls ran'
end

# Shared setup/teardown for the orchestration tests: each creates a throwaway
# tmpdir with a `data/` subdirectory (where the pipeline writes city JSONL) and
# removes it afterwards. Subclasses override `progress_files` to name their
# resume-progress file(s); setup derives each @<ivar> path from it, so a suite
# no longer re-derives its progress paths in its own `setup`.
module TmpDataDirHelper
  # ivar name (Symbol) => progress filename. `progress:` always derives
  # @progress; a suite with a second resume file (backfill's Foursquare batch)
  # adds another key.
  def progress_files
    { progress: '.progress' }
  end

  def setup
    super
    @dir = Dir.mktmpdir
    @data_dir = File.join(@dir, 'data')
    Dir.mkdir(@data_dir)
    progress_files.each do |ivar, filename|
      instance_variable_set("@#{ivar}", File.join(@dir, filename))
    end
  end

  def teardown
    FileUtils.remove_entry(@dir)
    super
  end

  # Runs an injected-provider orchestrator with the shared data_dir/progress/
  # sleeper wiring. `via` is the orchestrator method; `provider_keyword` names
  # the keyword that method uses for its provider (search/search_provider/
  # reverse_provider); any extra kwargs (cities:, foursquare_progress_path:) are
  # forwarded unchanged.
  def run_pipeline(provider, via:, provider_keyword:, **extra)
    via.call(**{ provider_keyword => provider, data_dir: @data_dir,
                 progress_path: @progress, sleeper: NO_SLEEP }, **extra)
  end
end

# Runs `run_body` with `write_atomic` overridden to capture, via `marker` (given
# the progress set at the moment the data file is written), whether the spot was
# already marked tried. The persist-before-mark invariant holds only when the
# marker sees an unmarked progress file at write time, so the caller asserts on
# the returned marker value. The real `write_atomic` is restored afterwards.
def capture_progress_marker_at_write(progress_path, marker, &run_body)
  progress_at_write = nil
  real_write_atomic = Object.instance_method(:write_atomic)
  define_singleton_method(:write_atomic) do |path, entries|
    progress_at_write = marker.call(load_progress(progress_path))
    real_write_atomic.bind_call(self, path, entries)
  end
  begin
    run_body.call
  ensure
    singleton_class.send(:remove_method, :write_atomic)
  end
  progress_at_write
end

# Asserts the provider-adapter marking contract every orchestration suite shares:
# a nil result is a hard failure that never marks the key tried, while a non-nil
# result (even an empty []/{}) is a success that marks it. `run` performs one
# pass with the given provider result; `keys_for` reads the marked keys back and
# `expected_keys` are the keys under test. The optional block is yielded after
# each half (:nil, then :success) so a suite can add its own per-half checks.
def assert_marking_contract(run, keys_for, expected_keys, success_result: [], &after_half)
  run.call(nil)
  expected_keys.each do |key|
    refute_includes keys_for.call, key,
                    'a nil (hard-failure) provider result never marks the key tried'
  end
  after_half&.call(:nil)

  run.call(success_result)
  expected_keys.each do |key|
    assert_includes keys_for.call, key,
                    'a non-nil empty provider result is success and marks the key tried'
  end
  after_half&.call(:success)
end

