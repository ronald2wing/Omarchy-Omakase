// catalog-utils.js — Omakase catalog pure logic extracted from BarWidget.qml
// Dual-use: Node.js (tests) and QML (import "catalog-utils.js" as CatalogUtils)
//
// Every function here is pure: inputs are passed explicitly (no root.* reads),
// so they are unit-testable under Node and reusable verbatim from QML bindings
// without tracking issues. Side-effecting orchestration stays in BarWidget.qml.

// The accent-folding function lives in spot-utils.js (shared with Service.qml
// and BarWidget.qml). In Node this file requires it; in QML the bare `SpotUtils`
// identifier resolves to the importing document's `import "spot-utils.js" as
// SpotUtils` qualifier (BarWidget.qml imports both files) — the same seam
// quran's search.js uses to reach Quran.js. The identifier is deliberately not
// declared with `var`: a local declaration would shadow the QML qualifier with
// null. `foldSpot`/`rankSpots` read it lazily inside their bodies, so the
// document is fully initialized before the first call regardless of import order.
if (typeof module !== "undefined" && module.exports) {
  SpotUtils = require("./spot-utils.js");
}

// Shared separator between list segments ("City · State · Country"), and its
// folded/inline form ("· ") baked into a segment's leading text so it never
// renders alone. `var` (not `const`) so QML's import qualifier exposes them
// (const/let bindings are not visible as Qualifier.NAME).
var SEP = " · ";
var SEP_LEAD = "· ";

// The three sort keys the filter chip cycles through. Single source for
// FilterBar's sort control and the filterDescription summary so the key set
// and its labels (via sortLabelFor) can never drift apart.
var SORT_KEYS = ["distance", "rating", "price"];

// The radius filter's off/on cycle (km): off, then 5/10/20. Single source for
// FilterBar's Nearby pill so the step sequence lives in one place and
// nextRadiusStep computes the successor instead of a hand-rolled chain.
var RADIUS_STEPS = [0, 5, 10, 20];

// Next radius in the cycle (0 -> 5 -> 10 -> 20 -> 0). An unknown current value
// wraps to off (0) — the same result as the hand-rolled chain's final `else`.
function nextRadiusStep(current) {
  var index = RADIUS_STEPS.indexOf(current);
  return RADIUS_STEPS[(index + 1) % RADIUS_STEPS.length];
}

// ---- City metadata ----
// City key -> { name, lat, lon }. Keys are the data/*.jsonl filename stems —
// the file stem is the only city key (the entry `city` field is no longer
// consulted). `name` is the display name; `lat`/`lon` are the city-center
// coordinates used for the home-to-city distance display.
const CITY_META = {
  // Country-level key: australia.jsonl holds spots across Australia, not one
  // city. Coordinates are Sydney's, used as a representative anchor.
  "australia": { name: "Australia", lat: -33.8688, lon: 151.2093 },
  "bangkok": { name: "Bangkok", lat: 13.7563, lon: 100.5018 },
  "chicago": { name: "Chicago", lat: 41.8781, lon: -87.6298 },
  "dubai": { name: "Dubai", lat: 25.2048, lon: 55.2708 },
  "hong-kong": { name: "Hong Kong", lat: 22.3193, lon: 114.1694 },
  "kyoto": { name: "Kyoto", lat: 35.0116, lon: 135.7681 },
  "las-vegas": { name: "Las Vegas", lat: 36.1699, lon: -115.1398 },
  "london": { name: "London", lat: 51.5074, lon: -0.1278 },
  "los-angeles": { name: "Los Angeles", lat: 34.0522, lon: -118.2437 },
  "mexico-city": { name: "Mexico City", lat: 19.4326, lon: -99.1332 },
  "nyc": { name: "New York City", lat: 40.7128, lon: -74.0060 },
  "osaka": { name: "Osaka", lat: 34.6937, lon: 135.5023 },
  "paris": { name: "Paris", lat: 48.8566, lon: 2.3522 },
  "san-francisco": { name: "San Francisco", lat: 37.7749, lon: -122.4194 },
  "sao-paulo": { name: "São Paulo", lat: -23.5505, lon: -46.6333 },
  "seoul": { name: "Seoul", lat: 37.5665, lon: 126.9780 },
  "shanghai": { name: "Shanghai", lat: 31.2304, lon: 121.4737 },
  "singapore": { name: "Singapore", lat: 1.3521, lon: 103.8198 },
  "taipei": { name: "Taipei", lat: 25.0330, lon: 121.5654 },
  "tokyo": { name: "Tokyo", lat: 35.6762, lon: 139.6503 },
  "toronto": { name: "Toronto", lat: 43.6532, lon: -79.3832 },
  "vancouver": { name: "Vancouver", lat: 49.2827, lon: -123.1207 },
  "washington-dc": { name: "Washington DC", lat: 38.91, lon: -77.04 }
};

