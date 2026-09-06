# Contributing to Omakase

Thanks for helping build the worldwide omakase directory and sushi-spot
tracker. Contributions cover
the data (`data/*.jsonl`), the Ruby pipeline (`bin/`), and the QML/JavaScript
plugin itself. Pull requests target `main`.

## Repository layout

| Path | Purpose |
|------|---------|
| `data/` | Seed directory — one `<city>.jsonl` file per city, one spot per line. |
| `bin/` | Ruby data pipeline that collects and refreshes Yelp fields and websites. |
| `tests/` | Unit tests and the data validator. |
| `Service.qml` | Headless `service` kind: loads seed data, owns state and IPC. |
| `BarWidget.qml` | `bar-widget` kind: the panel UI, driven by the state files. |
| `spot-utils.js` | Shared formatters/geography, used by Node tests and QML. |
| `catalog-utils.js` | Pure catalog helpers (`coordKey`, `decoratedSort`, `aggregateList`, `applySearchFilter`, …), used by Node tests and QML. |

## Data files

Restaurant data lives in `data/<city>.jsonl` — one city per file, one JSON
object per line, no pretty-printing. The filename stem (without `.jsonl`) is the
city key (lowercase, hyphenated for multi-word keys: `nyc`, `san-francisco`).

`australia.jsonl` is the one exception: its key is a country, not a city, and it
holds spots across Australia under a single file.

## Adding a restaurant

Add one line to the matching `data/<city>.jsonl`, then run `ruby bin/sort_data.rb`
(or `ruby bin/sort_data.rb <city>`) to place it in sorted order. Files are kept
**sorted by `name`** (case-insensitive, ties broken by `lat`/`lon`) so a line
reorder never shows whole-file churn in `git diff`. The pipeline
(`collect_city.rb`) sorts automatically; only a hand edit needs the explicit
sort. Canonical omakase spot:

```json
{"name":"SUSHI NOZ ASH & HINOKI","currency":"USD","courses":"20","price":"550","neighborhood":"Upper East Side"}
```

A discount spot (happy-hour deal) uses `time` + `discount` instead:

```json
{"name":"HASHI MARKET","time":"8pm","discount":"50%","neighborhood":"Upper East Side"}
```

## Field reference

This table is the single source of truth for fields. "Machine-filled" means a
pipeline script writes it — do not hand-write those.

| Field | Required | Source | Notes |
|-------|----------|--------|-------|
| `name` | yes | hand | Restaurant name. |
| `currency` | no | hand | ISO code (`USD`, `JPY`, …). The UI derives the price symbol from it. Set automatically by `collect_city.rb`. |
| `courses` | omakase | hand | Number of courses, e.g. `"20"`. |
| `price` | omakase | hand | The spot's own menu price: a bare number, no symbol or separators, e.g. `"550"`. The UI adds the currency symbol. |
| `time` | discount | hand | Discount window, e.g. `"8pm"`. |
| `discount` | discount | hand | e.g. `"50%"`. |
| `lat` / `lon` | no | hand | Coordinates (see below). Refresh-filled when missing. The Maps link is derived from these (or `display_address`) via `SpotUtils.mapsUrl()`. |
| `website` | no | hand | Official site URL. `backfill_websites.rb` fills it when missing. |
| `phone` | no | hand | Phone number. Refresh-filled when missing. |
| `neighborhood` | no | hand | Area/street label. Refresh-filled when missing (Yelp `address1`). |
| `source` | no | machine | Provenance marker (`"yelp"`) written by `collect_city.rb`. No code filters on it, and `persistedSpotFields` drops it, so it never reaches `state.json` or the UI. |
| `yelp_id` | no | machine | Yelp identity, used by the refresh scripts to match entries. Pipeline-only — `persistedSpotFields` drops it, so it is not surfaced in `state.json` or the UI. |
| `yelp_url` | no | machine | Yelp link. |
| `yelp_rating`, `yelp_review_count` | no | machine | Yelp rating (0–5) and review count. |
| `yelp_price` | no | machine | Yelp's own `$$` bucket — **not** the spot's `price`. |
| `image_url` | no | machine | Yelp header image. |
| `is_closed` | no | machine | Yelp's permanently-closed flag. |
| `transactions` | no | machine | Yelp transaction types (e.g. `restaurant_reservation`). |
| `city`, `state`, `country` | no | machine | Yelp location fields; `state` is a region code. |
| `display_address` | no | machine | Yelp's formatted address array. |

