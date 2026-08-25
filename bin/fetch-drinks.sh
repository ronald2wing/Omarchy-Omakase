#!/bin/bash
# Fetch drink names + thumbnails from TheCocktailDB (TheMealDB's drinks API), keyless.
# Usage: fetch-drinks.sh
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib.sh"

require_curl

tmp=$(mktemp)
fetch_ok=1
for category in Cocktail Ordinary_Drink; do
  curl -sS --max-time 25 --max-filesize 5242880 -G "https://www.thecocktaildb.com/api/json/v1/1/filter.php" --data-urlencode "c=$category" 2>/dev/null >> "$tmp" || fetch_ok=0
done

if (( fetch_ok == 0 )); then
  echo "cocktaildb request failed"
  rm -f "$tmp"
  exit 1
fi

# Stage the parse and reject an empty result, so a bad/busy response never
# clobbers a good cache.
parsed=$(jq -s '
  [.[]?.drinks[]? | {
    id: ("drink-" + .idDrink),
    name: .strDrink,
    thumb: (.strDrinkThumb // "")
  }] | unique_by(.name)
' "$tmp" 2>/dev/null) || {
  echo "cocktaildb response parse failed"
  rm -f "$tmp"
  exit 1
}
rm -f "$tmp"

if [[ $parsed == '[]' ]]; then
  echo "cocktaildb returned no drinks"
  exit 1
fi

save_cache drinks "$parsed"