// Lookup a city key in CITY_META. Reads through hasOwnProperty so a city like
// "constructor" can never resolve to an Object.prototype member. Returns null
// for unknown keys.
function cityMetaFor(key) {
  return Object.prototype.hasOwnProperty.call(CITY_META, key) ? CITY_META[key] : null;
}

// US 2-letter state codes. Value is 1 (present).
// Yelp returns region codes for non-US cities (e.g. "VIC" for Melbourne, "11"
// for Lisbon) which are not states and are deliberately absent here.
const US_STATES = {
  "AL":1,"AK":1,"AZ":1,"AR":1,"CA":1,"CO":1,"CT":1,"DE":1,
  "FL":1,"GA":1,"HI":1,"ID":1,"IL":1,"IN":1,"IA":1,"KS":1,"KY":1,"LA":1,
  "ME":1,"MD":1,"MA":1,"MI":1,"MN":1,"MS":1,"MO":1,"MT":1,"NE":1,"NV":1,
  "NH":1,"NJ":1,"NM":1,"NY":1,"NC":1,"ND":1,"OH":1,"OK":1,"OR":1,"PA":1,
  "RI":1,"SC":1,"SD":1,"TN":1,"TX":1,"UT":1,"VT":1,"VA":1,"WA":1,"WV":1,
  "WI":1,"WY":1,"DC":1
};

// US state code -> full display name (all 50 states + DC). Keys are the exact
// US_STATES codes, so a state can only resolve a name after it already passed
// the US_STATES validity gate in computeLocationAggregates. This is the only
// code->name table in the repo: the search dropdown reads it (via stateNameFor)
// so a name-bearing query like "new" reaches New Jersey / New York / New Mexico
// / New Hampshire, which the raw 2-letter code could never match.
const US_STATE_NAMES = {
  "AL":"Alabama","AK":"Alaska","AZ":"Arizona","AR":"Arkansas",
  "CA":"California","CO":"Colorado","CT":"Connecticut","DE":"Delaware",
  "FL":"Florida","GA":"Georgia","HI":"Hawaii","ID":"Idaho",
  "IL":"Illinois","IN":"Indiana","IA":"Iowa","KS":"Kansas",
  "KY":"Kentucky","LA":"Louisiana","ME":"Maine","MD":"Maryland",
  "MA":"Massachusetts","MI":"Michigan","MN":"Minnesota","MS":"Mississippi",
  "MO":"Missouri","MT":"Montana","NE":"Nebraska","NV":"Nevada",
  "NH":"New Hampshire","NJ":"New Jersey","NM":"New Mexico","NY":"New York",
  "NC":"North Carolina","ND":"North Dakota","OH":"Ohio","OK":"Oklahoma",
  "OR":"Oregon","PA":"Pennsylvania","RI":"Rhode Island","SC":"South Carolina",
  "SD":"South Dakota","TN":"Tennessee","TX":"Texas","UT":"Utah",
  "VT":"Vermont","VA":"Virginia","WA":"Washington","WV":"West Virginia",
  "WI":"Wisconsin","WY":"Wyoming","DC":"Washington DC"
};

// Resolve a US state code to its full name ("NY" -> "New York"). hasOwnProperty-
// guarded (like cityMetaFor) so a code like "constructor" never resolves to an
// Object.prototype member; returns null for unknown codes.
function stateNameFor(code) {
  return Object.prototype.hasOwnProperty.call(US_STATE_NAMES, code) ? US_STATE_NAMES[code] : null;
}

