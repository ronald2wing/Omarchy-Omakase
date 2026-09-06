#!/usr/bin/env ruby
# frozen_string_literal: true

# JSONL + progress-file IO shared by the pipeline scripts: loading a progress
# file, loading a data file (skipping bad lines), atomic writes, and name
# normalization for fuzzy matching.

require 'json'
require 'set'
require 'tempfile'

# Load a progress file (one completed key per line) into a Set.
def load_progress(path)
  return Set.new unless File.exist?(path)

  Set.new(File.readlines(path, chomp: true).map(&:strip).reject(&:empty?))
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

# Normalize a name for fuzzy matching: lowercase, alphanumerics only.
def normalize_name(name)
  name.to_s.downcase.gsub(/[^a-z0-9]/, '')
end
