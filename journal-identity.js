// journal-identity.js — Omakase journal identity + user-spot merge logic
// Dual-use: Node.js (tests) and QML (import "journal-identity.js" as
// JournalIdentity)
//
// Extracted from Service.qml's journal-identity cluster (alias canonicalization,
// name-first journal matching, newest-wins dedupe) plus writeState's user-spot
// merge. Every function is pure: inputs are passed explicitly (no root.* reads),
// so they are unit-testable under Node and reusable verbatim from QML. The
// side-effecting orchestration (assigning root.cityAliases / root.journal,
// serializing state.json) stays in Service.qml.

// normalizeName comes from spot-utils.js (shared with Service.qml/BarWidget.qml).
// In Node this file requires it; in QML the bare `SpotUtils` identifier resolves
// to the importing document's `import "spot-utils.js" as SpotUtils` qualifier
// (Service.qml imports both files). The identifier is deliberately not declared
// with `var`: a local declaration would shadow the QML qualifier with null.
// Every `SpotUtils` read sits lazily inside a function body, so the document is
// fully initialized before the first call regardless of import order.
if (typeof module !== "undefined" && module.exports) {
  SpotUtils = require("./spot-utils.js");
}

// ---- Alias canonicalization ----

// Lowercase a city key/name and strip non-alphanumerics to its alias token:
// "Los Angeles" and "los-angeles" both reduce to "losangeles". Shared by
// buildCityAliases (map keys) and canonicalCityKey (lookup keys) so the two can
// never drift apart. Strips non-ASCII on purpose (city keys are ASCII slugs);
// spot-utils' normalizeAyceText keeps CJK so "食べ放題" survives — do not merge.
function cityAliasToken(s) {
  return String(s).trim().toLowerCase().replace(/[^a-z0-9]/g, "");
}

// Build the token -> catalog-slug alias map from the loaded city keys plus a few
// curated display-name aliases the token can't derive. Called whenever the
// catalog loads (seed parse or state.json), so canonicalCityKey() has slugs for
// the current catalog.
function buildCityAliases(cities) {
  var map = Object.create(null);
  var keys = cities || [];
  for (var i = 0; i < keys.length; i++) {
    var token = cityAliasToken(keys[i]);
    if (token) map[token] = keys[i];
  }
  // Curated aliases for display names that don't re-spell their slug.
  map["newyork"] = "nyc";       // "New York" / "new york" (the nyc key's display name)
  map["newyorkcity"] = "nyc";   // "New York City"
  map["sopaulo"] = "sao-paulo"; // "São Paulo" (accent stripped by tokenization)
  return map;
}

// Canonical catalog slug for a city string, or "" when it can't be reduced to
// a known city. Case/whitespace/punctuation are normalized so "Los Angeles"
// and "los-angeles" both resolve to "los-angeles"; a small curated alias map
// (in buildCityAliases) bridges display-name cases the token alone can't
// ("new york" -> "nyc").
function canonicalCityKey(city, cityAliases) {
  if (city == null) return "";
  var token = cityAliasToken(city);
  return token ? (cityAliases[token] || "") : "";
}

// ---- Journal identity ----
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

// The single producer of the journal-entry shape: coerce one entry (from rate()
// or an undo snapshot replay) to { timestamp, name, rating, notes, city } —
// name/notes stringified and capped to the caller's length caps, city normalized
// and capped, rating parsed to 1..5 — or null when it can't form one (a
// non-object element, an empty name, or a rating outside 1..5). Both paths write
// through this so a crafted value can't inject an over-long field or an
// out-of-range rating straight into root.journal.
function coerceJournalEntry(entry, caps) {
  if (!SpotUtils.isPlainObject(entry)) return null;
  var name = String(entry.name == null ? "" : entry.name).slice(0, caps.maxNameLen);
  var notes = String(entry.notes == null ? "" : entry.notes).slice(0, caps.maxNotesLen);
  var city = SpotUtils.normalizeName(entry.city).slice(0, caps.maxCityLen);
  var rating = parseInt(entry.rating, 10) || 0;
  if (!name || rating < 1 || rating > 5) return null;
  return { timestamp: entry.timestamp, name: name, rating: rating, notes: notes, city: city };
}

// Dedup key for a journal entry: normalized name plus the canonical city when
// one resolves. Entries whose city can't be canonicalized key on name alone,
// mirroring findJournalIndex's name-first fallback.
function journalSpotKey(entry, cityAliases) {
  var name = SpotUtils.normalizeName(entry && entry.name);
  if (!name) return "";
  var cityKey = canonicalCityKey(entry && entry.city, cityAliases);
  return cityKey ? name + "\u0000" + cityKey : name;
}