// Whether a spot is in a US state. Both conditions must hold: the `state` is a
// 2-letter code in US_STATES (code validity) AND the `country` is "US". The
// country gate is what separates a foreign region code that collides with a US
// state code — Amsterdam's "NH" is Noord-Holland (country NL), Milan's "MI" /
// "MN" / "CO" / "VA" are Lombardy provinces (country IT) — from the real state,
// so a plausible code alone can never attribute a foreign spot to an American
// state. US_STATES stays a pure code-validity set; this adds the country
// condition at the point of use.
function isUsState(spot) {
  if (!spot) return false;
  var stateValue = (spot.state || "").trim().toUpperCase();
  var countryValue = (spot.country || "").trim().toUpperCase();
  return !!stateValue && !!US_STATES[stateValue] && countryValue === "US";
}

// Canonical key for the per-coordinate distance cache. Producer (the distance
// build step) and every consumer must use this exact format so a lookup hits
// the staged value instead of recomputing a haversine.
function coordKey(lat, lon) { return (lat || 0) + "|" + (lon || 0); }

// Single sort comparator over already-extracted scalar values. `key` fixes the
// intrinsic direction (rating descends, everything else ascends); `reversed`
// flips it. Callers pass extracted values so each key's accessor stays verbatim
// at the call site.
function compareSortValues(first, second, key, reversed) {
  if (key === "price") {
    // The unpriced sentinel (Infinity) always sorts last, regardless of
    // direction, so an unpriced spot never flips to the top under Price ↓.
    // The discount sentinel (-1) is finite and compares normally: cheapest
    // ascending, last descending.
    var firstUnpriced = !isFinite(first);
    var secondUnpriced = !isFinite(second);
    if (firstUnpriced !== secondUnpriced) return firstUnpriced ? 1 : -1;
    if (firstUnpriced && secondUnpriced) return 0;
  }
  var delta = (key === "rating") ? (second - first) : (first - second);
  return reversed ? -delta : delta;
}

// Whether a sort key orders descending (highest/largest first) after applying
// `reversed`. Mirrors compareSortValues' intrinsic direction — rating descends,
// distance/price ascend — so the sort arrow glyph can show the actual direction
// rather than assuming ascending.
function sortDescending(sortBy, reversed) {
  var descends = sortBy === "rating";
  return reversed ? !descends : descends;
}

// Tie-break-aware comparator: orders by the primary value (via
// compareSortValues), then — when the primary values are equal — by the
// tie-break scalars in order. `firstTieValues`/`secondTieValues` are the
// decorated tie-break values (one per extractor in `tieBreakers`); a missing
// value (undefined/null) is treated as 0. Direction is per-key:
//   price  — every tie-break is direction-independent: rating highest first,
//            review count highest first, then name ascending (the final string
//            fallback), so flipping Price ↑/↓ never flips them. The name
//            fallback must arrive pre-lowercased (the caller lowercases it at
//            decorate time) so the comparison is a plain `<`/`>` — no ICU
//            localeCompare and no per-comparison toLowerCase.
//   rating — the tie-break (Yelp review count) descends (highest first) and
//            `reversed` flips it along with the primary.
function compareSortValuesWithTie(first, second, key, reversed, firstTieValues, secondTieValues) {
  var primary = compareSortValues(first, second, key, reversed);
  if (primary !== 0) return primary;
  if (key === "price") {
    // Leading tie-breaks are numeric (higher first); the final name fallback
    // compares ascending for a stable deterministic order.
    for (var tieIndex = 0; tieIndex < firstTieValues.length - 1; tieIndex++) {
      var delta = (secondTieValues[tieIndex] || 0) - (firstTieValues[tieIndex] || 0);
      if (delta !== 0) return delta;
    }
    var nameIndex = firstTieValues.length - 1;
    var firstName = firstTieValues[nameIndex] || "";
    var secondName = secondTieValues[nameIndex] || "";
    if (firstName < secondName) return -1;
    if (firstName > secondName) return 1;
    return 0;
  }
  var tieDelta = (secondTieValues[0] || 0) - (firstTieValues[0] || 0);
  return reversed ? -tieDelta : tieDelta;
}

