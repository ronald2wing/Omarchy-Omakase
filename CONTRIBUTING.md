# Contributing to Omakase

Contributions cover the data (`data/*.jsonl`), the Ruby pipeline (`bin/`), and
the QML/JavaScript plugin itself. Pull requests target `main`.

## Repository layout

| Path | Purpose |
|------|---------|
| `data/` | Seed directory — one `<city>.jsonl` file per city, one spot per line. |
| `bin/` | Ruby data pipeline that collects and refreshes Yelp fields and websites. |
| `tests/` | Unit tests and the data validator. |
| `components/` | Panel pieces (SpotCard, FilterBar/Panel/Sheet, TabChips, ChunkedWalk, …). |
| `icons/` | SVG icon assets for the panel UI. |
| `Service.qml` | Headless `service` kind: loads seed data, owns state and IPC. |
| `BarWidget.qml` | `bar-widget` kind: the panel UI, driven by the state files. |
| `spot-utils.js` | Shared formatters/geography (Node + QML dual-use). |
| `catalog-utils.js` | Pure catalog helpers — sorting, search, aggregation, display names (Node + QML dual-use). |
| `manifest.json` | Manifest (id, version, kinds, entry points). |
| `preview.png` | Root preview image the marketplace shows on the listing (auto-optimized by the marketplace). |

## Data files

Restaurant data lives in `data/<city>.jsonl` — one JSON object per line, no
pretty-printing. The filename stem (without `.jsonl`) is the city key
(lowercase, hyphenated for multi-word keys: `nyc`, `san-francisco`). A spot has
no `city` field of its own; the file stem is the canonical city key.

`australia.jsonl` is the one country-level key — it holds spots across
Australia under a single file.

## Adding a restaurant

Add one line to the matching `data/<city>.jsonl`, then run
`ruby bin/sort_data.rb` (or `ruby bin/sort_data.rb <city>`) to place it in
sorted order. Files are kept sorted by `name` (case-insensitive, ties broken by
`lat`/`lon`) so a line reorder never shows whole-file churn in `git diff`.
`collect_cities.rb` sorts automatically; only a hand edit needs the explicit
sort.

An omakase spot:

```json
{"name":"SUSHI NOZ ASH & HINOKI","currency":"USD","courses":"20","price":"550","address":"161 E 82nd St","neighborhood":"Upper East Side"}
```

A discount spot (happy-hour deal) uses `time` + `discount` instead:

```json
{"name":"HASHI MARKET","time":"8pm","discount":"50%","address":"45 2nd Ave","neighborhood":"East Village"}
```

## Field reference

This table is the authoritative field reference. "Machine" means a pipeline
script writes it — do not hand-write those.

| Field | Required | Source | Notes |
|-------|----------|--------|-------|
| `name` | yes | hand | Restaurant name. The only strictly required field — the seed loader skips entries without it. |
| `lat` / `lon` | no | hand / machine | Coordinates. Refresh-filled when missing; drive distance sort and the Maps fallback link. |
| `address` | no | hand / machine | Street address, e.g. `"161 E 82nd St"`. `normalize_locations.rb` derives it from `display_address[0]` (or an address-like `neighborhood`) when Yelp's `address1` was stored elsewhere. Refresh-filled when missing. |
| `neighborhood` | no | hand | Real sub-area name only, e.g. `"Brooklyn"`. Never a street address — an absent field means no distinct sub-area. Hand-curated; the pipeline does not write it. |
| `website` | no | hand / machine | Official site URL. `backfill_websites.rb` fills it when missing. |
| `phone` | no | hand / machine | Phone number. Refresh-filled when missing. |
| `currency` | no | hand | ISO code (`USD`, `JPY`, …). The UI derives the price symbol from it. Set by `collect_cities.rb`. |
| `courses` | omakase | hand | Number of courses, e.g. `"20"`. |
| `price` | omakase | hand | The spot's menu price: a bare number, no symbol or separators, e.g. `"550"`. |
| `time` | discount | hand | Discount window, e.g. `"8pm"`. |
| `discount` | discount | hand | e.g. `"50%"`. |
| `yelp_id` | no | machine | Yelp identity, used by the refresh scripts to match entries. Pipeline-only — `Service.persistedSpotFields` drops it, so it never reaches `state.json` or the UI. |
| `yelp_url` | no | machine | Yelp link. |
| `yelp_rating` | no | machine | Yelp rating (0–5). |
| `yelp_review_count` | no | machine | Yelp review count. |
| `yelp_price` | no | machine | Yelp's `$$` bucket — not the spot's `price`. |
| `image_url` | no | machine | Yelp header image. |
| `is_closed` | no | machine | Yelp's permanently-closed flag. |
| `transactions` | no | machine | Yelp transaction types (e.g. `restaurant_reservation`). |
| `state` | no | machine | Yelp location `state` — a region code, not always a US state. |
| `country` | no | machine | Yelp location `country`. |
| `display_address` | no | machine | Yelp's formatted address array. |

