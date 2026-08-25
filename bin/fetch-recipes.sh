#!/bin/bash
# Fetch recipes from TheMealDB, keyless.
# Usage: fetch-recipes.sh <query>
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib.sh"

query="${1:-}"

if [[ -z $query ]]; then
  echo "usage: fetch-recipes.sh <query>" >&2
  exit 2
fi

require_curl

resp=$(curl -sS --max-time 25 --max-filesize 5242880 -G "https://www.themealdb.com/api/json/v1/1/search.php" --data-urlencode "s=$query" 2>/dev/null) || {
  echo "themealdb request failed"
  exit 1
}

# A busy endpoint returns HTML (HTTP 200); .meals is then absent. Validate the
# payload first and stage the parse, so a bad response never clobbers a good cache.
if ! echo "$resp" | jq -e '.meals | type == "array" and length > 0' >/dev/null 2>&1; then
  echo "themealdb returned no meals"
  exit 1
fi

parsed=$(echo "$resp" | jq -c '
  [.meals[]? | {
    id: ("recipe-" + .idMeal),
    source: "recipe",
    name: .strMeal,
    cuisine: (.strArea // ""),
    mealType: (if (.strCategory // "") == "Breakfast" then "breakfast" else "" end),
    category: (.strCategory // "")
  }]
' 2>/dev/null) || {
  echo "themealdb response parse failed"
  exit 1
}

save_cache recipes "$parsed"
