#!/bin/bash
# Static validation for the omakase plugin.
set -uo pipefail

PLUGIN_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fail=0

check() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "ok: $desc"
  else
    echo "FAIL: $desc"
    fail=$((fail + 1))
  fi
}

MANIFEST="$PLUGIN_DIR/manifest.json"

check "manifest is valid JSON" jq -e . "$MANIFEST"
check "schemaVersion == 1" jq -e '.schemaVersion == 1' "$MANIFEST"

for field in id name version author description; do
  check "manifest.$field is non-empty string" jq -e --arg f "$field" 'has($f) and (.[$f] | type == "string") and (.[$f] | length > 0)' "$MANIFEST"
done

id=$(jq -r '.id' "$MANIFEST")
check "id is lowercase" bash -c "[[ '$id' == '${id,,}' ]]"
check "id matches allowed pattern" bash -c "[[ '$id' =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && '$id' != *..* && '$id' != omarchy.* ]]"

check "kinds is non-empty array" jq -e '.kinds | type == "array" and length > 0' "$MANIFEST"

for kind_entry in "bar:bar" "bar-widget:barWidget" "menu:menu" "overlay:overlay" "panel:panel" "service:service"; do
  kind="${kind_entry%%:*}"
  ep="${kind_entry##*:}"
  if jq -e --arg k "$kind" '.kinds | index($k) != null' "$MANIFEST" >/dev/null 2>&1; then
    val=$(jq -r --arg ep "$ep" '.entryPoints[$ep] // ""' "$MANIFEST")
    check "entry point $ep exists and is safe" bash -c "[[ -n '$val' && '$val' != /* && '$val' != *..* && -f '$PLUGIN_DIR/$val' ]]"
  fi
done

for script in "$PLUGIN_DIR"/bin/*; do
  if [[ -f $script ]]; then
    check "bash -n $(basename "$script")" bash -n "$script"
  fi
done

check "config.example.json is valid JSON" jq -e . "$PLUGIN_DIR/config.example.json"

if (( fail == 0 )); then
  echo "all validations passed"
else
  echo "failed: $fail"
  exit 1
fi