function findJournalIndex(journal, name, city, cityAliases) {
  var normalizedName = SpotUtils.normalizeName(name);
  if (!normalizedName) return -1;
  var lookupCityKey = canonicalCityKey(city, cityAliases);
  var fallbackIndex = -1;
  for (var index = journal.length - 1; index >= 0; index--) {
    var entry = journal[index];
    if (SpotUtils.normalizeName(entry && entry.name) !== normalizedName) continue;
    // No lookup city -> wildcard: the newest name match wins.
    if (!lookupCityKey) return index;
    var entryCityKey = canonicalCityKey(entry && entry.city, cityAliases);
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

// One-time normalization: collapse duplicate journal entries that resolve to
// the same spot (via journalSpotKey) down to one, keeping the newest entry and
// its rating/notes. Pure over the array it is given; returns { entries, merged }
// where `merged` is the number of collapsed duplicates (0 when the input passes
// through unchanged, which the caller detects to skip the rewrite). Idempotent —
// a clean journal passes through with merged 0.
function dedupeJournalEntries(entries, cityAliases) {
  if (!Array.isArray(entries) || entries.length < 2) return { entries: entries, merged: 0 };
  // One pass: compute each entry's key once and keep, per key, the newest
  // entry (ties keep the later index). keptFlags records each survivor's
  // original index — a superseded winner's flag is cleared — so the survivors
  // compact back into original order without a second key computation.
  var winners = Object.create(null); // key -> { entry, index }
  var keptFlags = new Array(entries.length);
  var merged = 0;
  for (var i = 0; i < entries.length; i++) {
    var entry = entries[i];
    if (!SpotUtils.isPlainObject(entry)) { keptFlags[i] = true; continue; }
    var key = journalSpotKey(entry, cityAliases);
    if (!key) { keptFlags[i] = true; continue; }
    var current = winners[key];
    if (current === undefined ||
        (Number(entry.timestamp) || 0) >= (Number(current.entry.timestamp) || 0)) {
      if (current !== undefined) { keptFlags[current.index] = false; merged++; }
      winners[key] = { entry: entry, index: i };
      keptFlags[i] = true;
    } else {
      merged++;
    }
  }
  if (merged === 0) return { entries: entries, merged: 0 };
  var kept = [];
  for (var j = 0; j < entries.length; j++) {
    if (keptFlags[j]) kept.push(entries[j]);
  }
  return { entries: kept, merged: merged };
}

// ---- Saved (wishlist) entry normalization ----
//
// The wishlist's journal-mirroring shape: a flat array of { name, city }
// objects, where `city` is the canonical catalog slug when resolvable and ""
// (the deliberate wildcard) when it is not. normalizeSavedEntries turns any
// input — legacy bare-string names, object entries with free-form city strings,
// or wrong-shaped elements — into that shape in memory, without writing. Every
// string method on a stored value is guarded with String()/typeof so a
// wrong-typed element can never throw inside a ChunkedWalk chunk (a throw there
// escapes before the Qt.callLater reschedule and silently kills the catalog).
//
// `resolveCity` is the optional name->canonical-city resolver; `null` means
// "normalize shape only, no resolution" (the write-free loadSaved pass). When a
// name resolves, `city` becomes the resolved slug and `changed` flips, so the
// caller can detect the migration wrote a resolution. Idempotent: canonical
// input yields `changed === false` and no rewrite.
function normalizeSavedEntries(entries, cityAliases, resolveCity) {
  if (!Array.isArray(entries)) return { entries: [], changed: false };
  var out = [], changed = false;
  for (var i = 0; i < entries.length; i++) {
    var raw = entries[i], name, city;
    if (typeof raw === "string") { name = raw; city = ""; changed = true; }
    else if (SpotUtils.isPlainObject(raw)) {
      name = SpotUtils.asString(raw.name);
      city = canonicalCityKey(raw.city, cityAliases);
      if (city !== SpotUtils.asString(raw.city)) changed = true;
    } else { changed = true; continue; }
    if (!name) { changed = true; continue; }
    if (!city && typeof resolveCity === "function") {
      var r = resolveCity(name);
      if (r) { city = r; changed = true; }
    }
    out.push({ name: name, city: city });
  }
  return { entries: out, changed: changed };
}

// ---- User-spot merge ----
//
// The pure core of writeState's user-spot merge: `spotsByCity` may already
// contain merged user spots (loadState restores it wholesale from a state.json
// writeState had written with the user spots appended), so re-appending
// `userSpots` would duplicate one copy per write. Dedup by normalized name
// within each city: drop any existing entry whose name matches a current user
// spot, then append the current user spots, so the user's latest edit always
// wins over the stale merged copy still sitting in spotsByCity. `sanitize` is
// injected (the caller passes Service.sanitizeSpot) so this stays pure; the
// caller owns serializing the returned map.

// Normalize each user spot's city + name once; the dedupe-map build and the
// append loop below both consume these, so neither re-normalizes per spot.
function mergeUserSpots(spotsByCity, userSpots, sanitize) {
  var normalizedUserSpots = userSpots.map(function (userSpot) {
    return {
      city: SpotUtils.normalizeName(userSpot.city || ""),
      name: SpotUtils.normalizeName(userSpot.name),
      spot: userSpot
    };
  });
  var userNamesByCity = Object.create(null);
  normalizedUserSpots.forEach(function (u) {
    if (!userNamesByCity[u.city]) userNamesByCity[u.city] = Object.create(null);
    if (u.name) userNamesByCity[u.city][u.name] = true;
  });
  var allCitySpots = Object.keys(spotsByCity).reduce(function (byCity, city) {
    var userNames = userNamesByCity[city];
    byCity[city] = (spotsByCity[city] || []).filter(function (spot) {
      return !(userNames && userNames[SpotUtils.normalizeName(spot && spot.name)]);
    }).map(function (spot) { return sanitize(spot); });
    return byCity;
  }, Object.create(null));
  normalizedUserSpots.forEach(function (u) {
    if (!allCitySpots[u.city]) allCitySpots[u.city] = [];
    allCitySpots[u.city].push(sanitize(u.spot));
  });
  return allCitySpots;
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    buildCityAliases,
    canonicalCityKey,
    journalSpotKey,
    coerceJournalEntry,
    findJournalIndex,
    dedupeJournalEntries,
    normalizeSavedEntries,
    mergeUserSpots
  };
}