A spot's kind is derived from its fields: `courses` + `price` for omakase,
`time` + `discount` for discount. Adding `lat`/`lon` up front makes distance
sort work immediately instead of falling back to the city center.

## Coordinates

Right-click the spot in Google Maps — the first menu item shows the lat/lon.
Paste as `"lat": 40.7738, "lon": -73.9581`.

## Cities

The 65 city keys are the `data/*.jsonl` filename stems. Each has an entry in
`bin/cities.rb` carrying the Yelp search `location`; collectable cities also
carry a `currency` and a `center`.

| Key | Location | Currency | Collectable |
|-----|----------|----------|-------------|
| `amsterdam` | Amsterdam, Netherlands | EUR | yes |
| `atlanta` | Atlanta, GA, USA | USD | yes |
| `auckland` | Auckland, New Zealand | NZD | yes |
| `austin` | Austin, TX, USA | USD | yes |
| `australia` | Sydney, Australia | – | no |
| `bangkok` | Bangkok, Thailand | – | no |
| `barcelona` | Barcelona, Spain | EUR | yes |
| `berlin` | Berlin, Germany | EUR | yes |
| `boston` | Boston, MA, USA | USD | yes |
| `brisbane` | Brisbane, QLD, Australia | AUD | yes |
| `brussels` | Brussels, Belgium | EUR | yes |
| `buenos-aires` | Buenos Aires, Argentina | – | no |
| `chicago` | Chicago, IL, USA | USD | yes |
| `copenhagen` | Copenhagen, Denmark | DKK | yes |
| `dallas` | Dallas, TX, USA | USD | yes |
| `denver` | Denver, CO, USA | USD | yes |
| `dubai` | Dubai, UAE | – | no |
| `dublin` | Dublin, Ireland | EUR | yes |
| `fukuoka` | Fukuoka, Japan | JPY | yes |
| `hong-kong` | Hong Kong | – | no |
| `houston` | Houston, TX, USA | USD | yes |
| `kyoto` | Kyoto, Japan | JPY | yes |
| `las-vegas` | Las Vegas, NV, USA | USD | yes |
| `lisbon` | Lisbon, Portugal | EUR | yes |
| `london` | London, UK | GBP | yes |
| `los-angeles` | Los Angeles, CA, USA | USD | yes |
| `madrid` | Madrid, Spain | EUR | yes |
| `manila` | Manila, Philippines | – | no |
| `melbourne` | Melbourne, VIC, Australia | AUD | yes |
| `mexico-city` | Mexico City, Mexico | – | no |
| `miami` | Miami, FL, USA | USD | yes |
| `milan` | Milan, Italy | EUR | yes |
| `minneapolis` | Minneapolis, MN, USA | USD | yes |
| `montreal` | Montreal, QC, Canada | CAD | yes |
| `munich` | Munich, Germany | EUR | yes |
| `nagoya` | Nagoya, Japan | JPY | yes |
| `nashville` | Nashville, TN, USA | USD | yes |
| `nyc` | New York, NY | – | no |
| `osaka` | Osaka, Japan | JPY | yes |
| `paris` | Paris, France | EUR | yes |
| `perth` | Perth, WA, Australia | AUD | yes |
| `philadelphia` | Philadelphia, PA, USA | USD | yes |
| `phoenix` | Phoenix, AZ, USA | USD | yes |
| `portland` | Portland, OR, USA | USD | yes |
| `prague` | Prague, Czech Republic | CZK | yes |
| `rome` | Rome, Italy | EUR | yes |
| `san-antonio` | San Antonio, TX, USA | USD | yes |
| `san-diego` | San Diego, CA, USA | USD | yes |
| `san-francisco` | San Francisco, CA, USA | USD | yes |
| `san-jose` | San Jose, CA, USA | USD | yes |
| `sao-paulo` | São Paulo, Brazil | – | no |
| `sapporo` | Sapporo, Japan | JPY | yes |
| `seattle` | Seattle, WA, USA | USD | yes |
| `seoul` | Seoul, South Korea | KRW | yes |
| `shanghai` | Shanghai, China | – | no |
| `singapore` | Singapore | – | no |
| `stockholm` | Stockholm, Sweden | SEK | yes |
| `sydney` | Sydney, NSW, Australia | AUD | yes |
| `taipei` | Taipei, Taiwan | – | no |
| `tokyo` | Tokyo, Japan | JPY | yes |
| `toronto` | Toronto, ON, Canada | CAD | yes |
| `vancouver` | Vancouver, BC, Canada | CAD | yes |
| `vienna` | Vienna, Austria | EUR | yes |
| `washington-dc` | Washington, DC, USA | USD | yes |
| `zurich` | Zurich, Switzerland | CHF | yes |

