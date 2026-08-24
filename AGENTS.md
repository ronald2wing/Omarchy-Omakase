# AGENTS.md

Omarchy desktop-shell plugin (QML/Quickshell) for chef's-choice meal planning. Plugin id `omakase`. Dual-kind: `service` (headless, owns IPC) + `bar-widget` (UI). License MIT. Core interaction: the panel shows today's meal plan (name + cuisine + blurb + a "pairs with" drink); the user rates each meal 1–5 or declines it, and can add a free-text note; rating/decline/note logs to the journal and feeds the scoring engine. History has its own view.

## Verify

Run all checks before claiming done (validate → lint → scripts → tests):

```bash
omarchy plugin validate .
qmllint -I /usr/share/omarchy/shell Service.qml
qmllint -I /usr/share/omarchy/shell BarWidget.qml
bash -n bin/*.sh
node tests/model.js
bash tests/validate.sh
```

- `qmllint` REQUIRES `-I /usr/share/omarchy/shell` or the `qs.Commons`/`qs.Ui` imports won't resolve.
- `omarchy plugin validate .` checks the manifest schema and that entry points exist.
- `tests/model.js` is the only unit test (Model.js scoring logic, 53 tests). `tests/validate.sh` is static validation.

## Architecture

- `Service.qml` does all work: loads config, fetches catalogs (Overpass restaurants + TheMealDB recipes + TheCocktailDB drinks via `bin/` scripts), maintains journal/plan/cache/state JSON, runs the scoring engine, owns the `IpcHandler` (target = plugin id `omakase`).
- `BarWidget.qml` reads state from `~/.local/state/omakase/state.json` via `FileView{watchChanges:true}` — display is FILE-DRIVEN. IPC is only for ACTIONS (never for reading state). It has a `view` property ("plan"|"history") toggled by a PanelHero trailingControl button.
- `Model.js` is the only unit-tested logic (scoring: recency/cuisine-variety/time-of-day/distance/rating/decline/cuisine-affinity/note-sentiment + formatting: blurb/drink/formatTimestamp). It is `module.exports`-guarded so it loads under both Node (tests) and QML (`import "Model.js" as M`). Keep parsing/formatting here, not in QML.
- `bin/lib.sh` holds shared paths + the `have` helper (+ `require_curl`/`save_cache`). `bin/fetch-restaurants.sh` (Overpass, haversine distanceKm), `bin/fetch-recipes.sh` (TheMealDB), `bin/fetch-drinks.sh` (TheCocktailDB), `bin/locate-ip.sh` (ipwho.is geolocation).
- IPC surface (`omarchy-shell omakase <method>`): `ping`, `refresh`, `addMeal`, `removeMeal`, `generatePlan [day|week]`, `rate <id> <1-5> [notes]`, `decline <id> [notes]`, `undo`, `searchRestaurants <query>`, `searchRecipes <query>`, `setHome <lat> <lon>`, `locateIp`. `generatePlan` defaults to `"day"`. The UI shows a separate decline button (✕) beside the [1][2][3][4][5] rating buttons.

## Config & state

- Config `~/.config/omakase/config.json`: `{ home: {lat, lon, city}, radiusKm, refreshIntervalSec }`.
- State `~/.local/state/omakase/state.json`: `{ updatedAt, home, radiusKm, plan, journal, lastError, lastActionAt }` (`lastActionAt` is the timestamp of the last rate/decline, driving the 5-minute undo window).
- Plan item: `{ mealType, id, source, name, cuisine, score, reasons, blurb, website, address, drink, drinkThumb }`. `source` ∈ `restaurant`|`recipe`|`manual`. Journal entry (from rate/decline): `{ id, timestamp, mealType, name, cuisine, source, drink, restaurantId?|recipeId?, declined, rating?, notes? }`.
- Journal `~/.local/state/omakase/journal.json`, plan `plan.json`, undo snapshot `undo.json`, cache `cache/restaurants.json` + `cache/recipes.json` + `cache/drinks.json`.
- All data lives OUTSIDE the plugin dir. Use `Quickshell.env("HOME")`, never hardcoded paths.
- The daily plan is STICKY: `generatePlan` skips regeneration when `plan[0].date === today`. It only re-ranks when the day rolls over or the user rates/declines.

## Gotchas (hard-earned — do not re-learn these)

