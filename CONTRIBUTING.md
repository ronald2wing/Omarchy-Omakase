# Contributing to Omakase

Contributions cover the seed data (`data/*.jsonl`), the Ruby pipeline (`bin/`),
and the QML/JavaScript plugin. Pull requests target `main`. This file owns the
data schema, the pipeline, verification, and install; architecture and QML
gotchas live in `AGENTS.md`, user-facing prose in `README.md`.

## Data files

Spot data lives in `data/<city>.jsonl` — one JSON object per line, no
pretty-printing. The filename stem (without `.jsonl`) is the canonical city key
(lowercase, hyphenated for multi-word keys: `nyc`, `san-francisco`); a spot
carries no `city` field of its own. `australia.jsonl` is the one country-level
key — spots across Australia under a single file.

Coverage at HEAD, recounted from `data/*.jsonl`: **5,010 spots across 65
files — 3,018 carry a `website`, 4,943 an `address`, 475 a `neighborhood`.**
These drift as the pipeline runs.

### Field reference

`spotFieldTypes` in `spot-utils.js` is the authority for the persisted field
set: a field name → runtime-type map holding 22 fields. `Service.qml` derives
its `persistedSpotFields` whitelist from `Object.keys(SpotUtils.spotFieldTypes)`,
so the two always agree, and the map's insertion order is the field order
written into `state.json`. Every spot is passed through `sanitizeSpot`, which
drops any field not in the whitelist and coerces the rest to the listed type
(`coerceSpotField`). The table below lists those 22 runtime fields plus the
pipeline-only `yelp_id`, which is deliberately absent from `spotFieldTypes`.
Journal identity (name/city canonicalization) and the user-spot merge live in
the dual-use `journal-identity.js`, not `Service.qml`.

| Field | Type | Source | Holds |
|-------|------|--------|-------|
| `name` | string | hand | Spot name. The only strictly required field — the seed loader skips entries without it. e.g. `"Hatsu Omakase"`. |
| `lat` / `lon` | number | hand / machine | Coordinates (6 decimals). `collect_cities.rb` sets them; `refresh_yelp_fields.rb` fills them when missing; `geocode_fallback.rb` replaces city-centre placeholders. Drive distance sort and the Maps fallback link. e.g. `40.725375` / `-73.987261`. |
| `neighborhood` | string | hand | Real sub-area name only, e.g. `"Nolita"`. Never a street address — an absent field means no distinct sub-area. Hand-curated; the pipeline never writes it (but `normalize_locations.rb` drops a value that is actually a street address). |
| `website` | string | hand / machine | Official site URL. `backfill_websites.rb` fills it when missing. e.g. `"https://aoitsuki.com.au"`. |
| `phone` | string | hand / machine | Phone number, taken from Yelp's `display_phone` (`refresh_yelp_fields.rb` falls back to the raw `phone` field). e.g. `"(631) 868-8600"`. |
| `price` | string | hand | The spot's menu price: a bare number or range, no symbol or separators. e.g. `"255"`, `"68-150"`. |
| `courses` | string | hand | Number of courses, e.g. `"20"`; an AYCE token (e.g. `"AYCE"`) marks an all-you-can-eat spot. |
| `currency` | string | hand / machine | ISO code (`USD`, `JPY`, …). The UI derives the price symbol from it. `collect_cities.rb` sets it from `CITIES`. e.g. `"AUD"`. |
| `discount_window` | string | hand | Discount window, e.g. `"8pm"`. |
| `discount` | string | hand | e.g. `"50%"`. |
| `yelp_url` | string | machine | Yelp link. e.g. `"https://www.yelp.com/biz/hatsu-omakase-new-york"`. |
| `region_code` | string | machine | Yelp `location.state` — a region code; a US state only for US spots, foreign values are prefecture/province codes (`NH` is Noord-Holland in Amsterdam, `"13"` is a Tokyo prefecture). e.g. `"NY"`. |
| `image_url` | string | machine | Yelp header image. e.g. `"https://s3-media0.fl.yelpcdn.com/bphoto/7OdLnWObiEqDS6VkQkzc8Q/o.jpg"`. |
| `is_closed` | bool | machine | Yelp's permanently-closed flag. e.g. `false`. |
| `yelp_rating` | number | machine | Yelp rating (0–5). e.g. `4.3`. |
| `yelp_review_count` | number | machine | Yelp review count. e.g. `101`. |
| `yelp_price_level` | string | machine | Yelp's `$$` bucket — not the spot's `price`. e.g. `"$$"`. |
| `country` | string | machine | Yelp location `country`. e.g. `"US"`. |
| `transactions` | string array | machine | Yelp transaction types. e.g. `["delivery", "pickup"]`. |
| `address` | string | hand / machine | Street address. `normalize_locations.rb` derives it from `display_address[0]` (or an address-like `neighborhood`); `reverse_geocode_addresses.rb` fills the rest from coordinates. e.g. `"133 E 4th St"`. |
| `display_address` | string array | machine | Yelp's formatted address array. e.g. `["133 E 4th St", "New York, NY 10003"]`. |
| `yelp_id` | string | machine | Yelp identity, used by the refresh scripts to match entries. **Pipeline-only** — it is deliberately absent from `spotFieldTypes`, so `sanitizeSpot` drops it and it never reaches `state.json` or the UI. |