## Adding a city

1. Create `data/<key>.jsonl`, named after the city key.
2. Add exactly one entry to the `CITIES` table in `bin/cities.rb` with the
   fields known for that city: `location` (Yelp search string), `name`
   (display name), `currency` (ISO code), and `center` (`[lat, lon]`).

Invariant: **every `data/*.jsonl` filename stem must have a `CITIES` entry.**

A city with both `center` and `currency` is *collectable* — `collect_cities.rb`
can add new spots to it. Cities without them (for example `nyc` and
`singapore`) are *refresh-only*: `refresh_yelp_fields.rb` backfills existing
entries but never adds new ones. `COLLECTABLE_CITIES` is derived from that
rule, not hand-listed.

`center` also drives behavior: it is the reference point for the 70 km
`within_city?` guard in `collect_cities.rb` (Yelp's `location=` is a region, so
spots beyond 70 km are a neighbouring metro and are dropped) and the anchor for
the Foursquare batch searches in `backfill_websites.rb`.

The city's `name` in `bin/cities.rb` is the pipeline's source of truth.
`catalog-utils.js` carries the same display names and center coordinates for
the known cities in `CITY_META` (read through the `cityMetaFor(key)` accessor).
This is a known duplication of `CITIES`; the two tables must agree on `name`
and on `center` to 4 decimal places. `tests/city_consistency_test.js` enforces
that agreement — run it whenever you add or rename a city.

## Ruby data pipeline

The `bin/*.rb` scripts read API keys from a gitignored `.env`. Copy the
committed template and fill in the keys:

```bash
cp .env.example .env
# edit .env and set YELP_API_KEY (required) and FOURSQUARE_API_KEY (optional)
```

See `.env.example` for the key names and the Yelp/Foursquare developer links.

| Script | Purpose |
|--------|---------|
| `collect_cities.rb` | First-time collection for every collectable city (no argument). Bulk `term=omakase&categories=sushi`, two pages (100 max); hits must pass `relevant_omakase_business?`, deduped via `dedup_key`. Resumes via `.fetch-progress`. |
| `refresh_yelp_fields.rb [city]` | Fills missing Yelp fields on existing entries only — never adds spots. Two-phase (bulk by `id`, then per-name exact); `fill_if_absent!` writes only when absent, and `needs_fill` requires only the fields Yelp reliably returns (`yelp_url`/`yelp_rating`/`is_closed`/`address`/`state`/`display_address`) — not `image_url`/`phone`, which ~2-6% of spots lack on Yelp itself. |
| `backfill_websites.rb [--dry-run] [city]` | Official-website lookup via Nominatim, then Foursquare batch searches. Hosts matching `BLOCKED_FRAGMENTS` (substring) or `AGGREGATOR_HOSTS` (exact/suffix) are rejected. Skips the crawl when fewer than `MIN_MISSING_TO_CRAWL` (20) spots are missing. Resumes via `.website-progress`. |
| `normalize_locations.rb [--dry-run]` | Splits `address` from `neighborhood` (`location.address1` used to be stored there) and drops the legacy `city` field. Re-sorts and rewrites changed files only; `--dry-run` prints per-city counts. Idempotent. |
| `geocode_fallback.rb [--dry-run]` | Re-geocodes coarse placeholder coordinate groups (2+ spots sharing a ≤4-decimal point) via Nominatim. Points too far from the city center are reported, never guessed. |
| `sort_data.rb [city…]` | Re-sorts `data/*.jsonl` by name (`entry_sort_key`); rewrites only files whose order changed. Idempotent. |

Support files:

- `pipeline_common.rb` — the require hub, pulling in `cities.rb`, `jsonl.rb`,
  and `yelp_client.rb`, plus small shared helpers (paths, `load_env_key`,
  `canonical_yelp_url`, `haversine_km`, `entry_sort_key`/`sort_entries!`).
- `cities.rb` — the single `CITIES` table plus `collectable?` and
  `COLLECTABLE_CITIES`.
- `jsonl.rb` — JSONL/progress IO (`load_progress`, `load_jsonl` — which skips
  malformed lines — `select_city_files`, atomic `write_atomic`,
  `normalize_name`).