// Decorate-sort-undecorate: resolve each item's sort value once up front
// (O(n)) instead of twice per comparison (O(n log n)), sort on the scalars,
// then strip the decoration. `decorate` maps an item to its primary sort
// value; `tieBreakers` is an array of extractor functions applied in order
// when primary values are equal (the rating sort breaks ties by Yelp review
// count; the price sort by rating, then review count, then name). `extract`
// maps the decorated record back to the original item.
function decoratedSort(items, decorate, extract, key, reversed, tieBreakers) {
  var decorated = items.map(function(item) {
    var record = { item: item, value: decorate(item), tieValues: [] };
    for (var tieIndex = 0; tieIndex < (tieBreakers ? tieBreakers.length : 0); tieIndex++) {
      record.tieValues.push(tieBreakers[tieIndex](item));
    }
    return record;
  });
  decorated.sort(function(first, second) {
    if (tieBreakers && tieBreakers.length) {
      return compareSortValuesWithTie(first.value, second.value, key, reversed, first.tieValues, second.tieValues);
    }
    return compareSortValues(first.value, second.value, key, reversed);
  });
  return decorated.map(function(record) { return extract(record.item); });
}

// Collapse the three-way sortBy dispatch (rating/price/distance) into one spec
// lookup + a single decoratedSort call. `specs` maps a sort key to
// { extract(item) -> primary value, tieBreakers?: [extractor(item) -> scalar] };
// a missing or unknown key falls back to `specs.distance`, so distance stays
// the default. The decoration is stripped with the identity extractor — the
// callers' items (journal entries or spots) are returned as-is. `reversed`
// flips the value direction exactly as decoratedSort/compareSortValues do.
function sortBySpec(items, sortBy, reversed, specs) {
  var spec = (specs && (specs[sortBy] || specs.distance));
  if (!spec) return items;
  return decoratedSort(items, spec.extract, function(item) { return item; }, sortBy, reversed, spec.tieBreakers);
}

// Turn a value→count map into [{ key, count }] sorted alphabetically, with
// `nearestValue` moved to the front when it was counted. `key` holds the raw
// Yelp state/country code ("NY"/"US"), not a display name — the readable name
// is resolved downstream (stateNameFor for states, the code itself for
// countries).
function aggregateList(counts, nearestValue) {
  var list = [];
  for (var fieldValue in counts) list.push({ key: fieldValue, count: counts[fieldValue] });
  list.sort(function(firstValue, secondValue) { return firstValue.key.localeCompare(secondValue.key); });
  if (nearestValue && counts[nearestValue]) {
    for (var index = 0; index < list.length; index++) {
      if (list[index].key === nearestValue) {
        var homeValue = list.splice(index, 1)[0];
        list.unshift(homeValue);
        break;
      }
    }
  }
  return list;
}

// Map a city key to its display name: "los-angeles" -> "Los Angeles". The
// CITY_META table handles known keys first; this title-cases the slug as the
// fallback for unknown keys.
function displayNameFor(key) {
  return (key || "").replace(/-/g, ' ').replace(/\b\w/g, function (ch) { return ch.toUpperCase(); });
}

// Resolve a city key to its display label: the CITY_META name for known keys,
// else the title-cased slug. This is the single seam both the eager
// cityLabelMap build and the per-lookup cityLabel fallback go through, so
// a known key can never resolve to a title-cased slug ("nyc" -> "Nyc") while
// the CITY_META name ("New York City") exists.
function cityLabelFor(key) {
  var meta = cityMetaFor(key);
  return (meta && meta.name) ? meta.name : displayNameFor(key);
}

// Uppercase only the first character: "omakase" -> "Omakase". Distinct from
// displayNameFor (which title-cases every word); used for single-word filter
// labels like "omakase"/"rating".
function capitalize(text) {
  var value = text || "";
  return value.charAt(0).toUpperCase() + value.slice(1);
}

// Display label for a sort key: "distance" -> "Distance". The keys are
// SORT_KEYS; capitalization is the only transform (single-word labels).
function sortLabelFor(key) {
  return capitalize(key);
}

// ---- Search ranking ----
// Match-class tiers, highest first. rankSpots groups matches by class descending
// and preserves input order within a class, so a higher integer is a stronger
// match. Two rungs only: NAME_EXACT (the folded name equals the folded query)
// outranks MATCH (the folded query is a substring of the folded name OR the
// folded neighborhood). Everything below exact-match is one tier, so the
// caller's active sort (distance by default) decides among partial matches — a
// 1,644 km name-prefix must not outrank a 17 km word-start, and a 3,300 km city
// must not outrank a 5 km neighborhood. City-label matching is deliberately NOT
// a rung: it double-counts geography (once as rank, once as distance), and city
// scoping belongs to the search dropdown. `var` (not `const`) so the QML
// qualifier can read CatalogUtils.NAME_EXACT / CatalogUtils.MATCH.
var NAME_EXACT = 2;   // folded name equals the folded query
var MATCH = 1;        // query substring of the folded name or neighborhood

