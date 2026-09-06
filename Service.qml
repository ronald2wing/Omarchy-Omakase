import QtQuick
import Quickshell
import Quickshell.Io
import "spot-utils.js" as SpotUtils
import "journal-identity.js" as JournalIdentity
import "components"

// Omakase — worldwide sushi directory.
// Service kind: loads seed data, watches the weather-plugin location,
// and owns all state + IPC. BarWidget reads state via FileView (never IPC).
Item {
  id: root
  property var manifest: null
  readonly property string pluginId: "omakase"

  readonly property string homeDir: String(Quickshell.env("HOME"))
  readonly property string stateDir: homeDir + "/.local/state/omakase"
  readonly property string statePath: stateDir + "/state.json"
  readonly property string journalPath: stateDir + "/journal.json"
  readonly property string userSpotsPath: stateDir + "/user_spots.json"
  readonly property string undoPath: stateDir + "/undo.json"
  readonly property string sourceDir: manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : homeDir + "/.config/omarchy/plugins/" + pluginId

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
  property var spotsByCity: Object.create(null)   // city -> [spot]
  property var userSpots: []       // user-added spots (same fields + city)
  property var journal: []         // rated spots
  property var undoSnapshot: null
  // token (lowercase, non-alphanumerics stripped) -> catalog slug, rebuilt from
  // the loaded city keys plus a few curated display-name aliases (newyork,
  // newyorkcity, sopaulo) so canonicalCityKey() can canonicalize free-form city
  // strings.
  property var cityAliases: Object.create(null)

  // IPC input caps + undo window. rate/unrate truncate user input to these
  // lengths; undo only replays snapshots younger than undoWindowMs.
  readonly property int maxNameLen: 256
  readonly property int maxNotesLen: 2000
  readonly property int maxCityLen: 100
  readonly property int undoWindowMs: 5 * 60 * 1000

  // Subset of fields BarWidget actually reads — keeps state.json lean. Derived
  // from SpotUtils.spotFieldTypes (one source of truth for the field set): the
  // map's insertion order is the field order written into state.json.
  readonly property var persistedSpotFields: Object.keys(SpotUtils.spotFieldTypes)

  // Headless seed loader (components/SeedLoader.qml): shells out to bash to
  // emit `city\tjson` lines from data/*.jsonl and parses them in chunked
  // slices. `loaded` hands back the parsed catalog; this handler owns the state
  // writes (cities, cityAliases, catalogLoaded, writeState).
  SeedLoader {
    id: seedLoader
    sourceDir: root.sourceDir
    onLoaded: function(spotsByCity) {
      root.cities = Object.keys(spotsByCity).sort();
      root.spotsByCity = spotsByCity;
      root.rebuildCityAliases();
      root.catalogLoaded = true;
      root.writeState();
    }
  }

  StateFile {
    id: journalFile
    path: root.journalPath
    atomicWrites: true
    onParsed: function(content) { root.loadJournal(content) }
    onMissing: root.loadJournal("")
    // The journal holds personal rating notes, so lock it to owner-only after
    // every write. Fired post-save (after the atomic rename) so the chmod can't
    // race the write.
    onSaved: root.lockOwnerOnly(root.journalPath)
  }

  StateFile {
    path: root.userSpotsPath
    atomicWrites: true
    onParsed: function(content) { root.loadUserSpots(content) }
    onMissing: root.loadUserSpots("")
  }

  StateFile {
    id: undoFile
    path: root.undoPath
    atomicWrites: true
    onParsed: function(content) { root.loadUndo(content) }
    onMissing: root.loadUndo("")
    // undo.json snapshots the whole journal (spot names + up to 2000-char
    // notes) and persists past the 5-minute window, so lock it owner-only
    // after every write — same post-rename timing as journalFile.
    onSaved: root.lockOwnerOnly(root.undoPath)
  }

  FileView {
    path: root.homeDir + "/.local/state/omarchy/settings/weather.json"
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
    onLoadFailed: seedLoader.start()
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

  // Lock a personal-data file to owner-only (chmod 600). journal.json (personal
  // rating notes) and undo.json (a snapshot of the whole journal) both call this
  // from their FileView onSaved, post-rename, so the chmod can't race the write.
  function lockOwnerOnly(path) {
    Quickshell.execDetached(["chmod", "600", path]);
  }

  function loadJournal(raw) {
    // journal.json is user/tool-writable; a non-array here would make rate()/
    // unrate() throw on .push/.splice/.length. SpotUtils.parseJsonArray's
    // Array.isArray guard degrades a top-level object to [].
    root.journal = SpotUtils.parseJsonArray(raw);
    root.dedupeJournal();
  }
  function loadUserSpots(raw) {
    // user_spots.json is user/tool-writable; a non-array here would make the
    // next writeState throw on .forEach, breaking state persistence.
    // SpotUtils.parseJsonArray's Array.isArray guard degrades a top-level
    // object to [].
    root.userSpots = SpotUtils.parseJsonArray(raw);
  }

  // Rebuild the token -> catalog-slug alias map from the loaded city keys plus a
  // few curated display-name aliases (newyork, newyorkcity, sopaulo) so
  // canonicalCityKey() has slugs for the current catalog. The map itself is built
  // by JournalIdentity.buildCityAliases; this wrapper only owns the root.cityAliases
  // assignment. Called whenever the catalog loads (seed parse or state.json).
  function rebuildCityAliases() {
    root.cityAliases = JournalIdentity.buildCityAliases(root.cities);
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
      seedLoader.start();
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
    var lat = parseFloat(location.latitude);
    var lon = parseFloat(location.longitude);
    // A genuine (0,0) home is a valid coordinate (hasCoords), so only a
    // non-finite parse (a missing/garbled latitude) folds to 0 — never a real
    // zero. `|| 0` would treat the two identically and never persist an
    // equator home.
    root.homeLat = Number.isFinite(lat) ? lat : 0;
    root.homeLon = Number.isFinite(lon) ? lon : 0;
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

  function loadUndo(raw) { root.undoSnapshot = SpotUtils.parseJson(raw, null); }

  // Drop every field not in persistedSpotFields, so an unknown/injected field a
  // user_spots.json entry carries can't survive into state.json. Kept fields are
  // also coerced to their correct type (see SpotUtils.coerceSpotField), so a
  // wrong-typed value (price: 123, transactions: "delivery") can't reach the bar
  // widget, whose formatters assume strings/arrays/numbers and throw otherwise.
  function sanitizeSpot(spot) {
    // A non-object entry (null from a truncated/corrupt file, or a stray
    // string/number/array) carries no spot fields — reduce it to an empty
    // object rather than throwing on the field read.
    if (!spot || typeof spot !== "object" || Array.isArray(spot)) return {};
    return root.persistedSpotFields.reduce(function (kept, field) {
      var value = spot[field];
      if (value === undefined || value === null) return kept;
      var coerced = SpotUtils.coerceSpotField(field, value);
      if (coerced !== undefined) kept[field] = coerced;
      return kept;
    }, {});
  }

  // Coerce one undo snapshot entry to a valid journal entry, or return null
  // when it can't form one. undo.json is user/tool-writable, so `undo`
  // reinstalls the snapshot through this rather than verbatim: name/notes/city
  // are coerced to strings and capped, and rating is parsed to 1..5 — the same
  // coerce + cap the rate() path applies — so a crafted file can't inject an
  // over-long name/notes or an out-of-range rating straight into root.journal.
  // Any entry that fails (a non-object element, an empty name, or a rating
  // outside 1..5) is dropped rather than installed malformed.
  function sanitizeJournalEntry(entry) {
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) return null;
    var name = String(entry.name == null ? "" : entry.name).slice(0, root.maxNameLen);
    var notes = String(entry.notes == null ? "" : entry.notes).slice(0, root.maxNotesLen);
    var city = SpotUtils.normalizeName(entry.city).slice(0, root.maxCityLen);
    var rating = parseInt(entry.rating, 10) || 0;
    if (!name || rating < 1 || rating > 5) return null;
    return { timestamp: entry.timestamp, name: name, rating: rating, notes: notes, city: city };
  }

  function writeState() {
    // root.spotsByCity may already contain merged user spots: loadState
    // restores it wholesale from a state.json that writeState had written with
    // the user spots appended. Re-appending root.userSpots would therefore
    // duplicate one copy per write. JournalIdentity.mergeUserSpots dedups by
    // normalized name within each city — dropping any existing entry whose name
    // matches a current user spot, then appending the current user spots — so
    // the user's latest edit always wins over the stale merged copy still
    // sitting in spotsByCity. Serialization stays here.
    var allCitySpots = JournalIdentity.mergeUserSpots(root.spotsByCity, root.userSpots, root.sanitizeSpot);
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
  // merged. The single-pass newest-wins dedupe lives in
  // JournalIdentity.dedupeJournalEntries; this wrapper owns the root.journal
  // assignment + rewrite.
  function dedupeJournal() {
    var result = JournalIdentity.dedupeJournalEntries(root.journal, root.cityAliases);
    if (result.merged === 0) return;
    root.journal = result.entries;
    root.writeJournal();
  }

  // --- Journal identity ---
  //
  // A spot's journal identity is its normalized name (trim + lowercase). The
  // stored `city` field is unreliable metadata: older data stored free-form
  // strings ("new york", "flushing") while the UI now passes the catalog slug
  // ("nyc"). Matching is therefore name-first; city only disambiguates
  // same-named spots when both sides canonicalize to a known catalog slug. The
  // canonicalization (cityAliasToken/canonicalCityKey/journalSpotKey) and the
  // name-first lookup live in JournalIdentity; this wrapper supplies root.journal
  // and root.cityAliases.

  function findJournalIndex(name, city) {
    return JournalIdentity.findJournalIndex(root.journal, name, city, root.cityAliases);
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
      seedLoader.start();
      return "ok";
    }

    function rate(name: string, rating: string, notes: string, city: string): string {
      name = (name || "").slice(0, root.maxNameLen);
      city = SpotUtils.normalizeName(city || "").slice(0, root.maxCityLen);
      var ratingValue = parseInt(rating, 10) || 0;
      notes = (notes || "").slice(0, root.maxNotesLen);
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
        return JSON.stringify({ ok: false, error: "nothing to undo (no valid snapshot within the last 5 minutes)" });
      root.journal = snapshot.snapshot.map(function (entry) { return root.sanitizeJournalEntry(entry); }).filter(Boolean);
      root.undoSnapshot = null;
      // Re-normalize so undoing a pre-dedup snapshot can't reintroduce duplicates.
      root.dedupeJournal();
      root.writeJournal();
      undoFile.setText("");
      return JSON.stringify({ ok: true, data: "ok" });
    }

    function unrate(name: string, city: string): string {
      name = (name || "").slice(0, root.maxNameLen);
      city = SpotUtils.normalizeName(city || "").slice(0, root.maxCityLen);
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