Only `name` is strictly required. A spot's kind is derived from its fields —
`courses`+`price` for omakase, `time`+`discount` for discount. Adding `lat`/`lon`
up front makes distance sort work immediately instead of falling back to the
city center.

## Coordinates

Right-click the spot in Google Maps — the first menu item shows the lat/lon.
Paste as `"lat": 40.7738, "lon": -73.9581`.

## Adding a new city

1. Create `data/<key>.jsonl`, named after the city key.
2. Add exactly one entry to the `CITIES` table in
   `bin/cities.rb`, with the fields known for that city:
   `location` (Yelp search string), `name` (display name), `currency` (ISO
   code), and `center` (`[lat, lon]`).

Invariant: **every `data/*.jsonl` filename stem must have a `CITIES` entry**.
A city that has both `center` and `currency` is *collectable* —
`collect_city.rb` can add new spots to it. Cities without them (for example
`nyc` and `singapore`) are *refresh-only*: `refresh_yelp_fields.rb` backfills
existing entries but does not add new ones. `COLLECTABLE_CITIES` is derived from
that rule.

`center` also drives behavior: it is the reference point for the 70 km
`within_city?` guard in `collect_city.rb` (Yelp's `location=` is a region, so
spots beyond 70 km are treated as a neighbouring metro and dropped) and the
anchor for Foursquare batch searches in `backfill_websites.rb`.

Finally, keep `BarWidget.qml`'s `cityMeta` display-name map in sync so the city
gets a nicer label than a title-cased key.

## Running the pipeline

The `bin/*.rb` scripts read API keys from a gitignored `.env`. Copy the
committed template and fill in the keys:

```bash
cp .env.example .env
# edit .env and set YELP_API_KEY (required) and FOURSQUARE_API_KEY (optional)
```

See `.env.example` for the key names and the Yelp/Foursquare developer links.

Commands:

```bash
ruby bin/collect_city.rb                 # collect ALL collectable cities (no city argument)
ruby bin/refresh_yelp_fields.rb [city]   # backfill missing fields on existing entries only
ruby bin/backfill_websites.rb [--dry-run] [city]  # find official websites
```

- `collect_city.rb` adds new spots from Yelp to every city in
  `COLLECTABLE_CITIES`; it takes no city argument. Deduplicates by name + city.
- `refresh_yelp_fields.rb` only fills missing fields on entries already in a
  `data/*.jsonl` file — it never adds spots. Pass a city key to limit the run.
- `backfill_websites.rb` resolves official sites via Nominatim, then Foursquare
  batch searches. `--dry-run` prints hits without writing; it skips the crawl
  when fewer than 20 spots are missing.

Every script requires `bin/pipeline_common.rb`, the slim require hub over
`cities.rb` (the `CITIES` table), `jsonl.rb` (JSONL/progress IO), and
`yelp_client.rb` (Yelp HTTP client + `search_yelp`). Add shared city data to
`cities.rb`, not to a script.

Both long-running scripts resume from progress files (`.fetch-progress`,
`.website-progress`, gitignored). Without a populated `.env`, a run fails: the
Yelp key is required by `collect_city.rb` and `refresh_yelp_fields.rb`.

## Verifying your change

Run the full check set before opening a PR:

```bash
omarchy plugin validate .
node tests/spot_utils_test.js
node tests/catalog_utils_test.js
ruby tests/validate_data.rb
ruby tests/pipeline_common_test.rb
ruby tests/pipeline_test.rb
```

To reload the running shell after a plugin change, run `omarchy-restart-shell`.

## Submitting a PR

Create a branch, commit your change, and open a pull request against `main`.
Keep one restaurant per line and field names lowercase; values are strings
unless noted. Nerd-font glyphs are fine in data values — keep them out of
comments.
