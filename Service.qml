import QtQuick
import Quickshell
import Quickshell.Io
import "spot-utils.js" as SpotUtils
import "components"

// Omakase — worldwide omakase directory.
// Service kind: loads seed data, watches the weather-plugin location,
// and owns all state + IPC. BarWidget reads state via FileView (never IPC).
Item {
  id: root
  property var manifest: null
  readonly property string pluginId: "omakase"

  readonly property string home: String(Quickshell.env("HOME"))
  readonly property string stateDir: home + "/.local/state/omakase"
  readonly property string statePath: stateDir + "/state.json"
  readonly property string journalPath: stateDir + "/journal.json"
  readonly property string userSpotsPath: stateDir + "/user_spots.json"
  readonly property string undoPath: stateDir + "/undo.json"
  readonly property string sourceDir: manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : home + "/.config/omarchy/plugins/" + pluginId

  property double homeLat: 0
  property double homeLon: 0
  // Coordinates last written to state.json — the baseline reconcileLocation
  // compares each fresh weather read against, so an unchanged home never burns
  // a ~1.9 MB rewrite.
  property double persistedHomeLat: 0
  property double persistedHomeLon: 0
  // The catalog is in memory this session (seeded from data/*.jsonl, or reloaded
  // from an existing state.json). Gates location rewrites so startup can never
  // persist an empty catalog over a valid state.json.
  property bool catalogLoaded: false
  // The weather.json location has been read at least once, so homeLat/homeLon
  // are authoritative rather than still at their 0 defaults.
  property bool locationApplied: false
  property var cities: []
  property var spotsByCity: Object.create(null)   // city -> [{name, courses, price, ...}]
  property var userSpots: []       // user-added spots (same fields + city)
  property var journal: []         // rated spots
  property var undoSnapshot: null
  // token (lowercase, non-alphanumerics stripped) -> catalog slug, rebuilt from
  // the loaded city keys so cityKeyFor() can canonicalize free-form city strings.
  property var cityAliases: Object.create(null)

  // IPC input caps + undo window. rate/unrate truncate user input to these
  // lengths; undo only replays snapshots younger than undoWindowMs.
  readonly property int maxNameLen: 256
  readonly property int maxNotesLen: 2000
  readonly property int maxCityLen: 100
  readonly property int undoWindowMs: 5 * 60 * 1000

  // Chunked seed-parse config. The seed loader emits `city\tjson` lines on
  // stdout; parsing them all in one synchronous onExited handler blocked IPC
  // for the duration of a slow first-run/refresh, so the parse runs in
  // seedParseChunkSize-line slices, one per event-loop turn (Qt.callLater).
  readonly property int seedParseChunkSize: 400
  // $0 handed to the bash loader so its own diagnostics name the command.
  readonly property string seedLoaderArgv0: "seed-loader"
  property int seedParseToken: 0 // discards a superseded parse on a second refresh

  // Shared chunked-walk scaffold (components/ChunkedWalk.qml), imported by both
  // Service and BarWidget so the two processes share one token/chunk/reschedule/
  // publish implementation. The seed parse below is one bounded walk.
  ChunkedWalk { id: chunkWalk }

  // Subset of fields BarWidget actually reads — keeps state.json lean.
  readonly property var persistedSpotFields: ["name", "lat", "lon", "neighborhood", "website",
              "phone", "price", "courses", "currency",
              "time", "discount", "yelp_url",
              "state", "image_url", "is_closed",
              "yelp_rating", "yelp_review_count", "yelp_price", "country",
              "transactions", "address", "display_address"]

  Process {
    id: seedLoader
    // sourceDir is passed as argv ($1) so bash treats it literally — a HOME
    // containing a space or shell metacharacter can no longer break or inject.
    command: ["bash", "-c", "for f in \"$1\"/data/*.jsonl; do city=$(basename \"$f\" .jsonl); while IFS= read -r line; do [ -n \"$line\" ] && printf '%s\\t%s\\n' \"$city\" \"$line\"; done < \"$f\"; done", root.seedLoaderArgv0, root.sourceDir]
    stdout: StdioCollector { id: seedStdout; waitForEnd: true }
    stderr: StdioCollector { id: seedStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        console.warn("seed loader failed exit=" + exitCode, String(seedStderr.text || ""));
        return;
      }
      var text = String(seedStdout.text || "");
      if (!text) return;
      // Capture the output once (a refresh run resets seedStdout.text) and hand
      // the line array to the chunked parser; the per-line JSON.parse is what's
      // expensive, so the parse — not the split — is what gets chunked.
      root.seedParseToken++;
      var ctx = {
        index: 0,
        lines: text.split("\n"),
        citiesSet: Object.create(null),
        newSpots: Object.create(null)
      };
      chunkWalk.runChunked({
        getToken: function () { return root.seedParseToken; },
        chunkSize: root.seedParseChunkSize,
        ctx: ctx,
        step: function (ctx) {
          var line = ctx.lines[ctx.index];
          var tabIndex = line.indexOf("\t");
          if (tabIndex >= 0) {
            var city = line.slice(0, tabIndex).trim().toLowerCase();
            var rawJson = line.slice(tabIndex + 1);
            try {
              var entry = JSON.parse(rawJson);
              if (entry && entry.name) {
                // The file stem is the only city key: the entry `city` field is
                // no longer consulted, so a spot always lands under its file.
                if (!ctx.newSpots[city]) ctx.newSpots[city] = [];
                ctx.newSpots[city].push(entry);
                ctx.citiesSet[city] = true;
              }
            } catch (_) {
              // Malformed JSONL lines are silently skipped.
            }
          }
          ctx.index++;
          return { processed: 1, more: ctx.index < ctx.lines.length };
        },
        done: function (ctx) {
          root.cities = Object.keys(ctx.citiesSet).sort();
          root.spotsByCity = ctx.newSpots;
          root.rebuildCityAliases();
          root.catalogLoaded = true;
          root.writeState();
        }
      }, root.seedParseToken);
    }
  }

  FileView {
    id: journalFile
    path: root.journalPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadJournal(text())
    onLoadFailed: root.loadJournal("")
    onFileChanged: reload()
    // The journal holds personal rating notes, so lock it to owner-only after
    // every write. Fired post-save (after the atomic rename) so the chmod can't
    // race the write.
    onSaved: Quickshell.execDetached(["chmod", "600", root.journalPath])
  }

  FileView {
    path: root.userSpotsPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadUserSpots(text())
    onLoadFailed: root.loadUserSpots("")
    onFileChanged: reload()
  }

  FileView {
    id: undoFile
    path: root.undoPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadUndo(text())
    onLoadFailed: root.loadUndo("")
    onFileChanged: reload()
    // undo.json snapshots the whole journal (spot names + up to 2000-char
    // notes) and persists past the 5-minute window, so lock it owner-only
    // after every write — same post-rename timing as journalFile.
    onSaved: Quickshell.execDetached(["chmod", "600", root.undoPath])
  }

  FileView {
    path: root.home + "/.local/state/omarchy/settings/weather.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadLocation(text())
    onLoadFailed: root.loadLocation("")
    onFileChanged: reload()
  }

  // The service is the only writer of state.json, so there is no
  // watchChanges/onFileChanged — reloading our own writes is pointless. Its
  // startup preload doubles as a catalog load: onLoaded restores the existing
  // catalog + persisted coordinates (without re-seeding) so a later home move can
  // be rewritten; a missing or empty state still triggers the seed loader.
  FileView {
    id: stateFile
    path: root.statePath
    atomicWrites: true
    printErrors: false
    onLoadFailed: seedLoader.running = true
    onLoaded: root.loadState(text())
  }

  Component.onCompleted: {
    Quickshell.execDetached(["mkdir", "-p", "-m", "700", stateDir]);
    // mkdir's -m applies only to a newly created dir; tighten a pre-existing
    // stateDir explicitly (idempotent, safe to race the mkdir).
    Quickshell.execDetached(["chmod", "700", stateDir]);
    // Don't start the seed loader here: an existing state.json is already
    // correct, and re-deriving + re-serializing ~1.9 MB on every restart is
    // pure waste. First run (onLoadFailed) and `refresh` still run the loader.
  }

  function loadJournal(raw) {
    root.journal = SpotUtils.parseJson(raw, []);
    root.dedupeJournal();
  }
  function loadUserSpots(raw) {
    // user_spots.json is user/tool-writable, so a top-level JSON object (or any
    // non-array) could otherwise leave root.userSpots non-array and make the
    // next writeState throw on .forEach, breaking state persistence. The same
    // Array.isArray guard loadState applies to a per-city value.
    var parsed = SpotUtils.parseJson(raw, []);
    root.userSpots = Array.isArray(parsed) ? parsed : [];
  }

  // Lowercase a city key/name and strip non-alphanumerics to its alias token:
  // "Los Angeles" and "los-angeles" both reduce to "losangeles". Shared by
  // rebuildCityAliases (map keys) and cityKeyFor (lookup keys) so the two can
  // never drift apart.
  function tokenize(s) {
    return String(s).trim().toLowerCase().replace(/[^a-z0-9]/g, "");
  }

  // Rebuild the token -> catalog-slug alias map from the loaded city keys plus a
  // few curated display-name aliases the token can't derive. Called whenever the
  // catalog loads (seed parse or state.json), so cityKeyFor() has slugs for the
  // current catalog.
  function rebuildCityAliases() {
    var map = Object.create(null);
    var keys = root.cities || [];
    for (var i = 0; i < keys.length; i++) {
      var token = tokenize(keys[i]);
      if (token) map[token] = keys[i];
    }
    // Curated aliases for display names that don't re-spell their slug.
    map["newyork"] = "nyc";       // "New York" / "new york" (the nyc key's display name)
    map["newyorkcity"] = "nyc";   // "New York City"
    map["sopaulo"] = "sao-paulo"; // "São Paulo" (accent stripped by tokenization)
    root.cityAliases = map;
  }

  // Load an existing state.json back into memory, skipping the seed loader
  // (the state is already correct) while restoring the catalog + persisted
  // coordinates so a later home move can be rewritten in place.
  function loadState(raw) {
    var state = SpotUtils.parseJson(raw, {});
    if (!state || typeof state.spotsByCity !== "object" || Array.isArray(state.spotsByCity)) {
      // Missing, empty, malformed, or wrong-shaped state — rebuild from seed
      // data. The old falsy-only guard let a spotsByCity that is a string,
      // array, or number through, which then threw in the re-sanitize below
      // (Object.keys / .map) and left catalogLoaded false with no reseed — an
      // empty widget until state.json was deleted. Treat a shape failure the
      // same as a load failure so the seed loader re-runs and rewrites state.
      seedLoader.running = true;
      return;
    }
    // Re-sanitize every restored spot through the persistedSpotFields
    // whitelist: state.json lives outside the plugin dir and is
    // user/tool-writable, so a tampered file could otherwise carry arbitrary
    // fields into memory. writeState sanitizes on the way out; this closes
    // the read path too. One pass over the catalog (mirrors writeState's
    // map), added on top of the ~1.9 MB JSON.parse that already dominates
    // this synchronous load. A city value that is not an array (a stray
    // string/number/object/null) is treated as empty rather than throwing on
    // `.map`; sanitizeSpot handles a null/non-object element inside an array.
    root.spotsByCity = Object.keys(state.spotsByCity).reduce(function (byCity, city) {
      var citySpots = state.spotsByCity[city];
      byCity[city] = Array.isArray(citySpots)
        ? citySpots.map(function (spot) { return root.sanitizeSpot(spot); })
        : [];
      return byCity;
    }, Object.create(null));
    root.cities = Array.isArray(state.cities) ? state.cities : Object.keys(state.spotsByCity).sort();
    root.rebuildCityAliases();
    root.persistedHomeLat = typeof state.homeLat === "number" ? state.homeLat : 0;
    root.persistedHomeLon = typeof state.homeLon === "number" ? state.homeLon : 0;
    root.catalogLoaded = true;
    root.reconcileLocation();
  }

  function loadLocation(raw) {
    var location = SpotUtils.parseJson(raw, {});
    root.homeLat = parseFloat(location.latitude) || 0;
    root.homeLon = parseFloat(location.longitude) || 0;
    root.locationApplied = true;
    root.reconcileLocation();
  }

  // Rewrite state.json only when the home actually moved AND both the catalog
  // and the weather location are known. Fired from both loadLocation (live
  // weather changes) and loadState (startup), so the decision is independent of
  // which file loads first.
  function reconcileLocation() {
    if (!root.catalogLoaded || !root.locationApplied) return;
    if (root.homeLat !== root.persistedHomeLat || root.homeLon !== root.persistedHomeLon) {
      root.writeState();
    }
  }

  function loadUndo(text) { root.undoSnapshot = SpotUtils.parseJson(text, null); }

  // Drop every field not in persistedSpotFields, so an unknown/injected field a
  // user_spots.json entry carries can't survive into state.json.
  function sanitizeSpot(spot) {
    // A non-object entry (null from a truncated/corrupt file, or a stray
    // string/number/array) carries no spot fields — reduce it to an empty
    // object rather than throwing on the field read.
    if (!spot || typeof spot !== "object" || Array.isArray(spot)) return {};
    return root.persistedSpotFields.reduce(function (kept, field) {
      if (spot[field] !== undefined && spot[field] !== null) kept[field] = spot[field];
      return kept;
    }, {});
  }

  function writeState() {
    // root.spotsByCity may already contain merged user spots: loadState
    // restores it wholesale from a state.json that writeState had written with
    // the user spots appended. Re-appending root.userSpots would therefore
    // duplicate one copy per write. Dedup by normalized name within each city:
    // drop any existing entry whose name matches a current user spot, then
    // append the current user spots, so the user's latest edit always wins over
    // the stale merged copy still sitting in spotsByCity.
    var userNamesByCity = Object.create(null);
    root.userSpots.forEach(function (userSpot) {
      var city = String(userSpot.city || "").trim().toLowerCase();
      if (!userNamesByCity[city]) userNamesByCity[city] = Object.create(null);
      var name = SpotUtils.normalizeName(userSpot.name);
      if (name) userNamesByCity[city][name] = true;
    });
    var allCitySpots = Object.keys(root.spotsByCity).reduce(function (byCity, city) {
      var userNames = userNamesByCity[city];
      byCity[city] = (root.spotsByCity[city] || []).filter(function (spot) {
        return !(userNames && userNames[SpotUtils.normalizeName(spot && spot.name)]);
      }).map(function (spot) { return root.sanitizeSpot(spot); });
      return byCity;
    }, Object.create(null));
    root.userSpots.forEach(function (userSpot) {
      var city = String(userSpot.city || "").trim().toLowerCase();
      if (!allCitySpots[city]) allCitySpots[city] = [];
      allCitySpots[city].push(root.sanitizeSpot(userSpot));
    });
    stateFile.setText(JSON.stringify({
      updatedAt: Date.now(),
      cities: Object.keys(allCitySpots).sort(),
      spotsByCity: allCitySpots,
      homeLat: root.homeLat,
      homeLon: root.homeLon
    }));
    root.persistedHomeLat = root.homeLat;
    root.persistedHomeLon = root.homeLon;
  }

  function writeJournal() {
    journalFile.setText(JSON.stringify(root.journal));
  }

  // One-time normalization: collapse duplicate journal entries that resolve to
  // the same spot (via journalSpotKey) down to one, keeping the newest entry and
  // its rating/notes. Runs on every journal load and is idempotent — a clean
  // journal passes through unchanged and rewrites only when something was
  // merged. Returns the number of dropped entries.
  function dedupeJournal() {
    var entries = root.journal;
    if (!Array.isArray(entries) || entries.length < 2) return 0;
    // key -> newest matching entry object (ties keep the later, higher index).
    var newest = Object.create(null);
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i];
      if (!entry || typeof entry !== "object") continue;
      var key = journalSpotKey(entry);
      if (!key) continue;
      var current = newest[key];
      if (current === undefined || (Number(entry.timestamp) || 0) >= (Number(current.timestamp) || 0)) {
        newest[key] = entry;
      }
    }
    var kept = [];
    var mergedNames = [];
    var merged = 0;
    for (var j = 0; j < entries.length; j++) {
      var e = entries[j];
      if (!e || typeof e !== "object") { kept.push(e); continue; }
      var k = journalSpotKey(e);
      if (!k || e === newest[k]) { kept.push(e); continue; }
      merged++;
      mergedNames.push(e.name);
    }
    if (merged > 0) {
      root.journal = kept;
      root.writeJournal();
      console.log("omakase: deduplicated journal — merged " + merged + " duplicate entries: " + mergedNames.join(", "));
    }
    return merged;
  }

  // --- Journal identity ---
  //
  // A spot's journal identity is its normalized name (trim + lowercase). The
  // stored `city` field is unreliable metadata: older data stored free-form
  // strings ("new york", "flushing") while the UI now passes the catalog slug
  // ("nyc"). Matching is therefore name-first; city only disambiguates
  // same-named spots when both sides canonicalize to a known catalog slug.
  // A city that can't be canonicalized ("flushing") falls back to name-only
  // matching — the documented tradeoff: two distinct spots that share a name AND
  // at least one un-mappable city are treated as one, which is strictly better
  // than silently duplicating a rating.

  // Canonical catalog slug for a city string, or "" when it can't be reduced to
  // a known city. Case/whitespace/punctuation are normalized so "Los Angeles"
  // and "los-angeles" both resolve to "los-angeles"; a small curated alias map
  // (in rebuildCityAliases) bridges display-name cases the token alone can't
  // ("new york" -> "nyc").
  function cityKeyFor(city) {
    if (city == null) return "";
    var token = tokenize(city);
    return token ? (root.cityAliases[token] || "") : "";
  }

  // Dedup key for a journal entry: normalized name plus the canonical city when
  // one resolves. Entries whose city can't be canonicalized key on name alone,
  // mirroring findJournalIndex's name-first fallback.
  function journalSpotKey(entry) {
    var name = SpotUtils.normalizeName(entry && entry.name);
    if (!name) return "";
    var cityKey = cityKeyFor(entry && entry.city);
    return cityKey ? name + "\u0000" + cityKey : name;
  }

  function findJournalIndex(name, city) {
    var normalizedName = SpotUtils.normalizeName(name);
    if (!normalizedName) return -1;
    var lookupCityKey = cityKeyFor(city);
    var fallbackIndex = -1;
    for (var index = root.journal.length - 1; index >= 0; index--) {
      var entry = root.journal[index];
      if (SpotUtils.normalizeName(entry && entry.name) !== normalizedName) continue;
      // No lookup city -> wildcard: the newest name match wins.
      if (!lookupCityKey) return index;
      var entryCityKey = cityKeyFor(entry && entry.city);
      if (!entryCityKey) {
        // Entry city can't be canonicalized ("flushing") — remember the newest
        // name-only match as a fallback, then keep scanning for an exact city.
        if (fallbackIndex < 0) fallbackIndex = index;
        continue;
      }
      if (entryCityKey === lookupCityKey) return index;
    }
    // No exact city match: fall back to the newest name-only match.
    return fallbackIndex;
  }

  // Snapshot the journal into undo.json before any mutation so `undo` can
  // restore the pre-edit journal within undoWindowMs.
  function saveUndoSnapshot() {
    root.undoSnapshot = { snapshot: root.journal.slice(), at: Date.now() };
    undoFile.setText(JSON.stringify(root.undoSnapshot));
  }

  IpcHandler {
    target: root.pluginId

    function ping(): string { return "ok" }

    function refresh(): string {
      seedLoader.running = true;
      return "ok";
    }

    function rate(name: string, rating: string, notes: string, city: string): string {
      name = (name || "").slice(0, root.maxNameLen);
      var ratingValue = parseInt(rating, 10) || 0;
      notes = (notes || "").slice(0, root.maxNotesLen);
      city = String(city || "").trim().toLowerCase().slice(0, root.maxCityLen);
      if (!name || ratingValue < 1 || ratingValue > 5) return JSON.stringify({ ok: false, error: "usage: rate <name> <1-5> [notes] [city]" });
      var journalIndex = root.findJournalIndex(name, city);
      root.saveUndoSnapshot();
      if (journalIndex >= 0) {
        root.journal[journalIndex].rating = ratingValue;
        root.journal[journalIndex].notes = notes;
        root.journal[journalIndex].timestamp = Date.now();
        if (city) root.journal[journalIndex].city = city;
      } else {
        root.journal.push({ timestamp: Date.now(), name: name, rating: ratingValue, notes: notes, city: city });
      }
      root.writeJournal();
      return JSON.stringify({ ok: true, data: "ok" });
    }

    function undo(): string {
      // Validate before replaying. undo.json lives outside the plugin dir and
      // is user/tool-writable, so a crafted file could carry a non-array
      // snapshot or a non-numeric `at` (NaN > window is false — the window is
      // skipped) and inject arbitrary journal entries that rate() would reject;
      // a snapshot-less file would set the journal to undefined and wipe it on
      // the next write. Reject anything the write path (saveUndoSnapshot) could
      // not have produced and leave the journal untouched on failure.
      var snapshot = root.undoSnapshot;
      if (!snapshot || typeof snapshot !== "object" || !Array.isArray(snapshot.snapshot) ||
          !Number.isFinite(snapshot.at) || (Date.now() - snapshot.at) > root.undoWindowMs)
        return JSON.stringify({ ok: false, error: "nothing to undo" });
      root.journal = snapshot.snapshot;
      root.undoSnapshot = null;
      // Re-normalize so undoing a pre-dedup snapshot can't reintroduce duplicates.
      root.dedupeJournal();
      root.writeJournal();
      undoFile.setText("");
      return JSON.stringify({ ok: true, data: "ok" });
    }

    function unrate(name: string, city: string): string {
      name = (name || "").slice(0, root.maxNameLen);
      city = String(city || "").trim().toLowerCase().slice(0, root.maxCityLen);
      if (!name) return JSON.stringify({ ok: false, error: "usage: unrate <name> [city]" });
      var journalIndex = root.findJournalIndex(name, city);
      if (journalIndex < 0) return JSON.stringify({ ok: false, error: "no rating found" });
      root.saveUndoSnapshot();
      root.journal.splice(journalIndex, 1);
      root.writeJournal();
      return JSON.stringify({ ok: true, data: "ok" });
    }
  }
}