// Precompute the folded search fields for one spot. Called once per spot when
// the catalog index is built, so the per-keystroke hot path (matchClass) does
// no allocation and never re-folds. The city label is deliberately absent: the
// card-list rank matches name and neighborhood only (city scoping lives in the
// search dropdown).
function foldSpot(spot) {
  return {
    name: SpotUtils.foldSearchText(spot ? spot.name : null),
    neighborhood: SpotUtils.foldSearchText(spot ? spot.neighborhood : null)
  };
}

// Accent-insensitive substring test shared by the Journal and Wishlist search:
// folds both `text` and `query` (lowercase + Latin accent fold + whitespace
// collapse via SpotUtils.foldSearchText) and reports whether the folded text
// contains the folded query. This is the same fold the Explore rank path
// applies, so "sake" finds "Saké" on every tab. An empty/blank query is never
// a match (callers skip it before the scan; the guard keeps this total).
function foldedContains(text, query) {
  var foldedQuery = SpotUtils.foldSearchText(query);
  if (!foldedQuery) return false;
  return SpotUtils.foldSearchText(text).indexOf(foldedQuery) >= 0;
}

// Classify a folded spot against an already-folded query. Returns NAME_EXACT,
// MATCH, or 0 for no match. Tiers only — no continuous score, no field weights,
// no typo tolerance; the caller's active sort orders spots within a tier.
function matchClass(folded, foldedQuery) {
  if (!foldedQuery) return 0;
  var name = folded.name || "";
  var neighborhood = folded.neighborhood || "";
  if (name === foldedQuery) return NAME_EXACT;
  if (name.indexOf(foldedQuery) >= 0 || neighborhood.indexOf(foldedQuery) >= 0) return MATCH;
  return 0;
}

// Rank a spot list by search-match class. Returns a NEW array of the matching
// spots only, grouped by class descending, each class preserving its input
// order via a stable tie-break index (independent of the engine's sort
// stability). A spot carrying a precomputed `spot._folded` (the foldSpot result)
// is used as-is; otherwise it is folded on the fly from `spot`, so this also
// works on raw fixtures in tests. An empty/blank query returns `spots`
// unchanged. Search covers name and neighborhood only.
function rankSpots(spots, query) {
  var foldedQuery = SpotUtils.foldSearchText(query);
  if (!foldedQuery) return spots;
  var list = spots || [];
  var ranked = [];
  for (var index = 0; index < list.length; index++) {
    var spot = list[index];
    var folded = spot._folded || foldSpot(spot);
    var cls = matchClass(folded, foldedQuery);
    if (cls > 0) ranked.push({ spot: spot, cls: cls, index: index });
  }
  ranked.sort(function (first, second) {
    if (first.cls !== second.cls) return second.cls - first.cls;
    return first.index - second.index;
  });
  return ranked.map(function (record) { return record.spot; });
}

// Count label for invariant nouns: "2 saved" / "3 rated". The noun is
// appended as-is; nouns that change form with the count go through
// spotCountLabel. Missing or non-numeric input is treated as 0.
function countLabel(n, noun) {
  var count = Number.isFinite(n) ? n : 0;
  return count + " " + noun;
}

// "1 spot" / "2 spots" — the one count label with a plural form.
function spotCountLabel(n) {
  var count = Number.isFinite(n) ? n : 0;
  return count + " spot" + (count === 1 ? "" : "s");
}

// Radius filter label: "Within 10 km". Shared by the FilterBar token, the
// CityHeader title, and filterDescription so the wording stays consistent.
function formatRadius(km) {
  return "Within " + km + " km";
}

