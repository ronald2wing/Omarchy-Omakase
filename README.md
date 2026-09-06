# Omakase

A worldwide omakase directory and sushi-spot tracker for the Omarchy desktop shell. Browse by city, rate spots you try, and track your history.

## Requirements

- Omarchy (Quickshell-based shell).
- Omarchy's weather plugin configured with a location. Omakase reads its
  coordinates to compute distances from home; without them, distance sorting and
  the radius filter do not work.

## Install

From the Omarchy plugin marketplace, or manually:

```bash
omarchy plugin add https://github.com/ronald2wing/Omarchy-Omakase.git --enable
```

Add `--yes` to skip the confirmation prompt.

## Using the panel

The panel has three tabs:

| Tab | What it does |
|-----|--------------|
| **Explore** | Browse every spot in the directory. Search, filter, sort, or tap Surprise Me for a random pick. Tap a star to quick-rate. |
| **Wishlist** | Spots you saved. Tap the heart on any spot to pin it here. |
| **Journal** | Every spot you have rated. Open an entry to update the rating or notes, or remove it. |

### Filters

The filter bar under the search field:

- **Type** — All / Omakase / Discount.
- **Unvisited** — hide spots you have already rated. In the Journal tab the
  pill reads **Visited** and is disabled, since the Journal already lists only
  rated spots.
- **City** — pick a city from the list.
- **State** — US two-letter code (Yelp uses region codes for non-US cities).
- **Country** — as reported by Yelp.
- **Neighborhood** — appears once a city is selected.

A **✕** button clears every active filter.

### Sort

The sort chip cycles through **Distance → Rating → Price → Date**. Tap the
trailing arrow to reverse the order (ascending/descending). Rating sorts
highest-first; Distance is nearest-first. Price uses the spot's own `price`
(not Yelp's `$$` bucket); Date sorts journal entries by visit time.

### Radius

The **Nearby** control cycles off → 5 km → 10 km → 20 km. Selecting a radius
clears the city and neighborhood filters, so it searches around your home
location. Distance uses straight-line (haversine) kilometres.

### Rating

Opening a spot shows the detail form: tap the stars, add notes, then submit.
The buttons are:

- **Save / Saved** — add or remove the spot from your Wishlist.
- **Submit / Update** — write the rating. It reads **Update** when the spot
  already has a rating, **Submit** otherwise.
- **Remove** — delete the rating (visible only when one exists).

The Service owns the journal; the bar widget only sends the rate/unrate action.
A completed rating can be undone within five minutes via the `undo` IPC method.

### Surprise Me

The **Surprise Me** floating button picks a random spot from the current
Explore filter results and opens its detail view.

## Home location

Distance sorting, the radius filter, and the home-to-city distance display all
use the home coordinates from the Omarchy weather plugin. Set your location in
the weather panel; Omakase watches its settings file and picks up changes.

## Data

Omakase ships a worldwide omakase directory; see
[CONTRIBUTING.md](CONTRIBUTING.md) for the schema and how to add spots or
cities.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Add a line to the right
`data/<city>.jsonl`, verify it, and open a pull request against `main`.

## License

MIT
