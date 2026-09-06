# AGENTS.md

## Repo summary

Omakase is an Omarchy desktop-shell plugin (QML/Quickshell) — a worldwide
omakase (sushi) directory and sushi-spot tracker. Plugin id `omakase`. License
MIT.
Dual-kind: `service` (headless; loads seed data, owns persistent state + IPC) and
`bar-widget` (the panel UI). It shows every spot sorted by distance from home,
lets you search/filter by city, state, country, neighborhood, and rate spots 1–5
with notes.

Terminology: **Omakase** is the product/plugin; `"omakase"` is the spot **kind**
value (as opposed to `"discount"` happy-hour spots).

## Verify

Run all checks before claiming done:

```bash
omarchy plugin validate .
node tests/spot_utils_test.js
node tests/catalog_utils_test.js
ruby tests/validate_data.rb
ruby tests/pipeline_common_test.rb
ruby tests/pipeline_test.rb
```

- `omarchy plugin validate .` — manifest schema + entry points.
- `node tests/spot_utils_test.js` — formatters/geography (Node + QML dual-use).
- `node tests/catalog_utils_test.js` — catalog pure helpers (Node + QML dual-use).
- `ruby tests/validate_data.rb` — every `data/*.jsonl` line parses as JSON.
- `ruby tests/pipeline_common_test.rb` — shared pipeline helpers
  (`bin/pipeline_common.rb` and its requires).
- `ruby tests/pipeline_test.rb` — Ruby pipeline pure functions (minitest, no API
  calls; `main` is guarded by `if __FILE__ == $PROGRAM_NAME`).
- `qmllint` is unreliable here (exit 255, empty output) — rely on the shell
  runtime log instead.

## Repo map

- `Service.qml` — `service` kind. Loads seed data, watches weather/home, owns
  `state.json` / `journal.json` / `user_spots.json` / `undo.json`, owns the
  `IpcHandler` (target `omakase`).
- `BarWidget.qml` — `bar-widget` kind. The panel UI; reads state files (never via
  IPC), sends rate/unrate actions over IPC.
- `spot-utils.js` — shared formatters/geography, used by Node tests and QML.
- `catalog-utils.js` — pure catalog helpers (`coordKey`, `decoratedSort`,
  `aggregateList`, `applySearchFilter`, …), used by Node tests and QML.
- `bin/*.rb` — Ruby data pipeline: `collect_city.rb`, `refresh_yelp_fields.rb`,
  `backfill_websites.rb`, `sort_data.rb`, plus the `pipeline_common.rb` require
  hub and its `cities.rb` / `jsonl.rb` / `yelp_client.rb` modules.
- `tests/*` — unit tests + the data validator.
- `data/<key>.jsonl` — seed directory, one city per file, one JSON object per line.
- `manifest.json` — plugin manifest (id, version, kinds, entry points).
- Field table, `.env` setup, and JSONL examples live in
  [CONTRIBUTING.md](CONTRIBUTING.md) — not duplicated here.

## Architecture

### Service (`Service.qml`)

- **Seed loading.** A `Process` shells out to `bash -c` looping `data/*.jsonl`
  and printing `city\t<json>` per line; malformed lines are skipped. `sourceDir`
  is passed as argv (`$1`), so a HOME containing spaces or shell metacharacters
  can't break or inject. The loader runs only on first run (`state.json` missing)
  or `refresh` — an existing state is re-parsed into memory instead, avoiding a
  ~2.8 MB reserialize on every restart. This bash is the *runtime* loader, not a
  dev script; keep it (bash is the zero-dependency choice for user machines).
- **Home location.** A `FileView` watches the weather plugin's
  `~/.local/state/omarchy/settings/weather.json`; `latitude`/`longitude` become
  `homeLat`/`homeLon`.
- **`state.json`.** Service is the only writer. It is rewritten only when the
  location actually moved (`reconcileLocation` gates on `catalogLoaded` and
  `locationApplied`), so an unchanged home never burns a 2.8 MB write.