- `yelp_client.rb` — the Yelp Fusion client: persistent per-host connections,
  `retry_wait`/`http_request` backoff, `search_yelp` (a retry loop over
  `yelp_search_once`), streaming `read_capped_body` (caps body at
  `MAX_BODY_BYTES`). The key is read lazily at request time, so tests never
  touch the real `.env`.
- `website_sources.rb` — the official-website adapters (Nominatim +
  Foursquare) with shared host-cleaning/filtering (`BLOCKED_FRAGMENTS`/
  `AGGREGATOR_HOSTS`), loaded through `backfill_websites.rb` and
  `geocode_fallback.rb` (not `pipeline_common.rb`).

Long-running scripts resume from gitignored progress files (`.fetch-progress`,
`.website-progress`). Without a populated `.env`, `collect_cities.rb` and
`refresh_yelp_fields.rb` fail: the Yelp key is required.

### External API limits

- **Yelp Fusion** has returned HTTP 403 from this machine's network — Yelp's CDN
  blocking the egress IP, not a bad key. This is environment- and time-specific,
  not a repo limitation; if `refresh_yelp_fields.rb` fails this way, retry from
  another network or a VPN.
- **Foursquare** free tier is 500 Pro calls/month.
- **Nominatim** (OpenStreetMap) is free and keyless but rate-limited to about
  one request per second; the scripts send a `User-Agent` and sleep ~1.2 s
  between requests.
- Current coverage: 3,028 of 5,016 spots have a `website`.

## Verifying your change

Run the full check set before opening a PR:

```bash
omarchy plugin validate .
node tests/spot_utils_test.js
node tests/catalog_utils_test.js
node tests/city_consistency_test.js
ruby tests/validate_data.rb
ruby tests/pipeline_common_test.rb
ruby tests/bin_pipeline_test.rb
ruby bin/sort_data.rb
for f in bin/*.rb; do ruby -c "$f"; done
```

Expected results at HEAD:

| Command | Covers | Expected |
|---------|--------|----------|
| `omarchy plugin validate .` | Manifest + entry points | exit 0 |
| `node tests/spot_utils_test.js` | `spot-utils.js` formatters/geography | 195 pass |
| `node tests/catalog_utils_test.js` | `catalog-utils.js` pure catalog logic | 269 pass |
| `node tests/city_consistency_test.js` | `CITY_META` ↔ `CITIES` agreement | 127 pass |
| `ruby tests/validate_data.rb` | Every `data/*.jsonl` line parses | 5016 entries valid |
| `ruby tests/pipeline_common_test.rb` | Shared `bin/` helpers | 44 runs / 84 assertions |
| `ruby tests/bin_pipeline_test.rb` | Pipeline scripts — pure functions + off-network orchestration | 47 runs / 130 assertions |
| `ruby bin/sort_data.rb` | On-disk sort order | Changed 0 of 65 files |
| `for f in bin/*.rb; do ruby -c "$f"; done` | Ruby syntax | 11 files Syntax OK |

`ruby -c bin/*.rb` alone checks only the first file — loop over the files.

`qmllint` is unreliable in this shell (historically exit 255 with empty
output). For runtime QML errors, read the shell log at
`$XDG_RUNTIME_DIR/quickshell/by-id/<instance>/log.log`.

The shell loads the installed copy at `~/.config/omarchy/plugins/omakase/`, not
this working directory. `omarchy plugin add <git-url>` performs a full `git
clone` and moves the entire checkout into that directory, and `omarchy plugin
update omakase` fast-forwards it — so the installed checkout contains the whole
repository: `bin/`, `tests/`, the docs, `LICENSE`, `.gitignore`, and
`.env.example` are present but inert, since only the manifest's `entryPoints`
are ever loaded. Only untracked files are absent, which is why `AGENTS.md` is
gitignored. This working directory is the source of truth; after editing here,
copy the changed runtime files into the installed directory (or commit and run
`omarchy plugin update`), then reload with `omarchy-restart-shell`, which kills
the old shell and relaunches it from Hyprland detached from the invoking
terminal, so the new shell inherits the canonical session environment rather
than transient terminal/SSH/dev-tool variables. If the reload leaves no shell
running, relaunch with
`hyprctl dispatch 'hl.dsp.exec_cmd("omarchy-launch-shell")'`.

## Submitting a PR

Create a branch, commit your change, and open a pull request against `main`.
Keep one spot per line and field names lowercase; values are strings unless
noted. Nerd-font glyphs are fine in UI strings and data values — keep them out of
comments.