- **A `service` kind receives NO `settings` property.** The shell injects only `omarchyPath`/`shell`/`manifest`/`barWidgetRegistry`/`pluginRegistry`. Put service tunables in `config.json`, read via FileView.
- **The bar-widget must NOT register a second `IpcHandler`.** Root is `Panel { moduleName; manageIpc: false }` — the service owns the target.
- **QML property names must start lowercase** (camelCase). Uppercase-start passes qmllint but fails at RUNTIME silently.
- **Qt 6.11 dropped implicit signal-param injection.** Handlers must use arrow functions — `onXChanged: (v) => root.y = v`, NOT `onXChanged: root.y = v`.
- **Don't declare signals that shadow base QML signals** (e.g. `signal focusChanged` shadows `Item.focusChanged`). Prefix custom signals (e.g. `fieldFocusChanged`).
- **Changing IPC method names does NOT take effect via hot-reload.** The running `quickshell` caches the old QML. Run `omarchy-restart-shell`. Test IPC with `omarchy-shell [-q] omakase <method> [args...]`.
- **`FileView.setText()` skips the write when content is unchanged.** If the write is a change SIGNAL, include an always-changing field (e.g. `updatedAt: Date.now()`).
- **`qs.Ui` has NO `Field` type** — it exports `TextField`/`NumberField` only. If you use `Field { }`, you MUST define it as a local `component Field: Column { ... }` (see BarWidget.qml). Referencing an undefined type makes the widget fail to LOAD silently (no icon, no error in journalctl — the shell's `console.warn` goes to discarded stderr).
- **Panel content must be NESTED inside the KeyboardPanel.** Correct nesting: `KeyboardPanel > PanelKeyCatcher > Flickable > Column`. If the Flickable/Column are SIBLINGS of the KeyboardPanel, the panel opens EMPTY.
- **Nerd Fonts v3 dropped the old Material Design range U+F500–U+FD46.** Do NOT use 4-hex `\uf8b6`-style escapes for Material Design icons — they render as nothing. Free Font Awesome escapes still render: `\uf2e7` (utensils), `\uf1da` (history), `\uf08e` (external-link), `\uf0c5` (copy), `\uf00d` (times/decline), `\uf017` (clock), `\uf0e2` (undo). Supplementary-plane glyphs (the cuisine icons) must be pasted as LITERAL UTF-8, not `\uXXXX` escapes — 4 hex digits can't reach U+10000+ anyway. The bar font is `monospace` (fontconfig alias).
- **A circular geometry dependency hangs the shell.** `width: parent.width` inside a `Row` with no explicit width (where Row.width derives from children) → CPU-bound layout feedback loop → shell main thread spins, never services IPC → `omarchy-shell` times out with "is not responding" and `omarchy-restart-shell` also hangs. Fix: remove the circular width or give the Row an explicit width.
- **Shell logs live at `/run/user/1000/quickshell/by-id/<instance-id>/log.log`** (NOT journalctl). This is where QML `console.warn`/errors go. The newest instance dir is the live one.
- **The panel view toggle (`view` = "plan"|"history") is pure UI** — a `visible`-flag on the one `Column`, not a separate page. Keep `KeyboardPanel > PanelKeyCatcher > Flickable > Column` nesting; do NOT split into two Columns.
- **Shell hangs are not recoverable via `omarchy-restart-shell`** (it signals exit over the same hung IPC). Kill the hung quickshell PID directly (`kill <pid>`, escalate to `kill -9`), fix the QML, then restart.

## Install / enable / reload

- Installed copy: `~/.config/omarchy/plugins/omakase/` (the running shell loads THIS, not the working dir). Keep the working dir `/home/bigbrother/Desktop/Omarchy/Omakase/` in sync (it's the git source of truth).
- Enabled state: `~/.config/omarchy/shell.json` bar layout (omakase in `right` section) + `omarchy plugin list --json`.
- **Saving a file under `~/.config/omarchy/plugins/` auto-reloads the plugin** ("Local plugin changed, reloading: omakase"). `omarchy-shell shell rescanPlugins` forces a reload.
- Full restart: `omarchy-restart-shell` (or `pkill -f "quickshell -n -p /usr/share/omarchy/shell"`). **Always run the restart after changing plugin files** — don't rely on hot-reload; the user requires an explicit restart after every change.
- `omarchy plugin validate .` in the working dir validates the manifest + entry points.

## Notes

- Nerd-font glyphs in UI strings are fine (project convention); keep comments emoji-free.
- Publishing target: `homepage`/`repository` in `manifest.json` (HTTPS) point to `https://github.com/ronald2wing/Omarchy-Omakase`; git remote `origin` is `git@github.com:ronald2wing/Omarchy-Omakase.git`; branch is `main` — already configured.
- Reference plugins: `~/.config/omarchy/plugins/shop/` (working service+bar-widget, the model to follow) and `/usr/share/omarchy/shell/plugins/` (first-party).