- **`persistedSpotFields`** — whitelist applied by `sanitizeSpot()` to every spot
  before it reaches `state.json`, dropping unknown/injected fields. Current list: `name`,
  `lat`, `lon`, `neighborhood`, `website`, `phone`, `price`, `courses`,
  `currency`, `time`, `discount`, `yelp_url`, `state`,
  `image_url`, `is_closed`, `yelp_rating`, `yelp_review_count`, `yelp_price`,
  `country`, `transactions`, `display_address`.
- **`user_spots.json`** — a watched Service input at
  `~/.local/state/omakase/user_spots.json`. Entries carry the same fields as a
  seed spot plus `city`; they are merged into the catalog under their lowercased
  `city` when `state.json` is written, each passed through `sanitizeSpot`. This is
  how a user adds a spot without editing `data/`.
- **`undo.json`** — Service writes `{ snapshot: <journal array>, at: <epoch ms> }`
  before every `rate`/`unrate`. `undo` replays the snapshot only while
  `Date.now() - at <= 5 min` (`undoWindowMs`); older snapshots return
  "nothing to undo".
- **IPC surface** (`omarchy-shell omakase <method>`): `ping`, `refresh`,
  `rate <name> <1-5> [notes] [city]`, `unrate <name> [city]`, `undo`. All return
  a string: `"ok"` or `JSON.stringify({ok, data|error})`. `rate`/`unrate`
  truncate input to `maxNameLen`/`maxNotesLen`/`maxCityLen`.

### BarWidget (`BarWidget.qml`)

- **File-driven reads.** Three `FileView`s (`watchChanges: true`) watch
  `state.json`, `journal.json`, `wishlist.json`. IPC is for *actions* only
  (`rate`/`unrate`, fired through
  `Quickshell.execDetached(["omarchy-shell","omakase",…])`); the widget never
  reads via IPC.
- **No second `IpcHandler`.** Root is `Panel { moduleName: "omakase";
  manageIpc: false }` — the Service owns the target.
- **Tabs.** Explore / Wishlist / Journal are sibling components inside one
  `contentColumn` `Column`, only one visible via `root.tab`. Each card has a lazy
  `RatingEditor` (`Loader { active: expanded }`).
- **Key `root.*` state:** `catalog`, `journal`, `saved`, `tab`, `expandedSpotName`,
  `editStars`, `editNotes`, `cityKey`, `stateFilter`, `countryFilter`,
  `searchText`, `kindFilter`, `sortBy`, `sortReversed`, `radius`, `neighborhood`,
  `openDropdown`, `unvisited`, `spotlight`, `spotlightEntry`, `wishlistQuery`,
  `journalQuery`, `visibleCount`, `dataRevision`, `catalogVersion`.
