# Omakase

A worldwide omakase (sushi) directory and sushi-spot tracker for the Omarchy
desktop shell. Browse 5,016 spots across 65 cities, sorted by distance from
home; search and filter by city, state, country, and neighborhood; rate what
you try and keep a journal.

Two plugin kinds work together:

- **Service** (`Service.qml`) — headless. Loads the seed directory, owns the
  persistent state and the IPC surface.
- **Bar widget** (`BarWidget.qml`) — the panel UI. Reads state from files and
  sends rate/unrate actions to the service over IPC.

## Requirements

- Omarchy (a Quickshell-based shell).
- Omarchy's weather plugin configured with a location. Omakase reads the
  weather plugin's coordinates to compute distance from home; without them,
  distance sorting and the radius filter do nothing.

## Install

From the Omarchy plugin marketplace, or from the repository:

```bash
omarchy plugin add https://github.com/ronald2wing/Omarchy-Omakase.git --enable
```

Add `--yes` to skip the confirmation prompt.

The shell loads the installed copy from `~/.config/omarchy/plugins/omakase/`.
After installing or updating, restart the shell — hot-reload is not relied on:

```bash
omarchy-restart-shell
```

Do not run two shell instances at once. Confirm the service is up:

```bash
omarchy-shell omakase ping
# ok
```

## Using the panel

The panel has three tabs:

| Tab | What it does |
| --- | --- |
| **Explore** | Browse every spot in the directory. Search, filter, sort, or tap **Surprise me** for a random pick. |
| **Wishlist** | Spots you saved. Tap the heart on any spot to pin it here. |
| **Journal** | Every spot you have rated. Open an entry to update the rating or notes, or remove it. |

### Filters

The primary filter row sits under the search field:

- **Type** — All / Omakase / Discount.
- **Unrated** — hide spots you have already rated.
- **Nearby** — cycles the radius (see [Radius](#radius)).
- **Filters** — opens a sheet with the location scopes: **City**, **State**
  (US two-letter code; Yelp region codes for non-US cities are ignored),
  **Country** (as reported by Yelp), and **Neighborhood** (appears once a city
  with neighborhoods is selected). The sheet has its own **Clear all**.

When any filter is active, a summary line lists each as a clickable token that
removes that filter, plus a **Clear all** button that resets every filter.

### Sort

The sort chip cycles **Distance → Rating → Price**. Tap the trailing arrow to
reverse the order. Distance sorts nearest-first, rating highest-first. Price
sorts by the numeric price; discount spots with no numeric price sort cheapest,
and non-discount spots with no numeric price fall back to their Yelp price
bucket (`$` → 10 through `$$$$` → 40). Unpriced spots sort last, and equal
prices tie-break by rating, then review count, then name.

### Radius

The **Nearby** pill cycles off → 5 km → 10 km → 20 km; an active radius reads
**Within 10 km**. Setting a radius clears
the location scopes (city, state, country, neighborhood) so the list is built
around your home location; the radius itself is preserved. Distance is
straight-line (haversine) kilometres.

### Rating

Opening a spot shows the rating form: tap the stars, add notes, then save. The
buttons are **Save** and **Remove** (the latter only when a rating exists). A
rating or removal can be undone within five minutes via the service's `undo`
method.

### Home location

Distance sorting, the radius filter, and the home-to-city distance display all
use the home coordinates from the Omarchy weather plugin. Set your location in
the weather panel; Omakase watches its settings file and picks up changes.

## Data

Omakase ships a worldwide directory — one `data/<city>.jsonl` file per city,
one spot per line. State is kept outside the plugin directory, under
`~/.local/state/omakase/`. See [CONTRIBUTING.md](CONTRIBUTING.md) for the
schema, how to add a spot or city, and how to verify a change.

## License

MIT