`transactions`/`display_address`
are arrays; an **empty array means "no data"** — a refresh treats `[]` the same
as an absent field.

### Sort order

Files are kept sorted by `name` (case-insensitive, locale-independent), with
ties broken by `lat` then `lon`; spots with missing coordinates sort last
(`entry_sort_key` in `bin/pipeline_common.rb`). `collect_cities.rb` sorts
automatically; only a hand edit needs an explicit `ruby bin/sort_data.rb` (or
`ruby bin/sort_data.rb <city>`). The sort exists so a line reorder never shows
whole-file churn in `git diff`.

### Editing data

`data/*.jsonl` is the pipeline's output as much as its input. The **machine
fields** (`yelp_*`, `image_url`, `is_closed`, `transactions`, `region_code`,
`country`, `display_address`) are written by the refresh scripts — hand-writing
them fights a refresh and will be overwritten. Hand-curate only the **hand
fields** (`name`, `neighborhood`, `courses`/`price`, `discount_window`/`discount`, and —
when known — `address`/`website`/`currency`). To add a spot, append one line of
hand fields to the matching `data/<city>.jsonl`, then re-sort (`ruby
bin/sort_data.rb`). Adding `lat`/`lon` up front makes distance sort work
immediately instead of falling back to the city centre; right-click a spot in
Google Maps and the first menu item shows the coordinates.

### Adding a city

1. Create `data/<key>.jsonl`, named after the city key.
2. Add exactly one entry to the `CITIES` table in `bin/cities.rb` with the
   fields known for that city: `location` (Yelp search string), `name` (display
   name), `currency` (ISO code), and `center` (`[lat, lon]`).

Invariant: **every `data/*.jsonl` filename stem must have a `CITIES` entry.**

A city with both `center` and `currency` is *collectable* — `collect_cities.rb`
can add new spots to it. Cities without them (e.g. `nyc`, `singapore`,
`australia`) are *refresh-only*: `refresh_yelp_fields.rb` backfills existing
entries but never adds new ones. `COLLECTABLE_CITIES` is derived from that rule,
not hand-listed. `center` also drives two guards: the 70 km `within_city?`
radius in `collect_cities.rb` (Yelp's `location=` is a region, so spots beyond
70 km are a neighbouring metro and are dropped), and the anchor for the
Foursquare batch searches in `backfill_websites.rb`.

The city's `name` in `bin/cities.rb` is the pipeline's authoritative source of
truth — `catalog-utils.js` reads the same display names and centers through
`CITY_META` (`cityMetaFor(key)`), and the two must agree on `name` and on
`center` to 4 decimal places, enforced by `tests/city_consistency_test.js` (run
it whenever you add or rename a city); do not maintain a second copy here.