- **Declarative cache model.** Derived data is declarative properties, not
  lazy write-on-read getters, so no binding writes a property during evaluation
  (the source of binding loops). Each property lists its tracked inputs
  explicitly (reads inside `computeX()` aren't tracked) then calls a pure
  compute function: `filteredSpots` ← filter/sort state + `distanceVersion`;
  `searchedSpots` ← `filteredSpots` + `searchText` +
  `neighborhoodSearchIndex` (the match itself is `CatalogUtils.applySearchFilter`);
  `pagedSpots` ← `searchedSpots` + `visibleCount`, snapshotted into the `exploreSpots`
  model by `onPagedSpotsChanged`; `distanceByCoords` (plain, published by the
  chunked build) ← `catalogVersion` + home, with declarative readers tracking
  `distanceVersion` instead; `neighborhoodSearchIndex` ← `catalogVersion`;
  `sortedJournalData` ← `journal` + sort/filter + the rating
  and spot-name indexes + home; `neighborhoodOptions` ← `cityKey` +
  `catalogVersion`; `statesData`/`countriesData` ← `catalogVersion` + home +
  `distanceByCoords` (aggregated via `CatalogUtils.aggregateList`);
  `ratedEntries` ← `journal`. `displayCityMap`, `savedSet`,
  `ratingsBySpot`, `journalByName`, and `spotsByName` are rebuilt eagerly from
  `onCatalogChanged`/`onJournalChanged`/`onSavedChanged` (and
  `Component.onCompleted`). `catalogVersion` increments on catalog change
  and home move. `dataRevision` remains only for bindings that call functions
  (`filteredWishlist`, `filterDescriptionData`), whose internal reads the binding
  engine does not track; it bumps on filter change and `resetListWindow()` just
  resets `visibleCount` + bumps `dataRevision` (no cache-key clearing).
  `visibleCount` is the lazy paging window (`pageSize` 88), reset on
  filter/search change.
- **`cityMeta`.** A hardcoded display-name/country/center map keyed by data
  filename stem (e.g. `"nyc" → { name: "New York City", country: "USA", lat, lon }`),
  covering a subset of keys; `displayCity()` title-cases the key for the rest and
  `cityDistanceKm()` falls back to the first spot's coordinates. `"australia"`
  maps to Sydney. Keep it in sync with `CITIES` when adding a city.
- **Sort / filter model.** `sortBy` ∈ `distance` | `rating` | `price` |
  `date`, with `sortReversed` flipping the order. `stateFilter` accepts only US
  2-letter codes —
  Yelp region codes for non-US cities are ignored; `countryFilter` uses Yelp's
  `country`. Selecting a radius clears city + neighborhood. Geo-less spots sort
  last.

### `spot-utils.js`

Shared formatters/geography. Exports `spotKind`, `haversine`, `formatDate`,
`priceNumber`, `currencySymbol`, `formatPrice`, `formatCourses`, `formatDistance`,
`parseJson`, `canBook`, `isClosed`, `spotImageUrl`, `mapsUrl`,
`formatSpotClipboard`. `module.exports`-guarded so it loads under
Node (tests) and QML (`import "spot-utils.js" as SpotUtils`). Keep
parsing/formatting here, not in QML.

### `catalog-utils.js`

Pure catalog helpers extracted from `BarWidget.qml`. Exports `coordKey`,
`compareSortValues`, `decoratedSort`, `aggregateList`, `displayNameFor`, and
`applySearchFilter`. Every function takes its inputs explicitly (no `root.*`
reads), so it is unit-testable under Node and reusable verbatim from QML
bindings. `module.exports`-guarded; QML imports it as
`import "catalog-utils.js" as CatalogUtils`. Keep catalog pure logic here, not
in QML.

## Data & state

- **Seed data** `data/<key>.jsonl` — one JSON object per line; the filename stem
  (without `.jsonl`) is the city key. Field table and examples: [CONTRIBUTING.md](CONTRIBUTING.md).
  `australia.jsonl` is the one country-level key (spots across Australia); every
  other stem is a city. Files are kept **sorted by `name`** (case-insensitive,
  ties by `lat`/`lon`) so diffs stay clean — `bin/sort_data.rb` enforces it and
  `collect_city.rb` maintains it.
- **Runtime state** lives under `~/.local/state/omakase/`:
  - `state.json` — `{ updatedAt, cities, spotsByCity, homeLat, homeLon }`, with
    each spot reduced to `persistedSpotFields`.
  - `journal.json` — `[{ timestamp, name, rating, notes, city }]`.
  - `wishlist.json` — array of saved spot names (BarWidget is the writer).
  - `undo.json` — `{ snapshot, at }` for the 5-minute undo window.
  - `user_spots.json` — user-added spots (seed shape + `city`).
- All data lives OUTSIDE the plugin dir — use `Quickshell.env("HOME")`, never
  hardcoded paths.

## Ruby data pipeline (`bin/`)

Omarchy convention: **use Ruby, not Python/bash** for dev scripts (reach for JS
only when Ruby lacks an official lib). `YELP_API_KEY` (and optional
`FOURSQUARE_API_KEY`) live in a gitignored `.env`. Progress files are
`.*-progress*` (gitignored). Scripts guard `main` with
`if __FILE__ == $PROGRAM_NAME` so tests can `require` the pure functions;
`$stdout.sync = true` is set once in `pipeline_common.rb` and inherited through
`require`.

- **`collect_city.rb`** — first-time collection for every city in
  `COLLECTABLE_CITIES` (no city argument). Bulk `term=omakase&categories=sushi`
  search, two pages (100 results max). Hits must pass
  `relevant_omakase_business?`; duplicates are dropped via `dedup_key`.
  **`within_city?` rejects hits >70 km from the city center** — Yelp's
  `location=` is a *region*, so a big omakase city (NYC) can bleed into a
  neighbour (Philadelphia). Resumes via `.fetch-progress`.
- **`refresh_yelp_fields.rb`** — fills *missing* fields on existing entries,
  never adds spots. Two-phase: bulk `omakase` search matched by `id`
  (`pending_by_id`), then a per-name exact search for leftovers
  (`pending_by_name`); `fill_if_absent!` writes a value only when the field is
  absent. `needs_fill` requires only the fields Yelp
  reliably returns (`yelp_url`/`yelp_rating`/`is_closed`/`city`/`state`/
  `display_address`) — NOT `image_url`/`phone`, which ~2-6% of spots lack on
  Yelp itself (requiring them would re-search unfillable spots every run).
  Optional city argument.
- **`backfill_websites.rb`** — official-website lookup using only official APIs
  (no search-engine scraping, no browser spoofing): Nominatim (OpenStreetMap) as
  the per-spot fallback and the Foursquare Places API for batched nearby searches.
  Candidate hosts matching `BLOCKED_FRAGMENTS` (substring) or `AGGREGATOR_HOSTS`
  (exact/suffix) are rejected. `--dry-run` prints hits without writing; skips the
  crawl when fewer than `MIN_MISSING_TO_CRAWL` (20) spots are missing. Resumes
  via `.website-progress`.
- **`pipeline_common.rb`** — slim require hub: pulls in `cities.rb` /
  `jsonl.rb` / `yelp_client.rb` and defines the small shared helpers that don't
  warrant their own file — project paths, env-key loading, `canonical_yelp_url`,
  `haversine_km`, and the `entry_sort_key`/`sort_entries!` sort helpers.
- **`cities.rb`** — the single `CITIES` table plus `collectable?` and
  `COLLECTABLE_CITIES`. Each entry carries only the fields known for that city:
  `location` (Yelp search string), `name` (display), `currency` (ISO code),
  `center` (`[lat, lon]`). A city with both `center` and `currency` is
  *collectable*; `COLLECTABLE_CITIES` is derived from exactly that rule. Curated
  cities without them (e.g. `nyc`, `singapore`) are refresh-only. `center` also
  anchors the 70 km guard above.
- **`jsonl.rb`** — JSONL/progress IO: `load_progress`, `load_jsonl` (skips
  malformed lines), atomic `write_atomic`, and `normalize_name` for fuzzy
  matching.
- **`yelp_client.rb`** — Yelp Fusion HTTP client: persistent per-host
  connections, `retry_wait`/`http_request` backoff, and `search_yelp` (the retry
  loop over `yelp_search_once`). Calls `load_env_key` from the hub at request
  time, so requiring it in tests never touches the real `.env`.
- **`sort_data.rb`** — re-sorts every `data/*.jsonl` (or the given cities) by
  `entry_sort_key`, rewriting only files whose order changed. Run it after a hand
  edit; the pipeline keeps files sorted automatically.
- **Invariant:** every `data/*.jsonl` filename stem must have a `CITIES` entry
  (the `CITIES` table is the source of truth for the count).

## Gotchas — QML

- **A `service` kind receives NO `settings` property** — only
  `omarchyPath`/`shell`/`manifest`/`barWidgetRegistry`/`pluginRegistry`. Home
  location comes from the weather-plugin file via FileView.
- **The bar-widget must NOT register a second `IpcHandler`.** Root is
  `Panel { moduleName; manageIpc: false }` — the service owns the target.
- **QML property names must start lowercase.** Uppercase-start passes qmllint but
  fails at RUNTIME silently.
- **Qt 6.11 dropped implicit signal-param injection** — use arrow functions:
  `onXChanged: (v) => root.y = v`, NOT `onXChanged: root.y = v`.
- **Don't shadow base QML signals** (e.g. `signal focusChanged`). Prefix custom
  signals.
- **Changing IPC method names does NOT take effect via hot-reload** — the running
  quickshell caches old QML. Run `omarchy-restart-shell`.
- **`FileView.setText()` skips the write when content is unchanged** — include an
  always-changing field (e.g. `updatedAt: Date.now()`) for change signals.
- **Panel content must NEST: `KeyboardPanel > PanelKeyCatcher > Flickable >
  Column`.** Siblings of the KeyboardPanel → empty panel.
- **Circular geometry dependency hangs the shell** (`width: parent.width` in a
  `Row` with no explicit width). Kill the hung PID directly (`kill -9`), then fix
  — `omarchy-restart-shell` won't work once hung.
- **`readonly property` freezes bindings at component creation** — use `property`
  or a `Connections` handler for live re-evaluation.
- **An unknown QML property name crashes the WHOLE widget** (e.g. `topPadding`
  on a `Rectangle`) — the bar icon vanishes silently. Check
  `$XDG_RUNTIME_DIR/quickshell/by-id/<latest>/log.log` for
  `Plugin widget omakase failed`.
- **`averageRatingFor()` returns `null` (not 0) for unrated spots** — comparisons must
  use `!card.starValue`, not `card.starValue === 0`.

## Gotchas — Data

- **Empty arrays are valid JSON but mean "no data".** `merge_yelp`'s
  `fill_if_absent!` must reject `[]` (not just `""`/`nil`) — `[].to_s == "[]"` once
  fooled an early version into storing an empty `display_address`, which then
  made `needs_fill` think the field was already set.
- **Yelp search `location=` returns neighbouring metro areas** — the
  `within_city?` radius guard (see pipeline) exists because a Philadelphia fetch
  once pulled in ~93 NYC spots (verified by coordinates, not the `city` field,
  which Yelp fills with the real city).

## Install / reload

- Installed copy: `~/.config/omarchy/plugins/omakase/` — the running shell loads
  THIS, not the working directory. Keep the working directory in sync (git is the
  source of truth).
- **Always `omarchy-restart-shell` after changing plugin files** — don't rely on
  hot-reload; the user requires an explicit restart after every change.
- `omarchy plugin validate .` validates the manifest + entry points in the
  working directory.
- `omarchy-restart-shell` kills the old shell and relaunches it from Hyprland
  (`hyprctl dispatch hl.dsp.exec_cmd("omarchy-launch-shell")`), detached from the
  invoking terminal, so the new shell inherits the canonical session environment
  rather than transient terminal/SSH/dev-tool variables.

## Conventions

- Nerd-font glyphs in UI strings are fine (project convention); keep comments
  emoji-free.
- `manifest.json` `homepage`/`repository` (HTTPS) →
  `https://github.com/ronald2wing/Omarchy-Omakase`; git remote `origin` is
  `git@github.com:ronald2wing/Omarchy-Omakase.git`; branch `main`.
- Reference plugins: `~/.config/omarchy/plugins/shop/` (working
  service+bar-widget) and `/usr/share/omarchy/shell/plugins/` (first-party).
