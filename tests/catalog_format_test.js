// tests/catalog_format_test.js — catalog-utils.js distance-cache helpers
// (coordKey/stageSpotDistance), label/empty-state/formatting tests
const M = require("../catalog-utils.js");
const Spot = require("../spot-utils.js");
const { assert, assertEq, report } = require("./_assert.js");

// ----- coordKey -----
assert("coordKey formats lat/lon", M.coordKey(40.7, -74.0) === "40.7|-74");
assert("coordKey zero coords", M.coordKey(0, 0) === "0|0");
// Validity follows SpotUtils.hasCoords (finite, including 0): a missing/blank/
// NaN coordinate keys to "" so it can never collide with the genuine (0, 0).
assert("coordKey missing coords key empty", M.coordKey(null, undefined) === "");
assert("coordKey NaN coords key empty", M.coordKey(NaN, 5) === "");
assert("coordKey blank-string coords key empty", M.coordKey("", "-74.0") === "");
assert("coordKey distinguishes axis order", M.coordKey(1, 2) !== M.coordKey(2, 1));

// ----- stageSpotDistance (per-coordinate distance-cache step) -----
assert("stageSpotDistance stages a haversine keyed by coordKey",
  (function () {
    const staged = Object.create(null);
    M.stageSpotDistance({ lat: 40.7, lon: -74.0 }, 40.0, -74.0, staged);
    return staged["40.7|-74"] !== undefined && Number.isFinite(staged["40.7|-74"]);
  })());
assert("stageSpotDistance first write wins over a second spot with same coords",
  (function () {
    const staged = Object.create(null);
    M.stageSpotDistance({ lat: 1, lon: 1 }, 0, 0, staged);
    const first = staged["1|1"];
    M.stageSpotDistance({ lat: 1, lon: 1 }, 90, 90, staged);
    return staged["1|1"] === first;
  })());
assert("stageSpotDistance geo-less spot stages nothing",
  (function () {
    const staged = Object.create(null);
    M.stageSpotDistance({ lat: null, lon: -74.0 }, 0, 0, staged);
    return Object.keys(staged).length === 0;
  })());

// ----- catalogSpotsHash (deterministic content fingerprint) -----
assert("catalogSpotsHash is deterministic for equal content",
  M.catalogSpotsHash({ nyc: [{ name: "A" }] }) === M.catalogSpotsHash({ nyc: [{ name: "A" }] }));
assert("catalogSpotsHash differs when content differs",
  M.catalogSpotsHash({ nyc: [{ name: "A" }] }) !== M.catalogSpotsHash({ nyc: [{ name: "B" }] }));

// ----- titleCaseCitySlug (reached via cityLabelFor) -----
// titleCaseCitySlug is module-private; the title-cased-slug fallback is reached
// through cityLabelFor, which resolves a CITY_META name first and title-cases
// only unknown keys. "los-angeles" IS a CITY_META key, so it pins the known-key
// path (the name, not the slug); the multi-hyphen / plain / empty cases below
// are unknown keys and exercise the title-cased fallback.
assert("cityLabelFor known CITY_META key resolves to its name", M.cityLabelFor("los-angeles") === "Los Angeles");
assert("titleCaseCitySlug multi-hyphen slug", M.cityLabelFor("san-francisco-bay-area") === "San Francisco Bay Area");
assert("titleCaseCitySlug plain key title-cases first letter only", M.cityLabelFor("xyz") === "Xyz");
assert("titleCaseCitySlug empty", M.cityLabelFor("") === "");
assert("titleCaseCitySlug null", M.cityLabelFor(null) === "");

// ----- spotCountLabel -----
assert("spotCountLabel zero", M.spotCountLabel(0) === "0 spots");
assert("spotCountLabel one", M.spotCountLabel(1) === "1 spot");
assert("spotCountLabel two", M.spotCountLabel(2) === "2 spots");
assert("spotCountLabel undefined", M.spotCountLabel(undefined) === "0 spots");