// Human-readable filter summary: "All cities" (or the resolved city label) plus
// one segment per active filter — kind, Unrated, sort, radius, and neighborhood.
// The search term is deliberately NOT a segment: CityHeader's ` matching "…"`
// suffix is the single owner of that fact (Explore), and the spotlight search
// field already shows the query directly above the criteria row. `cityLabel` is
// the resolved display name for the selected city ("" when none is selected);
// the remaining inputs mirror the panel's filter state. The caller resolves
// cityLabel through its memoized map and passes it in, keeping this pure.
function filterDescription(cityLabel, kindFilter, unratedOnly, sortBy, radius, neighborhood) {
  var desc = cityLabel || "All cities";
  if (kindFilter !== "all") desc += SEP + capitalize(kindFilter);
  if (unratedOnly) desc += SEP + "Unrated";
  if (sortBy !== "distance") desc += SEP + sortLabelFor(sortBy);
  if (radius > 0) desc += SEP + formatRadius(radius);
  if (neighborhood) desc += SEP + neighborhood;
  return desc;
}

// Display cap for a search query rendered in a description line: the query is
// trimmed, then truncated to this many characters with a trailing ellipsis.
// The same 24-character convention CityHeader's hint (`queryDisplayCap`) and
// SearchResultsDropdown's query row apply, so a long query can never overrun a
// bounded row.
var QUERY_DISPLAY_CAP = 24;

// Human-readable summary of the surprise pool's criteria — every filter that
// restricts which spots are IN the draw. The pool is the filtered AND searched
// set (searchedSpots), so this differs from filterDescription in two ways: the
// sort is omitted (it orders the displayed list but cannot change pool
// membership), and the search query is included (it restricts the draw) as a
// quoted, capped `"…"` segment in the same register CityHeader's ` matching "…"`
// suffix uses. `cityLabel` is the resolved display name for the selected city
// ("" when none is selected); the rest mirror the panel's filter state. The
// scope is always present — no city selection yields "All cities" — so the
// result is never empty.
function surprisePoolCriteria(cityLabel, kindFilter, unratedOnly, radius, neighborhood, query) {
  var desc = cityLabel || "All cities";
  if (kindFilter !== "all") desc += SEP + capitalize(kindFilter);
  if (unratedOnly) desc += SEP + "Unrated";
  if (radius > 0) desc += SEP + formatRadius(radius);
  if (neighborhood) desc += SEP + neighborhood;
  var trimmed = (query || "").trim();
  if (trimmed) {
    var shown = trimmed.length <= QUERY_DISPLAY_CAP ? trimmed : trimmed.slice(0, QUERY_DISPLAY_CAP) + "…";
    desc += SEP + '"' + shown + '"';
  }
  return desc;
}

// Unique neighborhood names for a city's spots, sorted alphabetically. The
// "All neighborhoods" clear affordance is supplied by the dropdown's clearLabel
// row and the chip strip's leading "All" chip, not as an item here — this list
// carries real neighborhoods only. `spots` is the pre-resolved array for the
// selected city; pass [] when no city is selected and the result is [].
function computeNeighborhoodOptions(spots) {
  var seen = Object.create(null);
  var list = spots || [];
  for (var index = 0; index < list.length; index++) {
    var neighborhood = (list[index].neighborhood || "").trim();
    if (neighborhood && !seen[neighborhood]) seen[neighborhood] = true;
  }
  return Object.keys(seen).sort();
}

// Sort city keys by distance from home, nearest first, with geo-less cities
// (non-finite distance) pushed last. `decorate` maps a city key to its distance
// (km, may be Infinity). The original-order tiebreaker makes ties stable
// regardless of the engine's sort stability.
function computeSortedCities(cities, decorate) {
  var decorated = (cities || []).map(function (cityKey, index) {
    return { key: cityKey, distance: decorate(cityKey), index: index };
  });
  decorated.sort(function (first, second) {
    var firstFinite = isFinite(first.distance);
    var secondFinite = isFinite(second.distance);
    if (firstFinite !== secondFinite) return firstFinite ? -1 : 1;
    if (firstFinite && first.distance !== second.distance) return first.distance - second.distance;
    return first.index - second.index;
  });
  return decorated.map(function (record) { return record.key; });
}

// Type precedence for the search-dropdown hits, used as the tie-break when two
// hits share a distance (or both are geo-less): a city is a stronger scope than
// one of its neighborhoods, so it outranks them, and a state is the broadest
// scope so it sorts last at equal distance. Returned ascending so the comparator
// can subtract ranks.
function searchHitTypeRank(type) {
  if (type === "city") return 0;
  if (type === "neighborhood") return 1;
  return 2;
}

