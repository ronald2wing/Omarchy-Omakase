// catalog-utils.js — Omakase catalog pure logic extracted from BarWidget.qml
// Dual-use: Node.js (tests) and QML (import "catalog-utils.js" as CatalogUtils)
//
// Every function here is pure: inputs are passed explicitly (no root.* reads),
// so they are unit-testable under Node and reusable verbatim from QML bindings
// without tracking issues. Side-effecting orchestration stays in BarWidget.qml.

// The accent-folding function lives in spot-utils.js (shared with Service.qml
// and BarWidget.qml). In Node this file requires it; in QML the bare `SpotUtils`
// identifier resolves to the importing document's `import "spot-utils.js" as
// SpotUtils` qualifier (BarWidget.qml imports both files). The identifier is
// deliberately not declared with `var`: a local declaration would shadow the
// QML qualifier with null. Every `SpotUtils` read sits lazily inside a function
// body, so the document is fully initialized before the first call regardless
// of import order.
if (typeof module !== "undefined" && module.exports) {
  SpotUtils = require("./spot-utils.js");
}

// View/tab identifiers shared by the panel and its components: the `tab`
// property values (BarWidget.tab) and the search-dropdown view names
// (activeSearchView). One source so a tab string can never drift between the
// tab chips, the tab bodies, and a dropdown's `active` comparison. `var` (not
// `const`) so QML's import qualifier exposes them as Qualifier.NAME.
var VIEW_EXPLORE = "explore";
var VIEW_WISHLIST = "wishlist";
var VIEW_JOURNAL = "journal";
var VIEW_SPOTLIGHT = "spotlight";

// Location-scope identifiers: the selectLocationScope/selectX scope values AND
// the search-dropdown hit `type` values (a "city" scope IS a "city" hit). One
// set serves both, so the dropdown's type checks and the panel's scope checks
// can never disagree on the same string.
var SCOPE_CITY = "city";
var SCOPE_STATE = "state";
var SCOPE_COUNTRY = "country";
var SCOPE_NEIGHBORHOOD = "neighborhood";

// The kind-filter sentinel meaning "no type filter": the default kindFilter and
// the all-kinds chip, distinct from the "ayce"/"discount"/"omakase" kind values.
var KIND_FILTER_ALL = "all";

// Caption for the "filtered to empty" state on every tab (Explore/Wishlist/
// Journal): the list has content, but the active search or filters hide it all.
// Exported so the three tabs render one canonical string.
var EMPTY_STATE_CAPTION = "Try a different search or clear your filters.";

// The both-active empty-state action label: shown when a search query AND a
// filter are both active and the list is empty, so clearing only one changes
// nothing — the action clears both in one click. Exported so Explore and the
// Wishlist/Journal tabs render one canonical string.
var EMPTY_STATE_CLEAR_ACTION_LABEL = "Clear search and filters";

// The three sort keys the filter chip cycles through. Single source for
// FilterBar's sort control so the key set and its labels (via capitalizeFirst)
// can never drift apart.
var SORT_KEYS = ["distance", "rating", "price"];

// The radius filter's off/on cycle (km): off, then 5/10/20. nextRadiusStep
// computes the successor from this table; FilterBar consumes only nextRadiusStep
// (never the array directly) and the Node tests pin the cycle through
// nextRadiusStep too (the table itself is not exported).
const RADIUS_STEPS = [0, 5, 10, 20];

// Next radius in the cycle (0 -> 5 -> 10 -> 20 -> 0). An unknown current value
// wraps to off (0) — the same result as the hand-rolled chain's final `else`.
function nextRadiusStep(current) {
  var index = RADIUS_STEPS.indexOf(current);
  return RADIUS_STEPS[(index + 1) % RADIUS_STEPS.length];
}

