#!/bin/bash
# Shared paths + helpers for the omakase plugin. Source this from other bin scripts.
set -uo pipefail

PLUGIN_ID="omakase"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/$PLUGIN_ID"
CACHE_DIR="$STATE_DIR/cache"

have() { command -v "$1" >/dev/null 2>&1; }

# Fail fast when curl is missing. The message goes to stdout, not stderr, because
# the service surfaces the process stdout (stderr is discarded) as its last error.
require_curl() {
  if ! have curl; then
    echo "curl not installed"
    exit 1
  fi
}

# Write a staged JSON result to the cache file and echo it back for the service.
save_cache() {
  local name="$1" content="$2"
  mkdir -p "$CACHE_DIR"
  printf '%s\n' "$content" > "$CACHE_DIR/$name.json"
  cat "$CACHE_DIR/$name.json"
}