// ----- unpluralizedCountLabel (invariant nouns — never pluralized) -----
assert("unpluralizedCountLabel saved singular", M.unpluralizedCountLabel(1, "saved") === "1 saved");
assert("unpluralizedCountLabel saved plural stays invariant", M.unpluralizedCountLabel(2, "saved") === "2 saved");
assert("unpluralizedCountLabel rated plural stays invariant", M.unpluralizedCountLabel(3, "rated") === "3 rated");
assert("unpluralizedCountLabel undefined", M.unpluralizedCountLabel(undefined, "saved") === "0 saved");

// ----- searchPlaceholderFor (search-field placeholder for a view's list) -----
// The placeholder names what typing will search; a zero count drops the numeral
// entirely and the non-zero branch pluralizes via pluralizeCount. `noun` is the
// bare subject ("spot", "saved spot", "rated spot").
assert("searchPlaceholderFor zero count drops the numeral",
  M.searchPlaceholderFor(0, "spot") === "Search spot…");
assert("searchPlaceholderFor one count singular",
  M.searchPlaceholderFor(1, "spot") === "Search 1 spot…");
assert("searchPlaceholderFor many count plural",
  M.searchPlaceholderFor(8, "spot") === "Search 8 spots…");
assert("searchPlaceholderFor multi-word noun pluralizes the head",
  M.searchPlaceholderFor(8, "saved spot") === "Search 8 saved spots…");
assert("searchPlaceholderFor multi-word noun singular",
  M.searchPlaceholderFor(1, "rated spot") === "Search 1 rated spot…");

// ----- searchHitLabel (search-dropdown secondary count label) -----
// One shape per hit type: a city hit leads with the folded separator (the city
// name is the row's primary label), a neighborhood hit names its parent city,
// and a state hit is prefixed "All of". The count goes through spotCountLabel
// and the separator through SpotUtils.SEP / SEP_LEAD.
assert("searchHitLabel city hit leads with folded separator",
  M.searchHitLabel({ type: "city", key: "nyc", name: "New York City", count: 214 }) === "· 214 spots");
assert("searchHitLabel neighborhood hit shows parent city",
  M.searchHitLabel({ type: "neighborhood", key: "SoHo", name: "SoHo", cityName: "New York City", count: 1 }) === "New York City · 1 spot");
assert("searchHitLabel state hit prefixed 'All of'",
  M.searchHitLabel({ type: "state", key: "NY", name: "New York", count: 214 }) === "All of New York · 214 spots");
assert("searchHitLabel state hit singular count",
  M.searchHitLabel({ type: "state", key: "NY", name: "New York", count: 1 }) === "All of New York · 1 spot");
assert("searchHitLabel city no-count",
  M.searchHitLabel({ type: "city", key: "nyc", name: "New York City", count: 0 }) === "· 0 spots");
assert("searchHitLabel null hit",
  M.searchHitLabel(null) === "");

// ----- buildEmptyHeadline (empty-state headline for Explore/Wishlist/Journal) -----
// Byte-identical to the per-tab ternaries this replaces. `noun` is the subject
// adjective ("", "saved", "rated"); a query switches the tail to "your search.",
// no query keeps "your filters.", and Explore passes a city label for its
// city-scoped variant.
assert("buildEmptyHeadline explore unscoped no query", M.buildEmptyHeadline("", "", "") === "No spots match your filters.");
assert("buildEmptyHeadline explore unscoped query", M.buildEmptyHeadline("", "new", "") === "No spots match your search.");
assert("buildEmptyHeadline explore city no query", M.buildEmptyHeadline("", "", "New York City") === "No spots in New York City match your filters.");
assert("buildEmptyHeadline explore city query", M.buildEmptyHeadline("", "new", "New York City") === "No spots in New York City match your search.");
assert("buildEmptyHeadline wishlist no query", M.buildEmptyHeadline("saved", "", "") === "No saved spots match your filters.");
assert("buildEmptyHeadline wishlist query", M.buildEmptyHeadline("saved", "new", "") === "No saved spots match your search.");
assert("buildEmptyHeadline journal no query", M.buildEmptyHeadline("rated", "", "") === "No rated spots match your filters.");
assert("buildEmptyHeadline journal query", M.buildEmptyHeadline("rated", "new", "") === "No rated spots match your search.");