// Deterministic content fingerprint of a spotsByCity map. Two independent
// 31-bit rolling hashes over the JSON serialization plus its length — a
// collision would require an accidental 62-bit agreement the ~5k-spot catalog
// cannot produce (and a false "catalog changed" only costs one redundant walk,
// never a wrong result). JSON.stringify is the cheapest obviously-correct
// canonical form: it captures every persisted field (including the
// string_array fields) with no per-type edge cases. The load path calls this
// once per state.json read — startup, a home move, or a refresh — never per
// frame, so the ~1.9 MB serialization is negligible against the two chunked
// walks it lets us skip.
function catalogSpotsHash(spotsByCity) {
  var serialized = JSON.stringify(spotsByCity);
  var hashA = 5381;
  var hashB = 52711;
  for (var i = 0; i < serialized.length; i++) {
    var code = serialized.charCodeAt(i);
    hashA = (hashA * 31 + code) & 0x7fffffff;
    hashB = (hashB * 37 + code) & 0x7fffffff;
  }
  return serialized.length + ":" + hashA.toString(36) + ":" + hashB.toString(36);
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

// Null-safe own-property check: the guard every map read keyed by user data
// uses, so "constructor"/"toString"/"__proto__" can never resolve to an
// Object.prototype member.
function hasOwn(map, key) {
  return Object.prototype.hasOwnProperty.call(map, key);
}

// Lookup a city key in CITY_META. Reads through hasOwn so a city like
// "constructor" can never resolve to an Object.prototype member. Returns null
// for unknown keys — an explicit "no such key" marker a caller can distinguish
// from a real entry (stateNameFor uses the same null convention).
function cityMetaFor(key) {
  return hasOwn(CITY_META, key) ? CITY_META[key] : null;
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

// Resolve a US state code to its full name ("NY" -> "New York"). hasOwn-
// guarded (like cityMetaFor) so a code like "constructor" never resolves to an
// Object.prototype member; returns null for unknown codes.
function stateNameFor(code) {
  return hasOwn(US_STATE_NAMES, code) ? US_STATE_NAMES[code] : null;
}

// Normalize a spot's region code and country for lookup: each coerced through
// String() (so a wrong-typed field — a JSON number smuggled in through a
// hand-edited state.json — never throws on .trim()/.toUpperCase()), trimmed,
// and uppercased. Returns { state, country }.
function normalizeStateCountry(spot) {
  return {
    state: String(spot.region_code || "").trim().toUpperCase(),
    country: String(spot.country || "").trim().toUpperCase()
  };
}

// Whether an already-normalized (trimmed + uppercased) state/country pair is a
// US state: the `state` is a 2-letter code in US_STATES (code validity) AND the
// `country` is "US". The country gate is what separates a foreign region code
// that collides with a US state code — Amsterdam's "NH" is Noord-Holland
// (country NL), Milan's "MI"/"MN"/"CO"/"VA" are Lombardy provinces (country IT)
// — from the real state, so a plausible code alone can never attribute a
// foreign spot to an American state. US_STATES stays a pure code-validity set;
// this adds the country condition at the point of use. Shared by isUsState (a
// spot) and computeLocationAggregates (which has already normalized the same
// fields), so the normalize + lookup runs once per spot.
function isUsStateCode(state, country) {
  return !!state && hasOwn(US_STATES, state) && country === "US";
}

// Whether a spot is in a US state — isUsStateCode applied to the spot's
// normalized state/country. The single public predicate (a spot in, a boolean
// out); the one internal caller with already-normalized values
// (computeLocationAggregates) uses isUsStateCode directly.
function isUsState(spot) {
  if (!spot) return false;
  var normalized = normalizeStateCountry(spot);
  return isUsStateCode(normalized.state, normalized.country);
}

// Canonical key for the per-coordinate distance cache. Producer (the distance
// build step) and every consumer must use this exact format so a lookup hits
// the staged value instead of recomputing a haversine. Validity follows
// SpotUtils.hasCoords (finite, including 0): a coordinate hasCoords rejects
// keys to "" so a missing value can never collide with the genuine (0, 0) spot.
function coordKey(lat, lon) {
  if (!SpotUtils.hasCoords(lat, lon)) return "";
  return lat + "|" + lon;
}

// One step of the per-coordinate distance build: gate a spot on
// SpotUtils.hasCoords (the shared finite-coordinate rule), key it by coordKey,
// and stage a haversine from home on first write — a second spot with the same
// coordinates (or a repeat in the walk) never overwrites the first, so the cache
// keeps one entry per coordinate and the first-in-catalog-order value wins.
// `homeLat`/`homeLon` are injected so the step stays pure; the caller (the
// chunked walk) owns the staged-map publication and token supersede check.
function stageSpotDistance(spot, homeLat, homeLon, staged) {
  if (!SpotUtils.hasCoords(spot.lat, spot.lon)) return;
  var key = coordKey(spot.lat, spot.lon);
  if (staged[key] === undefined) staged[key] = SpotUtils.haversine(homeLat, homeLon, spot.lat, spot.lon);
}

// The intrinsic direction of a sort key before `reversed` is applied: rating
// descends (best first), distance and price ascend (nearest/cheapest first).
// Single source for both compareSortValues' delta sign and isSortDescending's
// arrow direction, so the two can never drift to opposite glyphs.
function intrinsicDescends(sortKey) {
  return sortKey === "rating";
}

// Single sort comparator over already-extracted scalar values. `sortKey` fixes
// the intrinsic direction (rating descends, everything else ascends);
// `reversed` flips it. Callers pass extracted values so each key's accessor
// stays verbatim at the call site.
function compareSortValues(first, second, sortKey, reversed) {
  if (sortKey === "price") {
    // The unpriced sentinel (Infinity) always sorts last, regardless of
    // direction, so an unpriced spot never flips to the top under Price ↓.
    // The discount sentinel (-1) is finite and compares normally: cheapest
    // ascending, last descending.
    var firstUnpriced = !SpotUtils.isFiniteNumber(first);
    var secondUnpriced = !SpotUtils.isFiniteNumber(second);
    if (firstUnpriced !== secondUnpriced) return firstUnpriced ? 1 : -1;
    if (firstUnpriced && secondUnpriced) return 0;
  }
  var delta = intrinsicDescends(sortKey) ? (second - first) : (first - second);
  return reversed ? -delta : delta;
}

// Whether a sort key orders descending (highest/largest first) after applying
// `reversed`. Mirrors compareSortValues' intrinsic direction — rating descends,
// distance/price ascend — so the sort arrow glyph can show the actual direction
// rather than assuming ascending.
function isSortDescending(sortBy, reversed) {
  var descends = intrinsicDescends(sortBy);
  return reversed ? !descends : descends;
}

// Ascending code-unit string comparison (plain `<`/`>`, no localeCompare), so
// the order is identical across Node and QJSEngine and independent of locale.
// Shared by the price sort's name fallback and the search-hit name/key
// tie-break, so both no-ICU call sites compare with one rule.
function compareStringsAscending(first, second) {
  if (first < second) return -1;
  if (first > second) return 1;
  return 0;
}

// The price sort's tie-break ladder: the leading numeric tie-breaks (rating,
// review count) order highest first and are direction-independent — they reuse
// the same scalar comparator as the rating tie-break below (compareSortValues
// with the rating direction and `reversed` pinned false), so flipping Price ↑/↓
// never flips them. The final name fallback compares ascending for a stable
// deterministic order, and must arrive pre-lowercased (the caller lowercases it
// at decorate time) so the comparison is a plain `<`/`>` — no ICU localeCompare
// and no per-comparison toLowerCase.
function comparePriceTieBreak(firstTieValues, secondTieValues) {
  for (var tieIndex = 0; tieIndex < firstTieValues.length - 1; tieIndex++) {
    var delta = compareSortValues(firstTieValues[tieIndex] || 0, secondTieValues[tieIndex] || 0, "rating", false);
    if (delta !== 0) return delta;
  }
  var nameIndex = firstTieValues.length - 1;
  var firstName = firstTieValues[nameIndex] || "";
  var secondName = secondTieValues[nameIndex] || "";
  return compareStringsAscending(firstName, secondName);
}

// The rating sort's single tie-break: Yelp review count, descending (highest
// first), and `reversed` flips it along with the primary.
function compareRatingTieBreak(firstTieValues, secondTieValues, reversed) {
  return compareSortValues(firstTieValues[0] || 0, secondTieValues[0] || 0, "rating", reversed);
}

// Tie-break-aware comparator: orders by the primary value (via
// compareSortValues), then — when the primary values are equal — by the
// tie-break scalars in order. `firstTieValues`/`secondTieValues` are the
// decorated tie-break values (one per extractor in `tieBreakers`); a missing
// value (undefined/null) is treated as 0. Direction is per-key:
//   price  — every tie-break is direction-independent (comparePriceTieBreak).
//   rating — the tie-break (Yelp review count) descends and `reversed` flips it
//            along with the primary (compareRatingTieBreak).
function compareSortValuesWithTie(first, second, sortKey, reversed, firstTieValues, secondTieValues) {
  var primary = compareSortValues(first, second, sortKey, reversed);
  if (primary !== 0) return primary;
  if (sortKey === "price") {
    return comparePriceTieBreak(firstTieValues, secondTieValues);
  }
  return compareRatingTieBreak(firstTieValues, secondTieValues, reversed);
}

// Decorate one item: resolve its primary sort value once and, when tie-breakers
// are present, its tie-break scalars. `tieValues` is allocated only when the
// spec has tie-breakers — the distance sort (and any other tie-less sort) would
// otherwise allocate one empty array per spot (~5k arrays) for nothing.
function decorateItem(item, decorate, tieBreakers, hasTieBreakers) {
  var record = { item: item, value: decorate(item) };
  if (hasTieBreakers) {
    record.tieValues = [];
    for (var tieIndex = 0; tieIndex < tieBreakers.length; tieIndex++) {
      record.tieValues.push(tieBreakers[tieIndex](item));
    }
  }
  return record;
}

// Compare two decorated records: tie-break-aware when the spec has tie-breakers,
// else the plain scalar comparison.
function compareDecorated(first, second, sortKey, reversed, hasTieBreakers) {
  if (hasTieBreakers) {
    return compareSortValuesWithTie(first.value, second.value, sortKey, reversed, first.tieValues, second.tieValues);
  }
  return compareSortValues(first.value, second.value, sortKey, reversed);
}

// Decorate-sort-undecorate: resolve each item's sort value once up front
// (O(n)) instead of twice per comparison (O(n log n)), sort on the scalars,
// then strip the decoration. `decorate` maps an item to its primary sort
// value; `tieBreakers` is an array of extractor functions applied in order
// when primary values are equal (the rating sort breaks ties by Yelp review
// count; the price sort by rating, then review count, then name).
function decoratedSort(items, decorate, sortKey, reversed, tieBreakers) {
  var hasTieBreakers = !!(tieBreakers && tieBreakers.length);
  var decorated = items.map(function(item) {
    return decorateItem(item, decorate, tieBreakers, hasTieBreakers);
  });
  decorated.sort(function(first, second) {
    return compareDecorated(first, second, sortKey, reversed, hasTieBreakers);
  });
  return decorated.map(function(record) { return record.item; });
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
  return decoratedSort(items, spec.extract, sortBy, reversed, spec.tieBreakers);
}

// Shared factory for the two spot-shaped sort specs (BarWidget's spotSortSpecs
// and wishlistSortSpecs): `spotOf(item)` resolves an item to its spot (or null —
// a saved name with no catalog match); `nameOf(item)` resolves the rating-map
// name; `ratingFor(spot, name)` and `distanceFor(spot)` are injected so the
// factory stays pure (the caller passes its rating fallback and its distance
// cache lookup). The two instantiations differ only in spotOf/nameOf; the rating
// primary and the price rating tie-break both route through ratingFor, so they
// cannot drift. Tie-break semantics:
//   rating   — the user's rating when present, else the stamped Yelp rating
//              (_yelpRating); tie-break by Yelp review count (_yelpReviewCount).
//   price    — priceSortKey yields -1 (discount, cheapest), a finite price,
//              the Yelp price bucket, or Infinity (unpriced, always last);
//              tie-break rating → review count → name, all direction-
//              independent so flipping Price ↑/↓ never flips them.
//   distance — nearest first, no tie-break.
function makeSortSpecs(spotOf, nameOf, ratingFor, distanceFor) {
  return {
    rating: {
      extract: function (item) { return ratingFor(spotOf(item), nameOf(item)); },
      tieBreakers: [
        function (item) { var spot = spotOf(item); return spot ? spot._yelpReviewCount : 0; }
      ]
    },
    price: {
      extract: function (item) { return SpotUtils.priceSortKey(spotOf(item)); },
      tieBreakers: [
        function (item) { return ratingFor(spotOf(item), nameOf(item)); },
        function (item) { var spot = spotOf(item); return spot ? spot._yelpReviewCount : 0; },
        // Pre-lowercased at decorate time so compareSortValuesWithTie compares
        // plain strings (no per-comparison toLowerCase/localeCompare). This
        // name tie-break always reads the item's own `name` field (raw spots
        // and wishlist entries both carry it).
        function (item) { return item.name ? String(item.name).toLowerCase() : ""; }
      ]
    },
    distance: {
      extract: function (item) {
        return distanceFor(spotOf(item));
      }
    }
  };
}

// Turn a value→count map into [{ key, count }] sorted alphabetically, with
// `nearestValue` moved to the front when it was counted. `key` holds the raw
// Yelp state/country code ("NY"/"US"), not a display name — the readable name
// is resolved downstream (stateNameFor for states, the code itself for
// countries).
function sortedCountList(counts, nearestValue) {
  var list = Object.keys(counts).map(function (fieldValue) {
    return { key: fieldValue, count: counts[fieldValue] };
  });
  // localeCompare here is deliberate: the keys are 2-letter state/country codes
  // (pure ASCII uppercase), so locale collation and a raw code-unit comparison
  // agree — the module's no-ICU rule targets user-entered names with accents,
  // which never reach this list.
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

// Stamp a state-count aggregate list ({ key, count } from sortedCountList) with
// the folded code and folded display name the search dropdown matches against.
// The folded name comes from stateNameFor (the full state name), so a
// name-bearing query like "new" reaches New Jersey/New York/New Mexico/New
// Hampshire; the folded code lets a code query ("ny") match the raw 2-letter
// code. Returns [{ key, count, foldedCode, foldedName }].
function buildStateOptions(aggregates) {
  var states = sortedCountList(aggregates.stateCounts, aggregates.nearestState);
  for (var stateIndex = 0; stateIndex < states.length; stateIndex++) {
    var code = states[stateIndex].key;
    states[stateIndex].foldedCode = SpotUtils.foldSearchText(code);
    states[stateIndex].foldedName = SpotUtils.foldSearchText(stateNameFor(code));
  }
  return states;
}

// Map a city key to its display name: "los-angeles" -> "Los Angeles". The
// CITY_META table handles known keys first; this title-cases the slug as the
// fallback for unknown keys.
function titleCaseCitySlug(key) {
  return (key || "").replace(/-/g, ' ').replace(/\b\w/g, function (ch) { return ch.toUpperCase(); });
}

// Resolve a city key to its display label: the CITY_META name for known keys,
// else the title-cased slug. This is the single seam both the eager
// cityLabelMap build and the per-lookup cityLabel fallback go through, so
// a known key can never resolve to a title-cased slug ("nyc" -> "Nyc") while
// the CITY_META name ("New York City") exists. Unlike the raw lookups
// (cityMetaFor/stateNameFor), which return null for an unknown key, this label
// path always returns a display string — an unknown key title-cases, and only
// a blank key yields "" — so a missing label renders as nothing, never "null".
function cityLabelFor(key) {
  var meta = cityMetaFor(key);
  return (meta && meta.name) ? meta.name : titleCaseCitySlug(key);
}

// Uppercase only the first character: "omakase" -> "Omakase". Distinct from
// titleCaseCitySlug (which title-cases every word); used for single-word filter
// labels like "omakase"/"rating".
function capitalizeFirst(text) {
  var value = text || "";
  return value.charAt(0).toUpperCase() + value.slice(1);
}

// Display label for a spot kind. The kind VALUES stay lowercase (spotKind's
// return, filter keys, equality checks) — only the rendered label changes.
// AYCE is an acronym, so it cannot go through capitalizeFirst() like the others.
// Unknown/empty kinds map to "" (SpotCard hides the chip on that).
var KIND_LABELS = Object.create(null);
KIND_LABELS.ayce = "AYCE";
KIND_LABELS.discount = "Discount";
KIND_LABELS.omakase = "Omakase";
function kindLabelFor(kind) {
  return KIND_LABELS[kind] || "";
}

// Display label for the collapsed action cluster's phone/copy cell, keyed on
// whether a `tel:` URI handler is registered. With a handler the cell dials
// ("Call"); without one the number must be copied to the clipboard ("Copy
// number"), so the label must say which. Pure (no I/O) so QML and Node share
// one source of truth and the choice is unit-testable.
function phoneActionLabel(telHandlerAvailable) {
  return telHandlerAvailable ? "Call" : "Copy number";
}

// ---- Search ranking ----
// Match-class tiers, highest first. rankSpots groups matches by class descending
// and preserves input order within a class, so a higher integer is a stronger
// match. Two rungs only: NAME_EXACT (the folded name equals the folded query)
// outranks MATCH (the folded query is a substring of the folded name OR the
// folded neighborhood). Everything below exact-match is one tier, so the
// caller's active sort (distance by default) decides among partial matches — a
// far name-prefix must not outrank a near word-start, and a distant city
// must not outrank a nearby neighborhood. City-label matching is deliberately NOT
// a rung: it double-counts geography (once as rank, once as distance), and city
// scoping belongs to the search dropdown. matchClass/rankSpots consume these
// internally (the tier constants are module-private).
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

// One spot's step in the catalog index walk: precompute the folded search blob
// (foldSpot) so the per-keystroke rank path (rankSpots -> matchClass) does zero
// allocation, and record the name→entries index entry. The blob folds name +
// neighborhood only — the card-list rank does not match the city label (city
// scoping lives in the search dropdown). Correctness never depends on _folded:
// rankSpots falls back to folding the raw spot when the field is absent. `map`
// is the null-prototype name→entries map the walk accumulates; entries key by
// normalized name (trim + lowercase) so resolveSpot resolves a journal/wishlist
// name like "Omi Omakase" to catalog "OMI OMAKASE".
function indexSpot(spot, cityKey, map) {
  spot._folded = foldSpot(spot);
  var name = spot.name;
  if (name !== undefined && name !== null) {
    var key = SpotUtils.normalizeName(name);
    if (!map[key]) map[key] = [];
    map[key].push({ spot: spot, cityKey: cityKey });
  }
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
// spots only, grouped by class descending (NAME_EXACT then MATCH), each class
// preserving its input order. A spot carrying a precomputed `spot._folded` (the
// foldSpot result) is used as-is; otherwise it is folded on the fly from `spot`,
// so this also works on raw fixtures in tests. An empty/blank query returns
// `spots` unchanged. Search covers name and neighborhood only.
//
// The grouping is a stable two-pass partition, not a sort: the first pass
// collects exact matches and the second partial matches, each in input order,
// so the result is byte-identical to a decorate-sort-undecorate on (class,
// index) but runs in O(m) and allocates only the output array — no per-match
// {spot, cls, index} record, no comparator, no `.map` strip. Two rungs only and
// stable within a class; this is a settled product decision, not a score.
function rankSpots(spots, query) {
  var foldedQuery = SpotUtils.foldSearchText(query);
  if (!foldedQuery) return spots;
  var list = spots || [];
  var ranked = [];
  for (var index = 0; index < list.length; index++) {
    var spot = list[index];
    var folded = spot._folded || foldSpot(spot);
    if (matchClass(folded, foldedQuery) === NAME_EXACT) ranked.push(spot);
  }
  for (var index2 = 0; index2 < list.length; index2++) {
    var spot2 = list[index2];
    var folded2 = spot2._folded || foldSpot(spot2);
    if (matchClass(folded2, foldedQuery) === MATCH) ranked.push(spot2);
  }
  return ranked;
}

// Query predicate shared by the Journal and Wishlist card-list filters: a row
// matches when any of its fields' folded text contains the folded query. The
// caller passes the fields it has as an array — a Journal row's [name, notes],
// a Wishlist row's [name, neighborhood] — and every field is optional, so a
// null/empty field is a non-match and the two callers share one predicate over
// their own field set. The city label is deliberately NOT matched: Explore's
// rankSpots matches name and neighborhood only, and matching the label would
// double-count geography (once as a match, once as distance) and let a far
// city's label outrank a near neighborhood — city scoping belongs to the search
// dropdown, not the card-list predicate. Notes stay because they are a genuine
// scoped-list feature (searching your own notes); Explore has no notes to match.
function entryMatchesQuery(fields, query) {
  var list = fields || [];
  for (var index = 0; index < list.length; index++) {
    var field = list[index];
    if (field && foldedContains(field, query)) return true;
  }
  return false;
}

// Shared filter+sort pipeline for the Journal and Wishlist card lists,
// extracted from BarWidget's computeSortedJournal / computeSortedWishlist:
// resolve each raw item ONCE, filter by the caller's global filters, filter by
// the search query, sort, then map to the delegate shape. The two call sites
// differ only in what `locate` and `opts` inject, so one body serves both.
//
//   entries — the raw source array (rated journal entries, or saved names).
//   locate(item) — resolves one raw item to its record once (the caller's
//       resolveSpot-based mapping). The record carries the fields the filters,
//       the sort specs, and the final map all read.
//   query — the active search term ("" when empty/blank).
//   opts:
//     foldNeighborhood() — the caller's folded neighborhood-filter value
//         (BarWidget's foldedNeighborhoodFilter); hoisted here so it is
//         computed once per pass, not once per item.
//     passesFilters(record, neighborhoodFolded) — the caller's global filter
//         (BarWidget's passesFilters) bound to its per-caller flags; returns
//         whether the record survives the kind/city/radius/neighborhood/
//         state/country/unrated predicates.
//     matchFields(record) — the fields this view searches, as an array of
//         strings for entryMatchesQuery (Journal: [name, notes]; Wishlist:
//         [name, neighborhood]).
//     sortSpecs / sortBy / sortReversed — the injected sort-spec map and the
//         active sort state, consumed by sortBySpec.
//     mapItem(record) — optional; the final map to the delegate shape (Journal
//         reshapes to { name, cityKey, spot, entry }; Wishlist records are
//         already delegate-shaped and omit it).
function resolveFilterSort(entries, locate, query, opts) {
  opts = opts || {};
  var records = (entries || []).slice().map(locate);
  var neighborhoodFolded = (typeof opts.foldNeighborhood === "function") ? opts.foldNeighborhood() : "";
  records = records.filter(function (record) {
    return opts.passesFilters(record, neighborhoodFolded);
  });
  var trimmedQuery = (query || "").trim();
  if (trimmedQuery) {
    var matchFields = opts.matchFields;
    records = records.filter(function (record) {
      return entryMatchesQuery(matchFields(record), query);
    });
  }
  records = sortBySpec(records, opts.sortBy, opts.sortReversed, opts.sortSpecs);
  if (opts.mapItem) records = records.map(opts.mapItem);
  return records;
}

// Aggregate a journal (rated entries, oldest-first) into the two per-name maps
// the widget maintains eagerly: `ratingsBySpot` (normalized-name -> { total,
// count } for the average) and `journalByName` (normalized-name -> the most
// recent rated entry — last write wins because entries arrive oldest-first).
// Entries without a rating are skipped. Both maps are null-prototype so a spot
// named "constructor"/"__proto__" can never resolve to Object.prototype. The
// caller's trap — it must pass the raw `journal`, not its declarative
// `ratedEntries` projection, which is stale during onJournalChanged — is a
// caller concern; this function is pure over the array it is given.
function buildRatingMaps(journal) {
  var ratingsBySpot = Object.create(null);
  var journalByName = Object.create(null);
  var list = journal || [];
  list.forEach(function (entry) {
    if (!entry.rating) return;
    var key = SpotUtils.normalizeName(entry.name);
    if (!ratingsBySpot[key]) ratingsBySpot[key] = { total: 0, count: 0 };
    ratingsBySpot[key].total += entry.rating;
    ratingsBySpot[key].count++;
    journalByName[key] = entry;
  });
  return { ratingsBySpot: ratingsBySpot, journalByName: journalByName };
}

// A count coerced to a finite number: non-finite input (missing/NaN/Infinity)
// is treated as 0, so a label can never render "undefined spots".
function finiteOrZero(n) {
  return Number.isFinite(n) ? n : 0;
}

// Count label for invariant nouns: "2 saved" / "3 rated". The noun is
// appended as-is; nouns that change form with the count go through
// spotCountLabel. Missing or non-numeric input is treated as 0.
function unpluralizedCountLabel(n, noun) {
  return finiteOrZero(n) + " " + noun;
}

// "1 spot" / "2 spots" / "1 open spot" / "2 open spots" — the count labels
// with a plural form. pluralizeCount coerces its count to a finite number
// (like unpluralizedCountLabel), appends the noun, and pluralizes it on a count of 1;
// spotCountLabel/openSpotCountLabel pass their noun through it. Both are
// declared with `const` (not `function`) so neither leaks to QML's import
// qualifier — the only public count label is spotCountLabel, read by
// BarWidget/CityHeader.
const pluralizeCount = function (count, noun) {
  var n = finiteOrZero(count);
  return n + " " + noun + (n === 1 ? "" : "s");
};

// "1 spot" / "2 spots".
function spotCountLabel(n) {
  return pluralizeCount(n, "spot");
}

// "1 open spot" / "2 open spots" — the Surprise pool's count label. The pool
// excludes permanently-closed spots, so the wording makes that self-explanatory;
// spotCountLabel stays generic for its other callers. `const` (not `function`)
// so it stays module-private: only surpriseSummary (below) calls it.
const openSpotCountLabel = function (n) {
  return pluralizeCount(n, "open spot");
};

// Search-field placeholder for a view's empty-query list length: "Search spots…",
// "Search 1 spot…", "Search 8 saved spots…". A zero count drops the numeral
// ("Search spots…", never "Search 0 spots…"); the non-zero branch pluralizes
// through pluralizeCount, the same helper spotCountLabel uses, so the two count
// labels never drift. `noun` is the bare subject ("spot", "saved spot",
// "rated spot").
function searchPlaceholderFor(count, noun) {
  if (count === 0) return "Search " + noun + "…";
  return "Search " + pluralizeCount(count, noun) + "…";
}

// Empty-list headline for a view whose list is filtered to nothing (Explore /
// Wishlist / Journal): "No spots match your search." / "No saved spots match
// your filters." — the subject noun ("", "saved", "rated") prefixes "spots",
// a city-scoped Explore inserts " in <city>", and a present query switches the
// "your filters." tail to "your search.". The collection-is-empty "yet" line
// ("No saved spots yet.") is NOT produced here — the caller keeps its own
// ternary for that branch. Strings are byte-identical to the per-tab ternaries
// this replaces.
function buildEmptyHeadline(noun, query, cityLabel) {
  return "No " + (noun ? noun + " " : "") + "spots" +
    (cityLabel ? " in " + cityLabel : "") +
    " match" + (query ? " your search." : " your filters.");
}

// Radius filter label: "Within 10 km". Shared by the FilterBar token and the
// CityHeader title so the wording stays consistent.
function radiusLabel(km) {
  return "Within " + km + SpotUtils.KM_SUFFIX;
}

// Coarse scroll bucket for viewport-gated image loading: the index of the
// `bucketHeight`-wide band `contentY` falls in. Both the outer Flickable (the
// Wishlist/Journal scroller) and the Explore ListView compute this same bucket,
// so a card's image binding re-evaluates only when the bucket changes — not on
// every scroll frame. Shared here so the two scrollers can never drift to
// different step sizes.
function computeImageWindowBucket(contentY, bucketHeight) {
  return Math.floor(contentY / bucketHeight);
}

// Trim → cap → ellipsis for a query shown in a bounded line: an over-length
// query is truncated to DISPLAY_QUERY_CAP chars with a trailing ellipsis; a
// blank/whitespace query yields "". The single source for the transform
// surpriseSummary, CityHeader's hint, and SearchSuggestionsDropdown's query row
// all need.
const DISPLAY_QUERY_CAP = 24;
function displayQueryCapped(query) {
  var trimmed = (query || "").trim();
  if (!trimmed) return "";
  return trimmed.length <= DISPLAY_QUERY_CAP ? trimmed : trimmed.slice(0, DISPLAY_QUERY_CAP) + "…";
}

// Resolve the place label for the surprise-pool breadcrumb from the active
// location scope, in precedence order: city → state → country. `cityLabel` is
// the ALREADY-RESOLVED city display name — the caller passes it because the
// panel honours a catalog-derived alias map a pure helper cannot see — so a
// non-empty `cityKey` returns it verbatim. A state scope resolves through
// stateNameFor (so "NY" renders as "New York"); a country scope is the raw
// code; "" when no location scope is selected. This is the precedence a past
// bug got wrong (it passed only the city label, so a state scope rendered as
// empty), so it must stay.
function placeLabelFor(cityKey, cityLabel, stateFilter, countryFilter) {
  if (cityKey) return cityLabel;
  if (stateFilter) return stateNameFor(stateFilter);
  if (countryFilter) return countryFilter;
  return "";
}

// Compose the surprise-pool breadcrumb line: "1 open spot in New York · \"new\"".
// The count comes from openSpotCountLabel; the place label is joined with " in "
// (the breadcrumb's place connective, distinct from SEP); the search query is
// appended as a quoted, capped segment joined with SEP — the same register
// CityHeader's ` matching "…"` suffix uses — so the pool count, its place, and
// the query that restricts it read as one line. A whitespace-only or empty
// query adds nothing, so the result never ends with a dangling separator.
function surpriseSummary(count, placeLabel, query) {
  var summary = openSpotCountLabel(count);
  if (placeLabel) summary += " in " + placeLabel;
  var shown = displayQueryCapped(query);
  if (shown) summary += SpotUtils.SEP + '"' + shown + '"';
  return summary;
}

// Coerce a spot's neighborhood to a trimmed string. String() guards a
// wrong-typed value (a JSON number smuggled in through a hand-edited
// state.json) so .trim() never throws — inside buildNeighborhoodRecords's
// chunked walk such a throw would escape before the Qt.callLater reschedule
// and leave the search index never published (silent empty panel).
function neighborhoodName(spot) {
  return String(spot.neighborhood || "").trim();
}

// Unique neighborhood names for a city, sorted alphabetically, from the city's
// neighborhood records (buildNeighborhoodRecords output — one record per
// neighborhood, first-seen order). The "All neighborhoods" clear affordance is
// supplied by the dropdown's clearLabel row and the chip strip's leading "All"
// chip, not as an item here — this list carries real neighborhoods only.
// Records (not raw spots) are the input because the filter sheet and the search
// dropdown share the same scoped index (`byCity`): a record is already deduped
// per neighborhood and drops empty names, so this only extracts + sorts.
function computeNeighborhoodNames(records) {
  var list = records || [];
  return list.map(function (record) { return record.key; }).sort();
}

// Neighborhood records for one city's spots, in first-seen order — the
// canonical definition of the neighborhood-record shape that the catalog-wide
// recordCityIndex (BarWidget.qml) and the scoped index both build.
// `spots` is the pre-resolved array for the city; `cityKey`/`cityName` label
// each record (cityName is the resolved display label, so a scoped build can
// attach its own subset's label). The representative coords come from the
// first spot with coordinates (mirrors cityDistanceKm's first-spot fallback).
function buildNeighborhoodRecords(spots, cityKey, cityName) {
  var byNeighborhood = new Map();
  var list = spots || [];
  for (var index = 0; index < list.length; index++) {
    var spot = list[index];
    var neighborhood = neighborhoodName(spot);
    if (!neighborhood) continue;
    var tally = byNeighborhood.get(neighborhood);
    if (tally === undefined) {
      // A Map keyed by the neighborhood string preserves first-seen insertion
      // order (the `order` array's old job) and can never collide with
      // Object.prototype ("constructor"/"toString" are safe keys).
      tally = { count: 0, lat: undefined, lon: undefined };
      byNeighborhood.set(neighborhood, tally);
    }
    tally.count++;
    // First located spot supplies the representative coords (mirrors
    // cityDistanceKm's first-spot fallback).
    if (tally.lat === undefined && SpotUtils.hasCoords(spot.lat, spot.lon)) {
      tally.lat = spot.lat;
      tally.lon = spot.lon;
    }
  }
  return Array.from(byNeighborhood.entries(), function (entry) {
    var neighborhood = entry[0];
    var tally = entry[1];
    return {
      key: neighborhood,
      name: neighborhood,
      foldedName: SpotUtils.foldSearchText(neighborhood),
      cityKey: cityKey,
      cityName: cityName,
      count: tally.count,
      lat: tally.lat,
      lon: tally.lon
    };
  });
}

// Shared proximity ordering: finite distances ascending, non-finite (or
// missing) distances last. Returns 0 when the two values are equal in this
// ordering (both non-finite, or both finite and equal), so callers apply their
// own tie-breaks only after this reports a tie.
function compareFiniteFirst(first, second) {
  var firstFinite = SpotUtils.isFiniteNumber(first);
  var secondFinite = SpotUtils.isFiniteNumber(second);
  if (firstFinite !== secondFinite) return firstFinite ? -1 : 1;
  if (firstFinite && first !== second) return first - second;
  return 0;
}

// Sort city keys by distance from home, nearest first, with geo-less cities
// (non-finite distance) pushed last. `decorate` maps a city key to its distance
// (km, may be Infinity). The original-order tiebreaker makes ties stable
// regardless of the engine's sort stability. Returns `{ key, distance }` records
// (the internal order index is dropped) so the caller can reuse the distance it
// already paid for — the haversine runs once here, not again at label time.
function computeSortedCities(cities, decorate) {
  var decorated = (cities || []).map(function (cityKey, index) {
    return { key: cityKey, distance: decorate(cityKey), index: index };
  });
  decorated.sort(function (first, second) {
    var finite = compareFiniteFirst(first.distance, second.distance);
    if (finite !== 0) return finite;
    return first.index - second.index;
  });
  return decorated.map(function (record) { return { key: record.key, distance: record.distance }; });
}

// Type precedence for the search-dropdown hits, used as the tie-break when two
// hits share a distance (or both are geo-less): a city is a stronger scope than
// one of its neighborhoods, so it outranks them, and a state is the broadest
// scope so it sorts last at equal distance. Returns an ascending rank index so
// the comparator can subtract them.
function searchHitTypeRank(type) {
  if (type === SCOPE_CITY) return 0;
  if (type === SCOPE_NEIGHBORHOOD) return 1;
  return 2; // state and any unknown type rank last, so the comparator stays total
}

// Deterministic name/key tie-break for equal-scope hits. The key (a city key or
// state code) is the final fallback so two hits with identical names still order
// deterministically rather than shuffling between renders. Comparison goes
// through compareStringsAscending — the same no-ICU rule as the price sort's
// name fallback — so the order is identical across Node and QJSEngine (no
// locale-dependent collation), including for non-ASCII names.
function compareSearchHitNameThenKey(first, second) {
  var nameDelta = compareStringsAscending(String(first.name || ""), String(second.name || ""));
  if (nameDelta !== 0) return nameDelta;
  return compareStringsAscending(String(first.key || ""), String(second.key || ""));
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
    var finite = compareFiniteFirst(firstDistance, secondDistance);
    if (finite !== 0) return finite;
    if (!SpotUtils.isFiniteNumber(firstDistance) && first.type === SCOPE_STATE && second.type === SCOPE_STATE) {
      // Geo-less states: the count-descending-then-name fallback.
      if (first.count !== second.count) return second.count - first.count;
      return compareSearchHitNameThenKey(first, second);
    }
    var firstRank = searchHitTypeRank(first.type);
    var secondRank = searchHitTypeRank(second.type);
    if (firstRank !== secondRank) return firstRank - secondRank;
    return compareSearchHitNameThenKey(first, second);
  });
  return list;
}

// Match a folded candidate against the folded term: prefix-only below 2
// characters, substring at 2+. Both sides are already folded, so the comparison
// is accent-insensitive like the card-list rank path.
function searchHitMatchesTerm(candidate, term, prefixOnly) {
  var hit = candidate.indexOf(term);
  return prefixOnly ? hit === 0 : hit >= 0;
}

// One city's search hits: the city itself (when its folded display name or key
// matches) plus each neighborhood record that matches. The per-city neighborhood
// tally is precomputed in `index.byCity`, so this only scans the cached records
// — no per-keystroke rescan of all spots. `cityDistance`/`neighborhoodDistance`
// are injected (km from home, may be Infinity when geo-less) so this stays pure.
function buildCitySearchHits(cityKey, index, term, prefixOnly, cityDistance, neighborhoodDistance) {
  var hits = [];
  var cityName = index.names[cityKey];
  if (searchHitMatchesTerm(index.foldedNames[cityKey], term, prefixOnly) || searchHitMatchesTerm(index.foldedKeys[cityKey], term, prefixOnly)) {
    hits.push({ type: SCOPE_CITY, key: cityKey, name: cityName, count: index.counts[cityKey], distance: cityDistance(cityKey) });
  }
  var records = index.byCity[cityKey];
  records.forEach(function (nb) {
    if (searchHitMatchesTerm(nb.foldedName, term, prefixOnly)) {
      hits.push({ type: SCOPE_NEIGHBORHOOD, key: nb.key, name: nb.name, cityKey: nb.cityKey, cityName: nb.cityName, count: nb.count, distance: neighborhoodDistance(nb) });
    }
  });
  return hits;
}

// A state's single search hit, or null: the state matches its 2-letter code OR
// its full name (via stateNameFor), folded like the rest of the search path, so
// a name-bearing query ("new") reaches New Jersey / New York / New Mexico / New
// Hampshire — the raw code alone could never match. The hit is labelled with the
// readable full name; its `key` stays the code for selectState/stateFilter. Its
// `distance` is the nearest spot in that state (stateDistances), so a state
// carries its own proximity like a city/neighborhood hit — undefined when every
// spot in the state lacks coordinates.
function buildStateSearchHit(stateHit, term, prefixOnly, stateDistances) {
  if (!searchHitMatchesTerm(stateHit.foldedCode, term, prefixOnly) &&
      !searchHitMatchesTerm(stateHit.foldedName, term, prefixOnly)) return null;
  return { type: SCOPE_STATE, key: stateHit.key, name: stateNameFor(stateHit.key), count: stateHit.count, distance: stateDistances[stateHit.key] };
}

// City/neighborhood/state matches for the search dropdown. Returns
// { type: "city", key, name, count, distance } or
// { type: "neighborhood", key, name, cityKey, cityName, count, distance } or
// { type: "state", key, name, count, distance }.
// The per-city neighborhood tally is independent of the query, so it is
// precomputed once per catalog version (searchIndex) and this function only
// filters the cached city names + neighborhood records + the cached states — no
// per-keystroke rescan of all spots. `index`, `states`, and `stateDistances`
// are parameters so one body serves both the catalog-wide source
// (root.searchIndex/root.stateOptions/root.locationAggregates.stateDistances)
// and the scoped Wishlist/Journal bundles (buildScopedSearchIndex);
// `cityDistance`/`neighborhoodDistance` are the injected distance resolvers.
function buildSearchHits(query, index, states, stateDistances, cityDistance, neighborhoodDistance) {
  if (!index || !index.cities) return [];
  var term = SpotUtils.foldSearchText(query);
  if (!term) return [];
  // Ultra-short queries get no loose matching: below 2 characters the match
  // is prefix-only (the entry starts with the term), so a single character
  // opens the dropdown without drowning it in substring noise. At 2+
  // characters the match is the substring scan used before.
  var prefixOnly = term.length < 2;
  var cityHits = index.cities.reduce(function (acc, cityKey) {
    return acc.concat(buildCitySearchHits(cityKey, index, term, prefixOnly, cityDistance, neighborhoodDistance));
  }, []);
  var stateHits = [];
  states.forEach(function (stateHit) {
    var hit = buildStateSearchHit(stateHit, term, prefixOnly, stateDistances);
    if (hit) stateHits.push(hit);
  });
  // Order the hits uniformly by proximity: finite distance ascending, geo-less
  // last, type as the tie-break, then name/key. Each hit carries its own
  // `distance` (computed above) so the sort reads it directly.
  return sortSearchHits(cityHits.concat(stateHits));
}

// One spot's step in the location-aggregation pass: normalize state/country,
// count the (US-gated) state and every non-empty country, track the value of the
// spot nearest home (only a genuine US state qualifies as `nearestState` — a
// foreign region code, even one that collides with a US state code, must not
// promote one), and record the nearest-spot distance per US state (geo-less
// spots — undefined/Infinity — never enter). Mutates the `agg` accumulators (all
// null-prototype) in place; the caller owns their construction and the final
// bundle shape.
function addLocation(spot, agg, distanceFor) {
  var normalized = normalizeStateCountry(spot);
  var stateValue = normalized.state;
  var countryValue = normalized.country;
  // Same predicate as isUsState, applied to the already-normalized fields —
  // this loop holds loose fields, not a spot object to pass through it.
  var usState = isUsStateCode(stateValue, countryValue);
  if (usState) agg.stateCounts[stateValue] = (agg.stateCounts[stateValue] || 0) + 1;
  if (countryValue) agg.countryCounts[countryValue] = (agg.countryCounts[countryValue] || 0) + 1;
  var distanceKm = distanceFor(spot);
  if (distanceKm !== undefined && distanceKm < agg.nearestDistance) {
    agg.nearestDistance = distanceKm;
    agg.nearestState = usState ? stateValue : "";
    agg.nearestCountry = countryValue;
  }
  if (usState && SpotUtils.isFiniteNumber(distanceKm) &&
      (agg.stateDistances[stateValue] === undefined || distanceKm < agg.stateDistances[stateValue])) {
    agg.stateDistances[stateValue] = distanceKm;
  }
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
  var agg = {
    stateCounts: Object.create(null),
    countryCounts: Object.create(null),
    stateDistances: Object.create(null),
    nearestState: "",
    nearestCountry: "",
    nearestDistance: Infinity
  };
  var list = spots || [];
  for (var index = 0; index < list.length; index++) {
    addLocation(list[index], agg, distanceFor);
  }
  return {
    stateCounts: agg.stateCounts,
    countryCounts: agg.countryCounts,
    nearestState: agg.nearestState,
    nearestCountry: agg.nearestCountry,
    stateDistances: agg.stateDistances
  };
}

// One entry's step in the scoped-index build: bucket the entry's spot into its
// city — creating the city's names/foldedNames/foldedKeys/count accumulators on
// first sight — and append it to the flat spot list the location aggregates
// consume. Null entries (no spot) are skipped. Mutates the `bucket` accumulators
// (all null-prototype) in place; the caller owns their construction.
function addScopedEntry(bucket, entry) {
  if (!entry || !entry.spot) return;
  var spot = entry.spot;
  var cityKey = entry.cityKey || "";
  bucket.flatSpots.push(spot);
  if (!bucket.spotsByCity[cityKey]) {
    bucket.spotsByCity[cityKey] = [];
    bucket.cities.push(cityKey);
    bucket.counts[cityKey] = 0;
    var label = cityLabelFor(cityKey);
    bucket.names[cityKey] = label;
    bucket.foldedNames[cityKey] = SpotUtils.foldSearchText(label);
    bucket.foldedKeys[cityKey] = SpotUtils.foldSearchText(cityKey);
  }
  bucket.spotsByCity[cityKey].push(spot);
  bucket.counts[cityKey]++;
}

// Assemble a location bundle from its nine fields. The bundle is the single
// shape the search dropdown, the filter sheet, and the scoped index all consume:
// {cities, names, counts, byCity, foldedNames, foldedKeys, states, countries,
// stateDistances}. Both the catalog-wide producer (BarWidget's
// activeLocationBundle, assembled from searchIndex + stateOptions + countries +
// locationAggregates) and the scoped producer (buildScopedSearchIndex) build it
// through this one shaper, so the two cannot drift to different field sets.
function buildLocationBundle(parts) {
  return {
    cities: parts.cities,
    names: parts.names,
    counts: parts.counts,
    byCity: parts.byCity,
    foldedNames: parts.foldedNames,
    foldedKeys: parts.foldedKeys,
    states: parts.states,
    countries: parts.countries,
    stateDistances: parts.stateDistances
  };
}

// Build a scoped search index from a subset of catalog spots — a superset of
// the searchIndex shape, so buildSearchHits consumes it directly. `entries` is
// [{ spot, cityKey }] (null spots skipped); `distanceFor` is an injected
// `(spot) => km | undefined` resolver. Each city's count and neighborhood
// records come from the subset's spots alone, so a Wishlist/Journal scope
// surfaces only geography reachable from the user's own saved/rated spots —
// never the catalog-wide aggregates. `states`/`stateDistances`/`countries` are
// derived via computeLocationAggregates + sortedCountList on the same subset.
// Returns an empty bundle (not null) for null/empty input so callers need no
// special case. All name-keyed maps are null-prototype. The returned shape is
// built through buildLocationBundle so it must track `recordCityIndex`/
// `searchIndex` (catalog-wide) and `activeLocationBundle` (BarWidget.qml) — the
// three build the same bundle independently (chunked walk vs one-shot loop vs
// assembled view source) and must not drift.
function buildScopedSearchIndex(entries, distanceFor) {
  var bucket = {
    cities: [],
    names: Object.create(null),
    counts: Object.create(null),
    foldedNames: Object.create(null),
    foldedKeys: Object.create(null),
    spotsByCity: Object.create(null),
    flatSpots: []
  };
  var list = entries || [];
  for (var index = 0; index < list.length; index++) {
    addScopedEntry(bucket, list[index]);
  }
  var byCity = Object.create(null);
  for (var cityIndex = 0; cityIndex < bucket.cities.length; cityIndex++) {
    var key = bucket.cities[cityIndex];
    byCity[key] = buildNeighborhoodRecords(bucket.spotsByCity[key], key, bucket.names[key]);
  }
  var resolveDistance = (typeof distanceFor === "function") ? distanceFor : function () { return undefined; };
  var aggregates = computeLocationAggregates(bucket.flatSpots, resolveDistance);
  var states = buildStateOptions(aggregates);
  return buildLocationBundle({
    cities: bucket.cities,
    names: bucket.names,
    counts: bucket.counts,
    byCity: byCity,
    foldedNames: bucket.foldedNames,
    foldedKeys: bucket.foldedKeys,
    states: states,
    countries: sortedCountList(aggregates.countryCounts, aggregates.nearestCountry),
    stateDistances: aggregates.stateDistances
  });
}

// " · N spots" — the shared count tail the city/state/country dropdown labels
// and the search-hit secondary label append after the name (SEP +
// spotCountLabel). Extracted so the three label builders can never drift to
// different separators.
function countSuffix(count) {
  return SpotUtils.SEP + spotCountLabel(count);
}

// Search-dropdown secondary label for one hit, varying by type: a neighborhood
// hit shows its parent city + count ("New York City · 4 spots"), a state hit is
// prefixed "All of <name>" ("All of New York · 214 spots"), and a plain city
// hit leads only with the folded separator ("· 214 spots" — the city name
// already renders as the row's primary label, so the separator is the inline
// form, not SEP). `hit` is a buildSearchHits hit ({ type, key, name, count, … });
// SCOPE_NEIGHBORHOOD/SCOPE_STATE are the same type constants the hit builders
// use. Moved out of SearchSuggestionsDropdown.qml so the strings live with the
// other label builders.
function searchHitLabel(hit) {
  if (!hit) return "";
  if (hit.type === SCOPE_NEIGHBORHOOD) return hit.cityName + countSuffix(hit.count);
  if (hit.type === SCOPE_STATE) return "All of " + hit.name + countSuffix(hit.count);
  return SpotUtils.SEP_LEAD + spotCountLabel(hit.count);
}

// Build { key, label } pairs for the city filter dropdown. Pure: inputs are
// passed explicitly, so it is unit-testable and reusable verbatim from QML.
// `sortedCities` is the computeSortedCities output — `{ key, distance }` records
// (distance in km, may be Infinity) — and the label formats that record's own
// distance, so the haversine still runs once (in computeSortedCities), never
// again here. `countFor` resolves a city key to its spot count — injected so the
// catalog-wide path reads the search index and a scoped (Wishlist/Journal) path
// reads its own subset, one builder serving both. City dropdown: "New York City
// · 3.2 km · 42 spots". The name comes from cityLabelFor (the CITY_META name,
// else the title-cased slug — the same seam the widget's cityLabel falls back
// to), the distance from the record's own `distance`, and the count from
// `countFor`.
function buildCityFilterItems(sortedCities, countFor) {
  return (sortedCities || []).map(function (record) {
    var count = (typeof countFor === "function") ? (countFor(record.key) || 0) : 0;
    var distance = SpotUtils.isFiniteNumber(record.distance) ? SpotUtils.formatDistance(record.distance) : "";
    var label = cityLabelFor(record.key) + (distance ? SpotUtils.SEP + distance : "") + countSuffix(count);
    return { key: record.key, label: label };
  });
}

// State/country dropdown items: "NY · 12 spots", "US · 42 spots". The label
// keys off the item's own `key` (the 2-letter code), not a display-name map —
// unlike the city dropdown, which resolves a display name via cityLabelFor.
function buildCodeCountItems(list) {
  return (list || []).map(function (item) {
    return { key: item.key, label: item.key + countSuffix(item.count) };
  });
}

// Neighborhood dropdown: the name unchanged. The "All neighborhoods" clear row
// is the dropdown's clearLabel (see FilterSheet.qml), not an item in this list.
function buildNeighborhoodFilterItems(neighborhoods) {
  return (neighborhoods || []).map(function (nb) {
    return { key: nb, label: nb };
  });
}

// Whether a spot is eligible for the surprise pool: a real spot that is not
// permanently closed. `_isClosed` is the stamped field SpotCard's "Closed"
// badge reads; the surprise pool excludes closed spots (and only here — the
// normal list/filter semantics are unchanged). Shared by surprisePoolSize and
// surpriseMe so the pool-membership rule is stated once.
function isSurpriseEligible(spot) {
  return !!(spot && !spot._isClosed);
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

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    VIEW_EXPLORE,
    VIEW_WISHLIST,
    VIEW_JOURNAL,
    VIEW_SPOTLIGHT,
    SCOPE_CITY,
    SCOPE_STATE,
    SCOPE_COUNTRY,
    SCOPE_NEIGHBORHOOD,
    KIND_FILTER_ALL,
    EMPTY_STATE_CAPTION,
    EMPTY_STATE_CLEAR_ACTION_LABEL,
    SORT_KEYS,
    displayQueryCapped,
    nextRadiusStep,
    catalogSpotsHash,
    CITY_META,
    cityMetaFor,
    US_STATES,
    US_STATE_NAMES,
    stateNameFor,
    normalizeStateCountry,
    isUsState,
    coordKey,
    stageSpotDistance,
    isSortDescending,
    capitalizeFirst,
    kindLabelFor,
    phoneActionLabel,
    sortBySpec,
    makeSortSpecs,
    sortedCountList,
    cityLabelFor,
    unpluralizedCountLabel,
    spotCountLabel,
    searchPlaceholderFor,
    buildEmptyHeadline,
    radiusLabel,
    computeImageWindowBucket,
    foldSpot,
    indexSpot,
    foldedContains,
    entryMatchesQuery,
    resolveFilterSort,
    buildRatingMaps,
    rankSpots,
    placeLabelFor,
    surpriseSummary,
    computeNeighborhoodNames,
    buildNeighborhoodRecords,
    computeSortedCities,
    sortSearchHits,
    searchHitMatchesTerm,
    buildCitySearchHits,
    buildStateSearchHit,
    buildSearchHits,
    searchHitLabel,
    computeLocationAggregates,
    buildScopedSearchIndex,
    buildLocationBundle,
    buildStateOptions,
    buildCityFilterItems,
    buildCodeCountItems,
    buildNeighborhoodFilterItems,
    isSurpriseEligible,
    pickRandom
  };
}
