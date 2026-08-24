#!/bin/bash
# Fetch nearby restaurants from the Overpass API (OpenStreetMap), keyless.
# Usage: fetch-restaurants.sh <lat> <lon> <radiusKm> [query]
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib.sh"

lat="${1:-}"
lon="${2:-}"
radius="${3:-10}"
query="${4:-}"

if [[ -z $lat || -z $lon ]]; then
  echo "usage: fetch-restaurants.sh <lat> <lon> <radiusKm> [query]" >&2
  exit 2
fi

require_curl

# Overpass `around:` is in METERS, but the config radius is in KM — convert.
radiusMeters=$((radius * 1000))

# Build Overpass query. The optional name filter uses Overpass regex syntax, so
# strip its metacharacters from user input to keep the query well-formed.
if [[ -n $query ]]; then
  safe_query=$(printf '%s' "$query" | tr -d '[]~()"\\')
  if [[ -z $safe_query ]]; then
    echo "search query must contain letters or numbers" >&2
    exit 2
  fi
  q="[out:json][timeout:25];(nwr[\"amenity\"=\"restaurant\"][\"name\"~\"${safe_query}\",i](around:${radiusMeters},${lat},${lon}););out center;"
else
  q="[out:json][timeout:25];(nwr[\"amenity\"=\"restaurant\"](around:${radiusMeters},${lat},${lon}););out center;"
fi

resp=$(curl -sS --max-time 25 -G "https://overpass-api.de/api/interpreter" --data-urlencode "data=$q" 2>/dev/null) || {
  echo "overpass request failed"
  exit 1
}

# The main endpoint returns an HTML error page (HTTP 200) when busy. Retry
# against a mirror before giving up, and never clobber a good cache.
if ! printf '%s' "$resp" | jq -e '.elements' >/dev/null 2>&1; then
  resp=$(curl -sS --max-time 25 -G "https://overpass.kumi.systems/api/interpreter" --data-urlencode "data=$q" 2>/dev/null) || {
    echo "overpass request failed"
    exit 1
  }
fi

parsed=$(echo "$resp" | jq -c --argjson hlat "$lat" --argjson hlon "$lon" '
  def haversineKm($lat2; $lon2):
    (($hlat - $lat2) * 3.141592653589793 / 180) as $dLat
    | (($hlon - $lon2) * 3.141592653589793 / 180) as $dLon
    | ($hlat * 3.141592653589793 / 180) as $rLat1
    | ($lat2 * 3.141592653589793 / 180) as $rLat2
    | (($dLat/2) | sin | .*.) as $a
    | ($a + (($rLat1|cos) * ($rLat2|cos) * (($dLon/2)|sin|.*.))) as $b
    | (2 * 6371 * ((($b | if . > 1 then 1 else . end) | sqrt) | asin));
  [.elements[]? | select(.tags.name != null) | {
    id: ("rest-" + (.id|tostring)),
    source: "restaurant",
    name: .tags.name,
    cuisine: (.tags.cuisine // ""),
    distanceKm: (haversineKm((.center.lat // .lat); (.center.lon // .lon)) * 10 | round | . / 10),
    address: (.tags["addr:street"] // ""),
    website: (.tags.website // "")
  }]
' 2>/dev/null) || {
  echo "overpass response parse failed"
  exit 1
}

save_cache restaurants "$parsed"