// ----- capitalizeFirst -----
// capitalizeFirst is the public capitalization helper (single-word filter
// labels like "omakase"/"rating"); kindLabelFor uses the KIND_LABELS map
// instead, so the AYCE acronym can't go through capitalizeFirst.
assert("capitalizeFirst lower", M.capitalizeFirst("omakase") === "Omakase");
assert("capitalizeFirst already upper", M.capitalizeFirst("Omakase") === "Omakase");
assert("capitalizeFirst empty", M.capitalizeFirst("") === "");
assert("capitalizeFirst undefined", M.capitalizeFirst(undefined) === "");
assert("capitalizeFirst null", M.capitalizeFirst(null) === "");
assert("capitalizeFirst single char", M.capitalizeFirst("a") === "A");

// ----- kindLabelFor -----
// AYCE is an acronym — the rendered label differs from capitalizeFirst(). The kind
// VALUES stay lowercase; only this mapping's output is user-facing.
assert("kindLabelFor ayce is the acronym AYCE", M.kindLabelFor("ayce") === "AYCE");
assert("kindLabelFor discount", M.kindLabelFor("discount") === "Discount");
assert("kindLabelFor omakase", M.kindLabelFor("omakase") === "Omakase");
assert("kindLabelFor unknown kind", M.kindLabelFor("bogus") === "");
assert("kindLabelFor empty", M.kindLabelFor("") === "");
assert("kindLabelFor null", M.kindLabelFor(null) === "");

// ----- phoneActionLabel -----
assert("phoneActionLabel handler present dials", M.phoneActionLabel(true) === "Call");
assert("phoneActionLabel no handler copies", M.phoneActionLabel(false) === "Copy number");

// ----- radiusLabel -----
assert("radiusLabel", M.radiusLabel(10) === "Within 10 km");
assert("radiusLabel five", M.radiusLabel(5) === "Within 5 km");
assert("radiusLabel zero", M.radiusLabel(0) === "Within 0 km");
// KM_SUFFIX is owned by spot-utils; radiusLabel reads it lazily, so the shared
// suffix value is pinned here against the owner.
assert("radiusLabel reads SpotUtils.KM_SUFFIX (single owner)", Spot.KM_SUFFIX === " km" && M.radiusLabel(7) === "Within 7 km");

// ----- computeImageWindowBucket -----
assert("computeImageWindowBucket zero contentY", M.computeImageWindowBucket(0, 200) === 0);
assert("computeImageWindowBucket within first bucket", M.computeImageWindowBucket(199, 200) === 0);
assert("computeImageWindowBucket boundary rolls to next", M.computeImageWindowBucket(200, 200) === 1);
assert("computeImageWindowBucket floors", M.computeImageWindowBucket(450, 200) === 2);
assert("computeImageWindowBucket floors at bucket end", M.computeImageWindowBucket(799, 200) === 3);

// ----- EMPTY_STATE_CAPTION -----
assert("EMPTY_STATE_CAPTION value", M.EMPTY_STATE_CAPTION === "Try a different search or clear your filters.");

// ----- placeLabelFor -----
// The breadcrumb's place scope resolves in precedence order city → state →
// country. `cityLabel` is the already-resolved city display name (the panel
// passes it because it honours a catalog-derived alias map a pure helper cannot
// see); a non-empty `cityKey` selects it. A state scope yields the FULL name
// via stateNameFor — the "NY" → "New York" behaviour a past bug fix established
// (the bug passed only the city label, so a state scope rendered empty) — and a
// country scope yields the raw code. All-empty yields "".
assert("placeLabelFor city key selects the resolved label",
  M.placeLabelFor("nyc", "New York City", "", "") === "New York City");
assert("placeLabelFor city beats state and country",
  M.placeLabelFor("nyc", "New York City", "NY", "US") === "New York City");