// Deterministic name/key tie-break for equal-scope hits. The key (a city key or
// state code) is the final fallback so two hits with identical names still order
// deterministically rather than shuffling between renders.
function compareSearchHitNames(first, second) {
  var nameCmp = String(first.name || "").localeCompare(String(second.name || ""));
  if (nameCmp !== 0) return nameCmp;
  return String(first.key || "").localeCompare(String(second.key || ""));
}

// Sort search-dropdown hits by proximity, uniformly across all three types.
// Each hit carries its own `distance` (km from home, may be Infinity/undefined
// when geo-less), computed by the caller where the hit is built: cities and
// neighborhoods resolve their representative spot, and a state resolves the
// nearest spot in that state. Order: finite distances ascending, geo-less hits
// last; type as the tie-break (city before neighborhood before state); then
// name/key. A geo-less state (every spot in the state lacks coordinates) falls
// back to the count-descending-then-name rule. The comparator is total
// (distance, type, name, key — with the geo-less-state count fallback), so
// distinct hits never reorder across renders regardless of the engine's sort
// stability. Returns a new array; the input is untouched.
function sortSearchHits(hits) {
  var list = (hits || []).slice();
  list.sort(function (first, second) {
    var firstDistance = first.distance;
    var secondDistance = second.distance;
    var firstFinite = isFinite(firstDistance);
    var secondFinite = isFinite(secondDistance);
    if (firstFinite !== secondFinite) return firstFinite ? -1 : 1;
    if (!firstFinite && first.type === "state" && second.type === "state") {
      // Geo-less states: the count-descending-then-name fallback.
      if (first.count !== second.count) return second.count - first.count;
      return compareSearchHitNames(first, second);
    }
    if (firstFinite && firstDistance !== secondDistance) return firstDistance - secondDistance;
    var firstRank = searchHitTypeRank(first.type);
    var secondRank = searchHitTypeRank(second.type);
    if (firstRank !== secondRank) return firstRank - secondRank;
    return compareSearchHitNames(first, second);
  });
  return list;
}

// One catalog pass over a flat spot list builds the state and country count
// maps, the nearest-to-home value for each (the state/country of the single
// nearest spot, for the "current" first entry), and the nearest-spot distance
// per US state (`stateDistances`: state code -> km). A spot's `state` counts
// only when it is a US state (isUsState: a 2-letter code in US_STATES AND
// `country === "US"`) — a foreign region code that collides with a US state
// code (Amsterdam's "NH" is Noord-Holland, Milan's "MI"/"MN"/"CO"/"VA" are
// Lombardy provinces) is rejected, and non-US region codes ("VIC"/"11") are not
// states at all. `countryCounts` counts every non-empty country. `nearestState`
// is US-gated too ("" when the nearest spot is foreign), so a foreign code never
// promotes a US state to the front. `distanceFor` maps a spot to its distance
// from home in km, or undefined when home/coords are unknown (that spot then
// never wins "nearest" and never enters a state's distance). Returns
// { stateCounts, countryCounts, nearestState, nearestCountry, stateDistances }.
function computeLocationAggregates(spots, distanceFor) {
  var stateCounts = Object.create(null);
  var countryCounts = Object.create(null);
  var stateDistances = Object.create(null);
  var nearestState = "";
  var nearestCountry = "";
  var nearestDistance = Infinity;
  var list = spots || [];
  for (var index = 0; index < list.length; index++) {
    var spot = list[index];
    var stateValue = (spot.state || "").trim().toUpperCase();
    var countryValue = (spot.country || "").trim().toUpperCase();
    var usState = isUsState(spot);
    if (usState) stateCounts[stateValue] = (stateCounts[stateValue] || 0) + 1;
    if (countryValue) countryCounts[countryValue] = (countryCounts[countryValue] || 0) + 1;
    var distanceKm = distanceFor(spot);
    // Track the value of the spot nearest home (for the "current" first entry).
    // Only a genuine US state qualifies; a foreign region code (even one that
    // collides with a US state code) is not a US state and must not promote one.
    if (distanceKm !== undefined && distanceKm < nearestDistance) {
      nearestDistance = distanceKm;
      nearestState = usState ? stateValue : "";
      nearestCountry = countryValue;
    }
    // Nearest spot per US state: the state hit's own proximity (the dropdown
    // orders state hits by distance, so a near state outranks a far
    // neighborhood). Geo-less spots (undefined/Infinity) never enter.
    if (usState && isFinite(distanceKm) &&
        (stateDistances[stateValue] === undefined || distanceKm < stateDistances[stateValue])) {
      stateDistances[stateValue] = distanceKm;
    }
  }
  return { stateCounts: stateCounts, countryCounts: countryCounts, nearestState: nearestState, nearestCountry: nearestCountry, stateDistances: stateDistances };
}

