#!/bin/bash
# IP-geolocation refresh of home location. Prints {"lat":..,"lon":..,"city":".."}.
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib.sh"

require_curl

resp=$(curl -sS --max-time 15 --max-filesize 1048576 "https://ipwho.is/" 2>/dev/null) || {
  echo "ipwhois request failed"
  exit 1
}

# ipwho.is returns success:false (HTTP 200) on rate-limit/errors. Reject that
# and any null/zero coordinates before emitting a home location, or the service
# would persist (0,0) and disable restaurant lookups.
if ! echo "$resp" | jq -e '
  .success == true and
  (.latitude  | type) == "number" and
  (.longitude | type) == "number" and
  .latitude  != 0 and
  .longitude != 0
' >/dev/null 2>&1; then
  echo "ipwhois lookup failed"
  exit 1
fi

echo "$resp" | jq -c '{lat: .latitude, lon: .longitude, city: (.city // "")}'