### Spot kinds

A spot's kind is derived from its fields by `spotKind()` in `spot-utils.js`,
tested in this precedence order:

1. **`ayce`** (all-you-can-eat) — `isAyceSpot` matches when any of:
   - a `courses` value carries an AYCE token (`ayce` / `tabehoudai` / `食べ放題`);
   - a `name` carries an AYCE token (`ayce` / `allyoucaneat` / `tabehoudai` / `食べ放題`);
   - a `website` host carries an AYCE token (`ayce` / `allyoucaneat` / `buffet` / `tabehoudai` / `食べ放題`).

   Tokens are matched as substrings on a normalized haystack — lowercased, ASCII
   punctuation and whitespace stripped — so `all you can eat`, `all-you-can-eat`,
   and `allyoucaneat` collapse to one token; non-ASCII passes through so the
   `食べ放題` kanji survives. `viking` / `unlimited` are deliberately not tokens:
   `unlimited sake` is a pairing add-on, not AYCE.
2. **`discount`** (happy-hour) — `discount_window` **and** `discount` both present.
3. **`omakase`** — `courses` **and** `price` both present.

AYCE is tested first because an AYCE `courses` value also carries a `price` and
would otherwise classify as omakase. Discount outranks omakase because a
happy-hour window is the actionable, time-bound deal when a spot carries both;
`discount_window`/`discount` and `courses` never co-occur in the current seed, so that
order only pins policy for future data.

`buffet` in a website host counts as AYCE **by default** and is overridden only
by human verification of the individual spot — do not drop it as too weak
without that verification. `collect_cities.rb` mirrors the stance: it deliberately
omits `buffet` from its `REJECT_TERMS`, so a sushi buffet is collected rather
than dropped before the classifier can label it AYCE.

Real examples:

```json
{"name":"Hatsu Omakase","currency":"USD","courses":"AYCE","price":"95","address":"133 E 4th St","neighborhood":"Lower Manhattan"}
{"name":"GENKIYA","discount_window":"8pm","discount":"50%","address":"54 Spring Street","neighborhood":"Nolita"}
{"name":"Aoi Tsuki","currency":"AUD","courses":"20","price":"255","neighborhood":"South Yarra"}
```

## Ruby data pipeline

### Setup (.env)

The `bin/*.rb` scripts read API keys from the environment first, then a
gitignored `.env` (`load_env_key`). Copy the committed template and fill in the
keys:

```bash
cp .env.example .env
# edit .env, then: chmod 600 .env
```

| Variable | Required | Used by |
|----------|----------|---------|
| `YELP_API_KEY` | yes | `collect_cities.rb`, `refresh_yelp_fields.rb` |
| `FOURSQUARE_API_KEY` | no | `backfill_websites.rb` (official-website lookup) |

