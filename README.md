# Omakase

Chef's-choice meal planning for the Omarchy desktop shell.
<https://github.com/ronald2wing/Omarchy-Omakase>

Omakase picks your meals so you don't have to. The panel shows today's plan —
breakfast, lunch, and dinner — each meal with a cuisine, a one-line blurb, and a
"pairs with" drink. Rate a meal 1–5 or decline it, and add an optional note.
Every rating, decline, and note is logged to a journal that sharpens the scoring
behind every future plan. A history view lists past meals, and a copy-to-share
button turns any meal into a one-line summary for the clipboard.

## How it works

- **Service** (`Service.qml`) runs headless and owns the IPC handler. It loads
  config, fetches candidate restaurants, recipes, and drinks, scores them, and
  writes state to `~/.local/state/omakase/`.
- **Panel** (`BarWidget.qml`) is file-driven: it reads `state.json` and renders
  the plan grouped by meal type. Actions (rate, decline, undo) go over IPC; the
  panel never reads state over IPC.
- **Scoring** (`Model.js`) is pure logic, unit-tested under Node, weighing
  recency, declines, cuisine variety, time of day, distance, your past ratings,
  cuisine affinity, and the sentiment of your notes.

The daily plan is sticky: it only regenerates when the day rolls over or when
you rate or decline a meal. Declined meals are remembered and avoided for a
while.

## Keyless data sources

No API keys required — only `curl` and `jq`:

- **Restaurants** — OpenStreetMap's Overpass API (nearby, ranked by distance).
- **Recipes** — TheMealDB.
- **Drinks** — TheCocktailDB.
- **Location** — ipwho.is IP geolocation on first run.

## Install

```bash
omarchy plugin add https://github.com/ronald2wing/Omarchy-Omakase --enable
```

Then restart the shell: `omarchy-restart-shell`.

## Remove

```bash
omarchy plugin remove omakase
```

## Config

`~/.config/omakase/config.json`:

```json
{
  "home": { "lat": 51.5074, "lon": -0.1278, "city": "London" },
  "radiusKm": 10,
  "refreshIntervalSec": 3600
}
```

- `home` — your location (`lat`/`lon`/`city`). Leave at `(0,0)` to auto-detect
  from your IP on first run.
- `radiusKm` — restaurant search radius.
- `refreshIntervalSec` — catalog refresh interval (min 60s).

## Data

All state lives outside the plugin directory under
`~/.local/state/omakase/`:

- `state.json` — snapshot the panel reads (plan, journal, last error, …).
- `journal.json` — your rated/declined meal history.
- `plan.json` — the current plan.
- `undo.json` — the last undoable action.
- `cache/` — cached restaurant/recipe/drink catalogs.

## IPC

All commands target the plugin id `omakase`:

```bash
omarchy-shell omakase <method> [args...]
```

| Method | Args | Purpose |
| --- | --- | --- |
| `ping` | | liveness check |
| `refresh` | | re-fetch all catalogs |
| `generatePlan` | `day`\|`week` | build a plan (defaults to `day`) |
| `rate` | `id`, `1-5`, `[notes]` | rate a planned meal |
| `decline` | `id`, `[notes]` | decline a planned meal |
| `undo` | | undo the last rate/decline (5-min window) |
| `searchRestaurants` | `query` | re-fetch restaurants filtered by name |
| `searchRecipes` | `query` | fetch recipes matching a query |
| `setHome` | `lat`, `lon` | set the home location |
| `locateIp` | | geolocate home from your IP |
| `addMeal` | `json` | add a journal entry |
| `removeMeal` | `id` | remove a journal entry |

Example:

```bash
omarchy-shell omakase setHome 51.5074 -0.1278
omarchy-shell omakase generatePlan day
omarchy-shell omakase rate rest-123 4 "great pizza"
```

## License

MIT — see [LICENSE](LICENSE).
