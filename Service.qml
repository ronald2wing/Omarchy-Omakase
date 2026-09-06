import QtQuick
import Quickshell
import Quickshell.Io
import "spot-utils.js" as SpotUtils
import "components"

// Omakase — worldwide omakase directory + review tracker.
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
  // a 2.8 MB rewrite.
  property double savedHomeLat: 0
  property double savedHomeLon: 0
  // The catalog is in memory this session (seeded from data/*.jsonl, or reloaded
  // from an existing state.json). Gates location rewrites so startup can never
  // persist an empty catalog over a valid state.json.
  property bool catalogLoaded: false
  // The weather.json location has been read at least once, so homeLat/homeLon
  // are authoritative rather than still at their 0 defaults.
  property bool locationApplied: false
  property var cities: []
  property var spots: Object.create(null)         // city -> [{name, courses, price, ...}]
  property var userSpots: []       // user-added spots (same fields + city)
  property var journal: []         // rated spots
  property var undoSnapshot: null

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
              "transactions", "display_address"]

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
                var entryCity = String(entry.city || "").trim().toLowerCase();
                if (entryCity) city = entryCity;
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
          root.spots = ctx.newSpots;
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
    id: userFile
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
    id: locationFile
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
  // catalog + saved coordinates (without re-seeding) so a later home move can
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
    // correct, and re-deriving + re-serializing ~2.8 MB on every restart is
    // pure waste. First run (onLoadFailed) and `refresh` still run the loader.
  }

  function loadJournal(raw) { root.journal = SpotUtils.parseJson(raw, []); }
  function loadUserSpots(raw) { root.userSpots = SpotUtils.parseJson(raw, []); }

  // Load an existing state.json back into memory, skipping the seed loader
  // (the state is already correct) while restoring the catalog + saved
  // coordinates so a later home move can be rewritten in place.
  function loadState(raw) {
    var state = SpotUtils.parseJson(raw, {});
    if (!state || !state.spotsByCity) {
      // Missing, empty, or malformed state — rebuild from seed data.
      seedLoader.running = true;
      return;
    }
    root.spots = state.spotsByCity;
    root.cities = Array.isArray(state.cities) ? state.cities : Object.keys(state.spotsByCity).sort();
    root.savedHomeLat = typeof state.homeLat === "number" ? state.homeLat : 0;
    root.savedHomeLon = typeof state.homeLon === "number" ? state.homeLon : 0;
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
    if (root.homeLat !== root.savedHomeLat || root.homeLon !== root.savedHomeLon) {
      root.writeState();
    }
  }

  function loadUndo(text) { root.undoSnapshot = SpotUtils.parseJson(text, null); }

  // Drop every field not in persistedSpotFields, so an unknown/injected field a
  // user_spots.json entry carries can't survive into state.json.
  function sanitizeSpot(spot) {
    return root.persistedSpotFields.reduce(function (kept, field) {
      if (spot[field] !== undefined && spot[field] !== null) kept[field] = spot[field];
      return kept;
    }, {});
  }

  function writeState() {
    var allCitySpots = Object.keys(root.spots).reduce(function (byCity, city) {
      byCity[city] = (root.spots[city] || []).map(function (spot) { return root.sanitizeSpot(spot); });
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
    root.savedHomeLat = root.homeLat;
    root.savedHomeLon = root.homeLon;
  }

  function writeJournal() {
    journalFile.setText(JSON.stringify(root.journal));
  }

  function findJournalIndex(name, city) {
    for (var index = root.journal.length - 1; index >= 0; index--) {
      if (root.journal[index].name === name && root.journal[index].city === city) return index;
    }
    return -1;
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
      if (!root.undoSnapshot || (Date.now() - root.undoSnapshot.at) > root.undoWindowMs)
        return JSON.stringify({ ok: false, error: "nothing to undo" });
      root.journal = root.undoSnapshot.snapshot;
      root.undoSnapshot = null;
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
