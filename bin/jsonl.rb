#!/usr/bin/env -S -u RUBYOPT -u RUBYLIB -u RUBYGEMS_GEMDEPS -u BUNDLE_GEMFILE -u BUNDLE_PATH -u BUNDLE_BIN_PATH -u GEM_HOME -u GEM_PATH /usr/bin/ruby
# frozen_string_literal: true

# JSONL + progress-file IO shared by the pipeline scripts: loading a progress
# file (load_progress/load_progress_with_resume/append_progress), opening and
# closing a progress file across a run (open_progress/close_progress/
# mark_progress), loading a data file (load_jsonl, which skips bad lines), atomic
# writes in persist-before-mark order (write_atomic/persist_then_mark), name
# normalization (normalize_name/normalized_name_or_nil), and the city-file
# helpers (select_city_files, data_filenames/data_paths, city_key_for).

require 'json'
require 'set'
require 'tempfile'

# Load a progress file (one completed key per line) into a Set.
def load_progress(path)
  return Set.new unless File.exist?(path)

  Set.new(File.readlines(path, chomp: true).map(&:strip).reject(&:empty?))
end

# Load a progress file and print the standard resume announcement, returning the
# set. The three crawlers that resume per-spot/per-coordinate keys
# (backfill_websites, geocode_fallback, reverse_geocode_addresses) all print the
# identical "Resuming: N spots already tried" line (suppressed when empty), so the
# load and the announcement stay together here.
def load_progress_with_resume(path)
  done = load_progress(path)
  puts "Resuming: #{done.size} spots already tried" unless done.empty?
  done
end

# Append a batch of completed keys to a progress file opened in append mode —
# one key per line, flushed after the batch so a crash mid-run never loses a
# half-flushed set. A nil file (dry run) or an empty batch is a no-op.
def append_progress(progress_file, keys)
  return if progress_file.nil? || keys.empty?

  progress_file.write("#{keys.join("\n")}\n")
  progress_file.flush
end

# Open a progress file for appending, or return nil on a dry run (so every
# append_progress call is a no-op and nothing reaches disk). The matching
# close_progress below is the safe close. Shared by the three crawlers that hold
# a progress file open across a whole run.
def open_progress(progress_path, dry_run:)
  dry_run ? nil : File.open(progress_path, 'a')
end

# Close a progress file when one was opened (open_progress returns nil on a dry
# run). Safe to call unconditionally — a nil file is a no-op.
def close_progress(file)
  file&.close
end

# Append keys to a progress file in one open/append/close, for a caller that
# marks progress per unit of work instead of holding a file open across a whole
# run (collect_cities marks each city as it completes). The open/append/close
# reuses append_progress, so the on-disk format is identical to a caller that
# holds the file open.
def mark_progress(progress_path, keys)
  File.open(progress_path, 'a') { |f| append_progress(f, keys) }
end

# Load a JSONL file into an array of parsed objects. Blank lines are skipped and
# malformed lines are warned about + skipped, so one bad line never aborts the
# pipeline. The warning uses the file's basename (path is not always the stem).
def load_jsonl(path)
  File.readlines(path, chomp: true).filter_map do |line|
    next if line.strip.empty?

    begin
      JSON.parse(line)
    rescue JSON::ParserError => e
      warn "#{File.basename(path)}: skipping malformed JSON line: #{e.message}"
      nil
    end
  end
end

# Atomically write `entries` (JSON objects, or nil for blank lines) to `path`
# via a same-directory temp file + rename, so a reader never sees a half-written
# file. A Tempfile's unpredictable name defeats a pre-placed symlink at the
# predictable "#{path}.tmp" (which `File.open(tmp, 'w')` would follow and
# overwrite), and fsync-before-rename makes the result durable before it swaps in.
def write_atomic(path, entries)
  tmp = Tempfile.new(['.', '.tmp'], File.dirname(path))
  begin
    entries.each do |entry|
      tmp.write(entry.nil? ? "\n" : JSON.generate(entry) + "\n")
    end
    tmp.fsync
    tmp.close
    # Tempfile.new creates 0600 and rename preserves it; restore the destination's
    # prior mode (0644 for a new file) so a pipeline run never churns data files
    # to owner-only or resets a user's custom mode.
    mode = File.exist?(path) ? (File.stat(path).mode & 0o777) : 0o644
    File.rename(tmp.path, path)
    File.chmod(mode, path)
  ensure
    tmp.close!
  end
