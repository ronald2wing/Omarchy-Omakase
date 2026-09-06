# Omakase

A worldwide sushi directory and sushi-spot tracker for the Omarchy
desktop shell.

It lives in the bar: every spot is sorted by distance from home. You search and
filter by city, state, country, and neighborhood, and you rate the spots you try
with notes.

The Omakase plugin ships two entry-point kinds:

- **Service** — headless. Loads the seed directory, owns the persistent state
  and the IPC surface.
- **Bar widget** — the panel UI. Reads state from files and sends rating
  actions to the service over IPC.

## Requirements

- Omarchy (a Quickshell-based shell).
- Omarchy's weather plugin configured with a location (see
  [Home location](#home-location)).

## Install

From the repository:

```bash
omarchy plugin add https://github.com/ronald2wing/Omarchy-Omakase.git --enable
```

Add `--yes` to skip the confirmation and bar-placement prompts. After installing
or updating (`omarchy plugin update omakase`), restart the shell (hot-reload is
unreliable; see [CONTRIBUTING.md § Install / reload](CONTRIBUTING.md#install--reload)):

```bash
omarchy-restart-shell
```

Confirm the service is up:

```bash
omarchy-shell omakase ping
# ok
```

## Home location

Distance sorting, the radius filter, and the home-to-city distance display use
your location from Omarchy's weather plugin. Set it in the weather panel;
Omakase reads the coordinates in the weather plugin's settings file
(`~/.local/state/omarchy/settings/weather.json`) as "home" and watches the file,
picking up changes. Without a location there is no distance to compute:
distance sorting falls back to catalog order, and the radius filter matches no
spot.

## Using the panel

### Explore, Wishlist, Journal

The panel has three tabs — Explore, Wishlist, and Journal — with the Wishlist
and Journal chips showing their saved/rated counts.

| Tab | What it does |
| --- | --- |
| **Explore** | Browse every spot in the directory. Search, filter, sort, or tap the **Surprise me** pill for a random pick. |
| **Wishlist** | Spots you saved. Tap the heart on any spot to pin it here. |
| **Journal** | Every spot you have rated. Open an entry to change the stars or notes (both save as you edit), or remove it. |

### Search

Typing filters the list by spot name or neighborhood (accent-insensitive, so
`sake` finds `Saké` and `poke` finds `Poké King`).

Every search bar — Explore (shared with the Spotlight "Surprise me" view),
Wishlist, and Journal — has a clear (`✕`) button that appears once there is
text. As you type, a dropdown suggests **geography** to jump into: city names,
neighborhoods, and US states (a state matches its two-letter code or its full
name, e.g. `New Jersey`). Suggestions are scoped per tab: on **Wishlist** they
cover only your **saved** spots and on **Journal** only your **rated** spots,
while Explore (and Spotlight, which reuses Explore's search) stay catalog-wide.
Escape is two-stage: it dismisses the dropdown first, and closes the panel only
when no dropdown is open.

### Filters

The primary filter row sits under the search field:

- **All / AYCE / Discount / Omakase** — a boxed segmented control (see
  [Spot kinds](#spot-kinds)).
- **Unrated** — hide spots you have already rated (hidden on the Journal tab,
  which already lists only rated spots).
- **Sort** — cycles the sort order (see [Sort](#sort)).
- **Radius** — cycles the radius (see [Radius](#radius)).
- **More filters** — opens a sheet with the location scopes: **City**, **State**
  (US two-letter code; Yelp region codes for non-US cities are ignored),
  **Country** (as reported by Yelp), and **Neighborhood** (appears once a city
  with neighborhoods is selected). Each sheet row resets via its own **All
  cities** / **All states** / **All countries** / **All neighborhoods** row.

When any filter is active, a summary line lists each as a clickable outlined
token that removes that filter, plus a **Clear all** action that resets every
filter.

### Sort

The **Sort** control cycles **Distance → Rating → Price**. Distance sorts
nearest first, rating highest first, price cheapest first. The trailing arrow
reverses the order.

### Radius

The **Radius** pill cycles off → 5 km → 10 km → 20 km; the active-filter token
and the city header read **Within 10 km**. Selecting a radius clears the
location scopes (city, state, country, neighborhood); picking a location scope
clears the radius. Distance is straight-line (haversine) kilometres.

### Spot kinds

Each spot is one of three kinds, shown as a label on its card:

- **AYCE** — all-you-can-eat.
- **Discount** — a happy-hour deal.
- **Omakase** — a set menu.

The **All / AYCE / Discount / Omakase** control in the filter row narrows the
list to one kind. The detection rules live in
[CONTRIBUTING.md § Spot kinds](CONTRIBUTING.md#spot-kinds).

### Surprise me

The **Surprise me** pill picks a random open spot from the current search and
filter results and opens it full-panel with the rating form ready. It can be
re-rolled with the shared **Surprise me** pill in the pinned header.

### Rating

Expand a spot (or use Surprise me) to reveal the rating form. There is no
**Save** button: tapping a star commits the rating immediately, and notes
auto-save about 600 ms after you stop typing. **Remove rating** is the only
button — it deletes the rating. The expanded form is the rating/notes editor
only. The stars on a collapsed card row quick-rate without expanding — hovering
across them previews the rating a click would set — and the collapsed card's
**Phone** cell dials in one click.

Each collapsed card carries five action cells: **Save** / **Saved** (heart),
**Website**, **Open in Maps**, **Copy** (formatted spot text to the
clipboard), and **Phone** (dials, or copies the number when no dialer is
available). The clickable **Yelp** rating pill sits beside those five cells —
it is a link to the spot's Yelp page, not a sixth action.

## Adding your own spots

Add spots as seed-shaped entries (plus a `city`) in
`~/.local/state/omakase/user_spots.json`; they merge into the directory. The
field reference lives in [CONTRIBUTING.md](CONTRIBUTING.md).

## Command line

The service exposes a small command surface you can call from a terminal:

```bash
omarchy-shell omakase ping
omarchy-shell omakase refresh                                  # re-read the seed data
omarchy-shell omakase rate "<name>" <1-5> [notes] [city]       # rate or update a spot
omarchy-shell omakase unrate "<name>" [city]                   # remove a rating
omarchy-shell omakase undo                                     # revert the last rate/unrate (within 5 min)
```

## License

MIT