`.env` is gitignored (`.env.*` too; `.env.example` is the committed template).
Keys are read lazily at request time (`yelp_api_key` / `foursquare_api_key` are
memoized on first use), so the tests never touch the real `.env`. At HEAD the
`FOURSQUARE_API_KEY` is out of quota, so Foursquare-backed lookups fail until
credits are restored — see [External API limits](#external-api-limits).

### Scripts

All 12 `bin/*.rb` files use the hardened `/usr/bin/ruby` shebang that strips
`RUBYOPT`/`GEM_HOME`/etc. from the environment; the seven entry-point scripts
guard `main` with `if __FILE__ == $PROGRAM_NAME` so tests can `require` their
pure functions. `tests/validate_data.rb` uses the same hardened shebang.

#### `collect_cities.rb`

First-time collection for every collectable city (no argument).

- Bulk `term=omakase&categories=sushi`, two pages (`YELP_MAX_PAGES` = 2,
  `YELP_PAGE_SIZE` = 50). The `term` is interchangeable with `sushi` — a direct
  measurement returned identical totals and the same top (all-sushi) results for
  both (`omakase&categories=sushi` vs `sushi&categories=sushi`: Tokyo 11500,
  London 369, Los Angeles 1200), so the deliberate 2-page cap, not the term, is
  the coverage ceiling.
- Hits must pass `relevant_omakase_business?`, stay within the 70 km
  `within_city?` guard, and dedupe via `dedup_key` (exact-name dedup that keeps
  punctuation/spaces — deliberately a different normalization from
  `normalize_name`'s fuzzy match key). A non-sushi buffet still fails the
  positive sushi/omakase/Japanese guard.
- Sleeps unconditionally between processed cities (`INTER_CITY_SLEEP`). Resumes
  via `.fetch-progress`.

#### `refresh_yelp_fields.rb [city]`

Fills missing Yelp fields on existing entries only — never adds spots — driven
by the `YELP_FILL_MAP` field mapping, in two phases:

- **Phase 1 — bulk by `id`/name**: a `term=<t>&location=<city>` search per city
  for each term in `BULK_SEARCH_TERMS` (`omakase` then `sushi`), sharing the
  pending sets so either term reaches a spot, with
  `YELP_BULK_UNPRODUCTIVE_PAGE_LIMIT` and `YELP_SEARCH_MAX_OFFSET` applied per
  term.
- **Phase 2 — exact by name**: matched by `id`, normalized name, a
  normalized-name substring (either name contains the other), or — for a
  pure-CJK title that normalizes to `""` — an exact case/whitespace-folded
  raw-title comparison.

`fill_if_absent!` writes only when absent; `needs_fill?` triggers on
`SEARCH_TRIGGER_FIELDS` (`yelp_url`/`yelp_rating`/`address`/`region_code`/
`display_address`/`yelp_id`, plus `is_closed` by key presence) — not
`image_url`/`phone`, which ~2–6% of spots lack on Yelp itself. Including
`yelp_id` closes a coverage gap (a spot carrying every other core field but no
id is re-searched so the id phase can fill it); the trade-off is extra Yelp API
calls on spots missing only their id.

Discount spots (`discount_window`+`discount`) are skipped. Resumes via
`.yelp-refresh-progress` — only a successful-but-empty search is marked, never a
`nil` failure.

#### `backfill_websites.rb [--dry-run] [city]`

Official-website lookup for spots missing one: a Foursquare batch search per
city, then a per-spot Nominatim fallback.

Hosts matching `BLOCKED_BRANDS`/`BLOCKED_DIRECTORIES` (substring) or
`AGGREGATOR_HOSTS`/`ORDER_PAGE_HOSTS` (exact/suffix) are rejected; a Nominatim
candidate must echo a distinctive name token. Skips the crawl when fewer than
`MIN_MISSING_TO_CRAWL` (20) *untried* spots are missing — each missing spot's
`name|city` key is tested against the tried set, so already-marked keys and
spots that were filled (and are no longer missing) never count; do not compute
it as `missing − done.size`, which double-counts the filled keys.

Resumes via `.website-progress` and `.foursquare-progress`. `--dry-run` still
calls Foursquare/Nominatim (it guards the writes, not the fetches) and prints
the expected call count.

#### `normalize_locations.rb [--dry-run]`

Splits `address` from `neighborhood` (an old `location.address1` used to be
stored there) and drops the legacy `city` field.

Its `STREET_PREFIX_WORDS` list derives its EU portion from `EU_STREET_TYPES`
rather than re-listing it. Re-sorts and rewrites changed files only; `--dry-run`
prints per-city counts and is genuinely offline (no provider calls). Idempotent.

#### `geocode_fallback.rb [--dry-run]`

Re-geocodes coarse placeholder coordinate groups (2+ spots sharing a ≤4-decimal
point) via Nominatim.

The query uses `nominatim_city_query`, which prefers the `CITIES` `name`
(display name) and falls back to the Yelp `location` string — deliberately NOT
the JS `cityLabelFor` display name, so the two must not be unified. Points
farther than `MAX_CENTER_KM` (250 km) from the city centre are reported, never
guessed. Resumes via `.geocode-progress`. `--dry-run` still calls Nominatim
(writes only are guarded) and prints the expected call count.

#### `reverse_geocode_addresses.rb [--validate] [--dry-run] [city]`

Fills missing `address` fields by reverse geocoding coordinates via Nominatim
(Yelp 403s from some networks, so a Yelp refresh cannot).

`--validate` samples ~25 known-good spots and reports the match rate — the gate
before filling. Only empty addresses are filled; coarse city-centre placeholder
coordinates and points > 250 km from the centre are skipped. The missing-address
set is already tight — the 67 spots missing an address at HEAD collapse to 2
real Nominatim calls, because 64 carry coarse/placeholder coordinates that are
skipped, 1 carries a precise coordinate implausibly far from its city centre
(> 250 km, skipped), and the remaining 2 eligible spots issue the 2 calls.

Resumes via `.reverse-geocode-progress`. `--dry-run` still calls Nominatim
(writes only are guarded) and prints the expected call count.

#### `sort_data.rb [city…]`

Re-sorts `data/*.jsonl` by `entry_sort_key`; rewrites only files whose order
changed. Idempotent.

Every CLI parses its flags through `parse_common_flags(argv, supported:)`; only
`reverse_geocode_addresses.rb` honours `--validate`, and the other six reject it
with `Unknown option: --validate` (exit 1). Per-spot progress lines share one
shape everywhere — a bare `name (city key)` prefix.

Long-running scripts resume from gitignored progress files (`.fetch-progress`,
`.website-progress`, `.foursquare-progress`, `.geocode-progress`,
`.reverse-geocode-progress`, `.yelp-refresh-progress`), which exist so a resumed
run does not re-pay for API calls it already made. Each file's key shape is
deliberately per-script, not shared: `collect_cities.rb` keys a bare city key;
`backfill_websites.rb` keys `name|city`; `geocode_fallback.rb` and
`reverse_geocode_addresses.rb` share the `geocode_progress_key` formatter
(`city|name|lat,lon`) so the two cannot drift; `refresh_yelp_fields.rb` keys
`name|city_key`. The shapes are deliberately not normalized to one another —
collapsing them would discard a file's resume state and re-trigger paid calls.
Without a `YELP_API_KEY`, `collect_cities.rb` and `refresh_yelp_fields.rb` fail
— the key is required.

### Support modules

Support modules (no `main`; required by the scripts above):

- `pipeline_common.rb` — the require hub, pulling in `cities.rb`, `jsonl.rb`,
  and `yelp_client.rb`, plus small shared helpers (paths, `load_env_key`,
  `fill_if_absent!`, `fill_yelp_fields!`/`YELP_FILL_MAP`, `canonical_yelp_url`,
  `haversine_km`, `MAX_CENTER_KM`, `coarse_coord?`, `rounded_coordinates`,
  `entry_sort_key`/`sort_entries!`, `geocode_progress_key`, `build_failure_guard`,
  `guard_result`, `warn_unresolvable_city`, `defer_sleep`,
  `print_dry_run_estimate` (and the shared `print_distinct_units_estimate` dry-run
  pre-count, `print_run_summary(state, file_count, dry_run:, labels:)`
  Filled/Skipped/Missed/Errored/Changed printer, and `DRY_RUN_SUFFIX`),
  the street-token lists) and the shared
  `ConsecutiveFailureGuard` / `MAX_CONSECUTIVE_FAILURES` abort-after-N guard,
  plus the shared CLI flag parser (`parse_common_flags`/`CommonFlags`) whose
  `CommonFlags` struct now carries `:positionals` (the full positional list) so
  `sort_data.rb` reads `flags.positionals` instead of the mutated global `ARGV`.
  The per-file `defined?`-guarded copies in `backfill_websites.rb` /
  `reverse_geocode_addresses.rb` are gone — that guard let whichever file
  loaded first win.
- `cities.rb` — the single `CITIES` table (each key carrying `location`,
  `name`, `currency`, `center`) plus `collectable?` and `COLLECTABLE_CITIES`.
- `jsonl.rb` — JSONL/progress IO: `load_progress`, `append_progress`,
  `load_jsonl` (skips malformed lines), `select_city_files`, `data_filenames` /
  `data_paths`, atomic `write_atomic`/`persist_then_mark` (persist-before-mark),
  `normalize_name`/`normalized_name_or_nil`, `city_key_for`.
- `yelp_client.rb` — the Yelp Fusion client: persistent per-host connections
  (`http_client`/`drop_http_client`, `HTTP_TIMEOUT`),
  `retry_wait`/`http_request` backoff, `search_yelp` (up to `YELP_MAX_ATTEMPTS`
  total attempts — 3, i.e. one initial call plus 2 retries — over `yelp_search_once` that retries only a 429 — honouring
  `Retry-After` — or a transport error, raises the typed `LocationNotFound` when
  the body's `error.code` is `LOCATION_NOT_FOUND` (parsed defensively, so a
  non-JSON/absent body cannot raise its own error), and fails fast on any other
  HTTP status or a parse failure), streaming `read_capped_body` (caps body
  at `MAX_BODY_BYTES`), and the shared `YELP_PAGE_SIZE` / `YELP_SLEEP` (1.1 s —
  the load-bearing pace below Yelp's throttle). `HTTP_TRANSPORT_ERRORS` is the
  set an adapter rescues as "no result"; its deliberately broad
  `SystemCallError` membership is documented in the file.
- `website_sources.rb` — the official-website/geocoding adapters (Nominatim +
  Foursquare: `nominatim_search`/`nominatim_reverse`, `foursquare_batch`) with
  shared host-cleaning/filtering (`clean_host`, `BLOCKED_BRANDS` /
  `BLOCKED_DIRECTORIES` for substring rejects, `AGGREGATOR_HOSTS` /
  `ORDER_PAGE_HOSTS` for exact/suffix rejects) and the shared
  `PROVIDER_ERRORS` rescue set, loaded through `backfill_websites.rb`,
  `geocode_fallback.rb`, and `reverse_geocode_addresses.rb` (not
  `pipeline_common.rb`).

The provider adapters follow a **hard-failure vs success-but-empty contract**:
`nil` means a hard failure (transport/parse error, non-2xx, missing API key) and
must never be recorded as a permanent "tried"; an empty `[]`/`{}` means the
request succeeded and genuinely found nothing. Callers rely on the distinction —
do not collapse `nil` into an empty value.

### CJK name-normalization guard

**Never collapse CJK names to an empty token.** `normalize_name` strips
non-ASCII, so a purely-CJK name (`くら寿司福岡飯倉店`) normalizes to `""`.
`backfill_websites.rb` skips such names on purpose — matching on an empty key
would assign one host to *every* CJK spot in a city. `refresh_yelp_fields.rb`
instead reaches them by an exact `yelp_id` match or an exact case/whitespace-
folded raw-title comparison, never by an empty normalized key. Preserve that
guard when touching any name-normalizing helper.

### External API limits

- **Yelp Fusion returns HTTP 403 from some networks** — Yelp's CDN blocks the
  egress IP, not a bad key. The Yelp-dependent pipeline therefore **cannot
  always run**; if `refresh_yelp_fields.rb` fails this way, retry from another
  network or a VPN. This is environment-specific, not a repo limitation.
- **Nominatim** (OpenStreetMap) is free and keyless but rate-limited to about
  one request per second; the scripts send a `User-Agent` and sleep ~1.2 s
  between requests (`NOMINATIM_SLEEP`).
- **Foursquare** is optional and keyed; its batch search caps at
  `FOURSQUARE_PAGE_SIZE` × `FOURSQUARE_MAX_PAGES` (200) results per city, and
  follows the [nil-vs-empty contract](#support-modules). The key at HEAD returns
  429 ("no API credits remaining … exceeded your freePro tier limit"), so
  `backfill_websites`' Foursquare Phase 1 cannot run until credits are restored —
  the per-spot Nominatim fallback is the only working path. A quota state, not a
  code fault.
- **Yelp has no coverage for some cities.** A `location=` string Yelp cannot
  resolve fails *every* search in that city — including the bare city name —
  with HTTP 400 `LOCATION_NOT_FOUND` (the strings are correct; Yelp simply lacks
  the coverage). `bin/yelp_client.rb` raises the typed `LocationNotFound`, and
  `refresh_yelp_fields.rb` / `collect_cities.rb` catch it per city: warn once,
  skip that city's remaining searches, and do **not** feed the
  consecutive-failure guard — an unsearchable city is not a dead key/network.
  Before this, eight such failures tripped `Abort: 8 consecutive failed
  searches` and killed a 13-minute run after 29 of 65 cities. Confirmed affected
  at HEAD: `seoul`, `bangkok`, `shanghai`, `dubai` (still 0% filled after a full
  run), and `australia` (2 of its 12 entries already carry Yelp fields, so it
  cannot be newly enriched). A `latitude`/`longitude`+`radius` request returns
  200 with zero businesses, so these cities cannot be enriched from Yelp at all.

## Verifying your change

Run the full check set before opening a PR:

```bash
omarchy plugin validate .
node tests/spot_utils_test.js
node tests/catalog_sort_test.js
node tests/catalog_search_test.js
node tests/catalog_format_test.js
node tests/catalog_data_test.js
node tests/city_consistency_test.js
node tests/journal_identity_test.js
ruby tests/validate_data.rb
ruby tests/pipeline_common_test.rb
ruby tests/refresh_yelp_fields_test.rb
ruby tests/collect_cities_test.rb
ruby tests/normalize_locations_test.rb
ruby tests/backfill_websites_test.rb
ruby tests/geocode_fallback_test.rb
ruby tests/reverse_geocode_addresses_test.rb
ruby bin/sort_data.rb
for f in bin/*.rb; do ruby -c "$f"; done
```

All seven Ruby suites require `tests/test_helper.rb`, which holds the shared
persist-before-mark probe (`capture_progress_marker_at_write`), the no-op
sleeper, the shared Yelp fixture, and `assert_marking_contract` — the
nil-vs-empty marking-contract assertion helper the orchestration suites share.

Expected results at HEAD — verified by running each:

| Command | Covers | Expected |
|---------|--------|----------|
| `omarchy plugin validate .` | Manifest schema + safe entry points that exist | exit 0 (silent) |
| `node tests/spot_utils_test.js` | `spot-utils.js` formatters/geography | 276 pass |
| `node tests/catalog_sort_test.js` | `catalog-utils.js` sort/spec/price | 113 pass |
| `node tests/catalog_search_test.js` | `catalog-utils.js` search (fold/rank/scoped index) | 89 pass |
| `node tests/catalog_format_test.js` | `catalog-utils.js` labels/empty-state/formatting | 108 pass |
| `node tests/catalog_data_test.js` | `catalog-utils.js` data literals (`CITY_META`/`US_STATES`) + export guard | 134 pass |
| `node tests/city_consistency_test.js` | `CITY_META` ↔ `CITIES` agreement + data stems in `CITIES` | 128 pass |
| `node tests/journal_identity_test.js` | `journal-identity.js` alias canonicalization + journal dedupe + user-spot merge + wishlist normalization | 57 pass |
| JS suites total | — | 905 pass |
| `ruby tests/validate_data.rb` | Every `data/*.jsonl` line parses as a JSON object (parseability only — no field-name/type checking) | all valid — spot count under Data files |
| `ruby tests/pipeline_common_test.rb` | Shared `bin/` helpers | 86 runs / 198 assertions |
| `ruby tests/refresh_yelp_fields_test.rb` | `refresh_yelp_fields.rb` merge/fill + orchestration + resume | 20 runs / 83 assertions |
| `ruby tests/collect_cities_test.rb` | `collect_cities.rb` relevance/dedup + orchestration | 21 runs / 69 assertions |
| `ruby tests/normalize_locations_test.rb` | `normalize_locations.rb` `address_like?` + `normalize_entry` | 11 runs / 32 assertions |
| `ruby tests/backfill_websites_test.rb` | `backfill_websites.rb` + `website_sources.rb` | 21 runs / 60 assertions |
| `ruby tests/geocode_fallback_test.rb` | `geocode_fallback.rb` coarse-coord + orchestration | 9 runs / 23 assertions |
| `ruby tests/reverse_geocode_addresses_test.rb` | `reverse_geocode_addresses.rb` address derivation + orchestration | 20 runs / 35 assertions |
| Ruby suites total | — | 188 runs / 500 assertions |
| `ruby bin/sort_data.rb` | On-disk sort order | `Changed 0 of 65 files` |
| `for f in bin/*.rb; do ruby -c "$f"; done` | Ruby syntax | 12 files `Syntax OK` |

`ruby -c bin/*.rb` alone checks only the
first file, hence the loop above.

`qmllint` is unreliable in this shell: `qmllint .` exits 255 with empty output,
and per-file runs (`qmllint Service.qml`) exit 0 with empty output, so it proves
nothing either way. For runtime QML errors, read the shell log at
`$XDG_RUNTIME_DIR/quickshell/by-id/<instance>/log.log`.

### QML verification on Qt 6

A probe that must match the shell's runtime has to use
`/usr/lib/qt6/bin/qmltestrunner` (with the test files in their own `-input`
directory), never `/usr/bin/qml`, which is Qt 5.15 on this machine. The
verified list of unavailable/available JS APIs lives in `AGENTS.md`.

## Install / reload

The running shell always loads the installed copy at
`~/.config/omarchy/plugins/omakase/`, never this working tree, and needs a
restart after any plugin change. Two install topologies exist:

- **A real install** — `omarchy plugin add <git-url>` (the installer
  `/usr/share/omarchy/bin/omarchy-plugin-add`) does a full `git clone` and moves
  the clone into `~/.config/omarchy/plugins/omakase/`. The installed checkout
  holds the whole repository tree: `bin/`, `tests/`, the docs, `LICENSE`,
  `.gitignore`, and `.env.example` are present but inert, since the shell loads
  only the manifest's `entryPoints` and what they import (`components/`,
  `data/`, `icons/`, the shared JS). Only untracked files are absent from a
  clone, which is why `AGENTS.md` and `.env` (both gitignored) are not shipped.
  `omarchy plugin update omakase` updates such an install in place (`git fetch`
  + `merge --ff-only`).
- **This machine's hand-synced copy** — `~/.config/omarchy/plugins/omakase/`
  here holds only the runtime files (`Service.qml`, `BarWidget.qml`,
  `spot-utils.js`, `catalog-utils.js`, `components/`, `data/`, `icons/`,
  `manifest.json`) and is not a git repo, so `omarchy plugin update` has nothing
  to pull from; a local edit has to be copied into the installed directory
  manually.

After changing a plugin file, sync the changed runtime files into the installed
directory — commit and run `omarchy plugin update omakase`, or copy the files
directly — then restart the shell, never relying on hot-reload:

```bash
omarchy-restart-shell
```

which kills the running shell and relaunches it via Hyprland so it inherits the
session environment. In practice it often leaves no shell running; relaunch
explicitly:

```bash
hyprctl dispatch 'hl.dsp.exec_cmd("omarchy-launch-shell")'
```

**Data changes need no restart.** `omarchy-shell omakase refresh` returns `ok`
and restarts the seed loader, which re-parses `data/*.jsonl` and calls
`writeState()` — so `state.json` **is** rewritten (its always-changing
`updatedAt` defeats `FileView.setText`'s unchanged-content skip), and the bar
widget's `watchChanges` FileView reloads the catalog. The "`state.json` is only
rewritten when home moves" rule governs the **normal restart** path, where the
seed loader is deliberately not started (see `AGENTS.md`); `refresh` is the
explicit exception. A `data/*.jsonl` edit therefore reaches the widget through
`refresh` alone — no need to delete `state.json` or restart the shell.