assert("placeLabelFor state falls back to the full name",
  M.placeLabelFor("", "", "NY", "") === "New York");
assert("placeLabelFor state beats country",
  M.placeLabelFor("", "", "NY", "US") === "New York");
assert("placeLabelFor country falls back to the raw code",
  M.placeLabelFor("", "", "", "US") === "US");
assert("placeLabelFor all-empty yields empty string",
  M.placeLabelFor("", "", "", "") === "");

// ----- surpriseSummary -----
// The breadcrumb is the pool count, the place scope, and the query that
// restricts the pool, joined as "1 open spot in New York · \"new\"". The place is
// joined with " in " (the breadcrumb's place connective, distinct from SEP);
// the query is a quoted, capped segment joined with SEP. A whitespace-only or
// empty query adds nothing, so the line never ends with a dangling separator.
assert("surpriseSummary count only",
  M.surpriseSummary(1, "", "") === "1 open spot");
assert("surpriseSummary count + place",
  M.surpriseSummary(1, "New York", "") === "1 open spot in New York");
assert("surpriseSummary count + place + query",
  M.surpriseSummary(1, "New York", "new") === '1 open spot in New York · "new"');
assert("surpriseSummary count + query with no place",
  M.surpriseSummary(1, "", "new") === '1 open spot · "new"');
assert("surpriseSummary empty query adds nothing",
  M.surpriseSummary(2, "Tokyo", "") === "2 open spots in Tokyo");
assert("surpriseSummary whitespace-only query adds nothing",
  M.surpriseSummary(2, "Tokyo", "   ") === "2 open spots in Tokyo");
assert("surpriseSummary zero count has no dangling separator",
  M.surpriseSummary(0, "", "") === "0 open spots");
// A 24-char query fits the display cap verbatim; a 25-char query is truncated
// to 24 plus the same ellipsis displayQueryCapped uses.
assert("surpriseSummary 24-char query fits the cap",
  M.surpriseSummary(1, "", "abcdefghijklmnopqrstuvwx") === '1 open spot · "abcdefghijklmnopqrstuvwx"');
assert("surpriseSummary longer query capped with ellipsis",
  M.surpriseSummary(1, "", "abcdefghijklmnopqrstuvwxy") === '1 open spot · "abcdefghijklmnopqrstuvwx…"');

// ----- displayQueryCapped -----
// The trim → cap → ellipsis transform the three query renderers (CityHeader's
// hint, SearchSuggestionsDropdown's query row, and the surpriseSummary
// breadcrumb's query segment) share.
assertEq("displayQueryCapped blank query", M.displayQueryCapped(""), "");
assertEq("displayQueryCapped null query", M.displayQueryCapped(null), "");
assertEq("displayQueryCapped whitespace-only query", M.displayQueryCapped("   "), "");
assertEq("displayQueryCapped 24-char query fits verbatim", M.displayQueryCapped("abcdefghijklmnopqrstuvwx"), "abcdefghijklmnopqrstuvwx");
assertEq("displayQueryCapped truncates to 24 + ellipsis", M.displayQueryCapped("abcdefghijklmnopqrstuvwxy"), "abcdefghijklmnopqrstuvwx…");
// Trim runs before the cap counts, so leading whitespace never consumes budget.
assertEq("displayQueryCapped trims before capping", M.displayQueryCapped("  abcdef"), "abcdef");

// ----- build*FilterItems -----
assert("buildCityFilterItems name + distance + count",
  (function () {
    const items = M.buildCityFilterItems(
      [{ key: "nyc", distance: 3.2 }, { key: "los-angeles", distance: Infinity }],
      (k) => ({ nyc: 2, "los-angeles": 1 }[k])
    );
    return JSON.stringify(items.map((i) => i.key)) === '["nyc","los-angeles"]' &&
           JSON.stringify(items.map((i) => i.label)) === '["New York City · 3.2 km · 2 spots","Los Angeles · 1 spot"]';
  })());