// Build { key, label } pairs for the filter dropdowns. Each is pure: inputs are
// passed explicitly, so they are unit-testable and reusable verbatim from QML.
// `distanceLabelFor` resolves a city key to its formatted distance string ("" when
// unknown) — injected so this module stays independent of spot-utils' formatters.

// City dropdown: "New York City · 3.2 km · 42 spots". The name comes from
// cityLabelFor (the CITY_META name, else the title-cased slug — the same seam
// the widget's cityLabel falls back to), the distance from the injected
// resolver, and the count from the spotsByCity map.
function buildCityFilterItems(sortedCities, distanceLabelFor, spotsByCity) {
  return (sortedCities || []).map(function (key) {
    var count = (spotsByCity && spotsByCity[key]) ? spotsByCity[key].length : 0;
    var distance = distanceLabelFor(key) || "";
    var label = cityLabelFor(key) + (distance ? SEP + distance : "") + SEP + spotCountLabel(count);
    return { key: key, label: label };
  });
}

// Shared count-label mapping for the state/country dropdowns.
function buildNamedCountItems(list) {
  return (list || []).map(function (item) {
    return { key: item.key, label: item.key + SEP + spotCountLabel(item.count) };
  });
}

// State dropdown: "NY · 12 spots".
function buildStateFilterItems(states) {
  return buildNamedCountItems(states);
}

// Country dropdown: "US · 42 spots".
function buildCountryFilterItems(countries) {
  return buildNamedCountItems(countries);
}

// Neighborhood dropdown: the name unchanged. The "All neighborhoods" clear row
// is the dropdown's clearLabel (see FilterSheet.qml), not an item in this list.
function buildNeighborhoodFilterItems(neighborhoods) {
  return (neighborhoods || []).map(function (nb) {
    return { key: nb, label: nb };
  });
}

// Pick a uniform random spot from `pool`, optionally avoiding `excludeName`.
// Returns the picked spot, or null when the pool is empty or every candidate
// is excluded. `rng` is an injectable [0, 1) source (default Math.random) so
// tests are deterministic; `excludeName` (optional) is a spot name to skip —
// "Try another" passes the currently shown spot so a shuffle never repeats it
// while an alternative exists.
function pickRandom(pool, rng, excludeName) {
  var spots = pool || [];
  var candidates = spots;
  if (excludeName) {
    candidates = spots.filter(function (spot) { return spot.name !== excludeName; });
  }
  if (candidates.length === 0) return null;
  var random = (typeof rng === "function") ? rng() : Math.random();
  var index = Math.floor(random * candidates.length);
  // Clamp into range so an out-of-spec rng (>= 1.0 or negative) never returns
  // undefined from an index outside the array.
  if (index < 0) index = 0;
  if (index >= candidates.length) index = candidates.length - 1;
  return candidates[index];
}

if (typeof module !== "undefined") {
  module.exports = {
    SEP,
    SEP_LEAD,
    SORT_KEYS,
    RADIUS_STEPS,
    QUERY_DISPLAY_CAP,
    nextRadiusStep,
    CITY_META,
    cityMetaFor,
    US_STATES,
    US_STATE_NAMES,
    stateNameFor,
    isUsState,
    coordKey,
    compareSortValues,
    sortDescending,
    sortLabelFor,
    compareSortValuesWithTie,
    decoratedSort,
    sortBySpec,
    aggregateList,
    displayNameFor,
    cityLabelFor,
    countLabel,
    spotCountLabel,
    capitalize,
    formatRadius,
    NAME_EXACT,
    MATCH,
    foldSpot,
    matchClass,
    foldedContains,
    rankSpots,
    filterDescription,
    surprisePoolCriteria,
    computeNeighborhoodOptions,
    computeSortedCities,
    sortSearchHits,
    computeLocationAggregates,
    buildCityFilterItems,
    buildStateFilterItems,
    buildCountryFilterItems,
    buildNeighborhoodFilterItems,
    pickRandom
  };
}