end

# Persist a data file BEFORE recording its spots as tried in the progress
# file. The order is what makes resume safe: a crash between the two writes
# leaves unwritten fills unmarked, so the next run retries them instead of
# permanently skipping spots whose fill never reached disk — the reverse order
# (mark first, write later) was the bug. The data write is skipped when `changed`
# is false, but the progress mark always runs (a spot that succeeded with no
# result is still "tried", never re-crawled). Returns whether the data file was
# written, so a caller can count changed files.
def persist_then_mark(changed, data_path, entries, progress_file, tried_keys)
  write_atomic(data_path, entries) if changed
  append_progress(progress_file, tried_keys)
  changed
end

# Normalize a name for fuzzy matching: lowercase, alphanumerics only.
def normalize_name(name)
  name.to_s.downcase.gsub(/[^a-z0-9]/, '')
end

# Normalize a name for fuzzy matching, or nil when it has no matchable key: a
# purely-CJK name (no Latin alphanumerics) normalizes to "", and storing that
# empty key would collapse every CJK spot onto the single "" bucket, letting the
# first CJK result match all of them. Callers skip a nil result rather than
# storing the empty key.
def normalized_name_or_nil(name)
  normalized = normalize_name(name)
  normalized.empty? ? nil : normalized
end

# Fold a name for an exact raw-title comparison: lowercase + collapse runs of
# whitespace. Unlike normalize_name it keeps non-Latin characters, so a pure-CJK
# title still yields a usable key. Used only by refresh_yelp_fields' Phase 2 CJK
# fallback, where the normalized (alnum-stripped) key is empty and an exact title
# match is the only safe remaining signal. Deliberately a different contract from
# normalize_name — do not merge them.
def collapse_name(name)
  name.to_s.downcase.gsub(/\s+/, ' ').strip
end

# Narrow a list of data filenames to the one matching `city_arg`. The ".jsonl"
# suffix is optional; no argument means every file (the "all cities" case). An
# unknown city warns and exits 1 — the caller's typo must not silently no-op
# into an empty run (which would read as "0 entries" and exit 0).
def select_city_files(files, city_arg)
  return files unless city_arg

  target = city_arg.end_with?('.jsonl') ? city_arg : "#{city_arg}.jsonl"
  selected = files.select { |file| file == target }
  if selected.empty?
    available = files.map { |file| city_key_for(file) }.sort.join(', ')
    warn "no data file for #{city_arg} (available: #{available})"
    exit 1
  end
  selected
end

# Return the city key (the filename stem) for a `*.jsonl` path or basename, so a
# data path "data/nyc.jsonl" and a bare "nyc.jsonl" both yield "nyc". Only the
# trailing ".jsonl" is stripped — a stem carrying dots ("new.york.jsonl") keeps
# them ("new.york"). Unifies the suffix-strip idiom (which left a directory
# prefix on a full path) with the basename-with-suffix idiom.
def city_key_for(filename)
  File.basename(filename, '.jsonl')
end

# Return the sorted list of `*.jsonl` basenames in `data_dir` (the keys a
# pipeline iterates). An empty or absent dir yields an empty array.
def data_filenames(data_dir)
  Dir.glob(File.join(data_dir, '*.jsonl')).map { |path| File.basename(path) }.sort
end

# Return the sorted list of full `*.jsonl` paths in `data_dir` — the counterpart
# of data_filenames, which returns basenames. Callers that open the files
# directly (sort_data.rb, normalize_locations.rb) iterate these. An empty or
# absent dir yields an empty array.
def data_paths(data_dir)
  Dir.glob(File.join(data_dir, '*.jsonl')).sort
end