assert("buildCityFilterItems empty distance omitted",
  (function () {
    const items = M.buildCityFilterItems([{ key: "nyc", distance: Infinity }], (k) => 3);
    return JSON.stringify(items.map((i) => i.key)) === '["nyc"]' &&
           JSON.stringify(items.map((i) => i.label)) === '["New York City · 3 spots"]';
  })());

assert("buildCityFilterItems count comes from the resolver, not a spots map",
  (function () {
    // The count-for contract: a view-scoped counts map (not a spots array) is
    // the source — a city absent from the view counts 0 and still renders.
    const counts = Object.create(null);
    counts.nyc = 2;
    const items = M.buildCityFilterItems(
      [{ key: "nyc", distance: Infinity }, { key: "absent", distance: Infinity }],
      (k) => counts[k] || 0
    );
    return JSON.stringify(items.map((i) => i.key)) === '["nyc","absent"]' &&
           JSON.stringify(items.map((i) => i.label)) === '["New York City · 2 spots","Absent · 0 spots"]';
  })());

assert("buildCodeCountItems state codes",
  (function () {
    const items = M.buildCodeCountItems([{ key: "NY", count: 2 }, { key: "CA", count: 1 }]);
    return JSON.stringify(items.map((i) => i.key)) === '["NY","CA"]' &&
           JSON.stringify(items.map((i) => i.label)) === '["NY · 2 spots","CA · 1 spot"]';
  })());

assert("buildCodeCountItems country code",
  (function () {
    const items = M.buildCodeCountItems([{ key: "US", count: 3 }]);
    return JSON.stringify(items.map((i) => i.key)) === '["US"]' &&
           JSON.stringify(items.map((i) => i.label)) === '["US · 3 spots"]';
  })());

assert("buildNeighborhoodFilterItems",
  (function () {
    const items = M.buildNeighborhoodFilterItems(["SoHo", "Chelsea"]);
    return JSON.stringify(items.map((i) => i.key)) === '["SoHo","Chelsea"]' &&
           JSON.stringify(items.map((i) => i.label)) === '["SoHo","Chelsea"]';
  })());

// ----- pickRandom -----
assert("pickRandom empty pool returns null", M.pickRandom([], Math.random) === null);
assert("pickRandom null pool returns null", M.pickRandom(null, Math.random) === null);
assert("pickRandom single spot with no exclusion returns it",
  M.pickRandom([{ name: "Solo" }], Math.random).name === "Solo");
assert("pickRandom single spot with matching exclusion returns null",
  M.pickRandom([{ name: "Solo" }], Math.random, "Solo") === null);
assert("pickRandom deterministic given fixed rng",
  M.pickRandom([{ name: "A" }, { name: "B" }, { name: "C" }], function () { return 0.5; }).name === "B");
assert("pickRandom never returns the excluded name (2+ spots)",
  (function () {
    var pool = [{ name: "A" }, { name: "B" }, { name: "C" }];
    for (var i = 0; i < 20; i++) {
      if (M.pickRandom(pool, Math.random, "A").name === "A") return false;
    }
    return true;
  })());
assert("pickRandom rng at 1.0 clamps to last candidate",
  M.pickRandom([{ name: "A" }, { name: "B" }], function () { return 1.0; }).name === "B");
assert("pickRandom negative rng clamps to first candidate",
  M.pickRandom([{ name: "A" }, { name: "B" }], function () { return -0.5; }).name === "A");
assert("pickRandom exclusion not in pool still returns a candidate",
  M.pickRandom([{ name: "A" }, { name: "B" }], function () { return 0; }, "Z").name === "A");

// ----- isSurpriseEligible -----
assert("isSurpriseEligible open spot", M.isSurpriseEligible({ name: "A", _isClosed: false }) === true);
assert("isSurpriseEligible closed spot", M.isSurpriseEligible({ name: "A", _isClosed: true }) === false);
assert("isSurpriseEligible missing _isClosed is open", M.isSurpriseEligible({ name: "A" }) === true);
assert("isSurpriseEligible null spot", M.isSurpriseEligible(null) === false);
assert("isSurpriseEligible undefined spot", M.isSurpriseEligible(undefined) === false);


report();
