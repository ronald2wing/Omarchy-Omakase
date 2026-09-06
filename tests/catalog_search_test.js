// tests/catalog_search_test.js — catalog-utils.js search tests (fold/rank/scoped index)
const M = require("../catalog-utils.js");
const S = require("../spot-utils.js");
const { assert, report } = require("./_assert.js");

// ----- foldSpot -----
assert("foldSpot folds name/neighborhood",
  (function () {
    const folded = M.foldSpot({ name: "Saké", neighborhood: "SoHo" });
    return folded.name === "sake" && folded.neighborhood === "soho";
  })());
assert("foldSpot empty spot folds empty strings",
  (function () {
    const folded = M.foldSpot({});
    return folded.name === "" && folded.neighborhood === "";
  })());
assert("foldSpot null spot",
  (function () {
    const folded = M.foldSpot(null);
    return folded.name === "" && folded.neighborhood === "";
  })());

// ----- foldedContains (Journal/Wishlist accent-insensitive search) -----
assert("foldedContains sake matches Saké", M.foldedContains("Saké", "sake") === true);
assert("foldedContains saké query matches sake", M.foldedContains("sake", "saké") === true);
assert("foldedContains cote matches Côté Sushi", M.foldedContains("Côté Sushi", "cote") === true);
assert("foldedContains poke matches Poké King", M.foldedContains("Poké King", "poke") === true);
assert("foldedContains sao paulo matches São Paulo", M.foldedContains("São Paulo", "sao paulo") === true);
assert("foldedContains case-insensitive", M.foldedContains("SUSHI SATO", "sushi") === true);
assert("foldedContains no match", M.foldedContains("ramen", "sushi") === false);
assert("foldedContains empty query", M.foldedContains("anything", "") === false);
assert("foldedContains whitespace-only query", M.foldedContains("anything", "   ") === false);
assert("foldedContains null text", M.foldedContains(null, "sushi") === false);
assert("foldedContains undefined text", M.foldedContains(undefined, "sushi") === false);

// ----- matchClass tiers (reached via rankSpots) -----
// matchClass/NAME_EXACT/MATCH are module-private; the two-rung classification
// is reached through rankSpots, which folds the spot and returns it only when
// it matches (exact name match, or name/neighborhood substring — everything
// else is dropped). Class ordering (exact > match) is pinned in the rankSpots
// block below.
assert("matchClass exact via rankSpots",
  JSON.stringify(M.rankSpots([{ name: "sushi", neighborhood: "" }], "sushi").map((s) => s.name)) === '["sushi"]');
assert("matchClass name-prefix via rankSpots",
  JSON.stringify(M.rankSpots([{ name: "sushi bar", neighborhood: "" }], "sushi").map((s) => s.name)) === '["sushi bar"]');
assert("matchClass word-start via rankSpots",
  JSON.stringify(M.rankSpots([{ name: "soba sushi", neighborhood: "" }], "sushi").map((s) => s.name)) === '["soba sushi"]');
assert("matchClass mid-word substring via rankSpots",
  JSON.stringify(M.rankSpots([{ name: "asushiya", neighborhood: "" }], "sushi").map((s) => s.name)) === '["asushiya"]');
assert("matchClass neighborhood substring via rankSpots",
  JSON.stringify(M.rankSpots([{ name: "", neighborhood: "soho" }], "soho").map((s) => s.name)) === '[""]');
assert("matchClass city-label-only match returns empty via rankSpots",
  JSON.stringify(M.rankSpots([{ name: "", neighborhood: "", city: "tokyo" }], "tokyo")) === '[]');
assert("matchClass no match via rankSpots",
  JSON.stringify(M.rankSpots([{ name: "sushi", neighborhood: "" }], "ramen")) === '[]');

// ----- rankSpots -----
// Two rungs: NAME_EXACT > MATCH. Every MATCH entry keeps its input order (the
// caller's active sort — distance by default), so proximity decides among
// partial matches.

// exact > match, then input order among MATCH entries (neighborhood match at
// input index 0 before the name-substring match at index 2; "ramen" dropped).
const twoRungSpots = [
  { name: "tempura", neighborhood: "sushi town" },   // MATCH (neighborhood)
  { name: "sushi", neighborhood: "" },               // NAME_EXACT
  { name: "soba sushi", neighborhood: "" },          // MATCH (name substring)
  { name: "ramen", neighborhood: "" }                // no match
];
assert("rankSpots groups exact above match, input order within match",
  JSON.stringify(M.rankSpots(twoRungSpots, "sushi").map((s) => s.name)) ===
  '["sushi","tempura","soba sushi"]');

// Calibration: a name match 11,000 km away must NOT outrank a nearer spot that
// matches only in its neighborhood, when the input is pre-sorted distance-first.
const farNameSpots = [
  { name: "Omakase Room", neighborhood: "East Village" },   // near (11 km): neighborhood match
  { name: "Village Sushi", neighborhood: "" }               // far (11,000 km): name match
];
assert("rankSpots keeps a nearer neighborhood match above a far name match",
  JSON.stringify(M.rankSpots(farNameSpots, "village").map((s) => s.name)) ===
  '["Omakase Room","Village Sushi"]');

// Calibration: an exact name match floats to the top regardless of input order,
// even against a nearer partial match.
const exactFloatSpots = [
  { name: "Sushi Bar", neighborhood: "" },   // MATCH, near (first in input)
  { name: "Sushi", neighborhood: "" }        // NAME_EXACT (later in input)
];
assert("rankSpots floats an exact name match above a nearer partial match",
  JSON.stringify(M.rankSpots(exactFloatSpots, "sushi").map((s) => s.name)) ===
  '["Sushi","Sushi Bar"]');

// name-prefix and interior word-start are the SAME class (MATCH), so they keep
// the caller's order — a naive prefix > word-start score would move
// "new york sushi" ahead of "omakase new".
const mergedPrefixSpots = [
  { name: "omakase new", neighborhood: "" },   // word-start
  { name: "new york sushi", neighborhood: "" } // index-0 prefix
];
assert("rankSpots merges prefix and word-start into one class (input order)",
  JSON.stringify(M.rankSpots(mergedPrefixSpots, "new").map((s) => s.name)) ===
  '["omakase new","new york sushi"]');

// stability: equal-class spots keep their input order (a naive sort would swap)
const stableSpots = [
  { name: "sushi beta", neighborhood: "" },
  { name: "sushi alpha", neighborhood: "" }
];
assert("rankSpots stable within MATCH class",
  JSON.stringify(M.rankSpots(stableSpots, "sushi").map((s) => s.name)) ===
  '["sushi beta","sushi alpha"]');

const rankSpotsFixture = [
  { name: "Sushi Sato", neighborhood: "SoHo" },
  { name: "Ramen Row", neighborhood: "Midtown" },
  { name: "Tempura Tavern", neighborhood: "SoHo" }
];
assert("rankSpots empty query returns input unchanged",
  M.rankSpots(rankSpotsFixture, "") === rankSpotsFixture);
assert("rankSpots whitespace-only query returns input unchanged",
  M.rankSpots(rankSpotsFixture, "   ") === rankSpotsFixture);
assert("rankSpots no match returns empty array",
  JSON.stringify(M.rankSpots(rankSpotsFixture, "zzz")) === "[]");
assert("rankSpots blank/null name does not throw",
  JSON.stringify(M.rankSpots([{ name: null }, { name: "" }, { name: undefined }], "sushi")) === "[]");

// accent folding end-to-end
assert("rankSpots sake matches Saké",
  JSON.stringify(M.rankSpots([{ name: "Saké" }], "sake").map((s) => s.name)) === '["Saké"]');
assert("rankSpots poke matches Poké King",
  JSON.stringify(M.rankSpots([{ name: "Poké King" }], "poke").map((s) => s.name)) === '["Poké King"]');
assert("rankSpots cote matches Côté Sushi",
  JSON.stringify(M.rankSpots([{ name: "Côté Sushi" }], "cote").map((s) => s.name)) === '["Côté Sushi"]');
assert("rankSpots barfusser matches Barfüsser",
  JSON.stringify(M.rankSpots([{ name: "Barfüsser" }], "barfusser").map((s) => s.name)) === '["Barfüsser"]');

assert("rankSpots 1-char query returns matches",
  JSON.stringify(M.rankSpots([{ name: "Sushi" }, { name: "Ramen" }], "s").map((s) => s.name)) === '["Sushi"]');

// precomputed _folded is preferred over re-folding; still works without it
assert("rankSpots uses precomputed _folded",
  JSON.stringify(M.rankSpots([{ name: "Saké", _folded: { name: "sake", neighborhood: "" } }], "sake").map((s) => s.name)) === '["Saké"]');
const searchOverride = [{ name: "Saké", _folded: { name: "zzz", neighborhood: "" } }];
assert("rankSpots prefers precomputed _folded over raw name",
  JSON.stringify(M.rankSpots(searchOverride, "zzz").map((s) => s.name)) === '["Saké"]' &&
  JSON.stringify(M.rankSpots(searchOverride, "sake")) === "[]");

// Trade-off: city-label matching left the card list, so a query like "city"
// returns only spots whose name or neighborhood contains "city" — not spots
// that would have matched via their city's label alone (e.g. "New York City").
const cityTradeoffSpots = [
  { name: "Plain Spot", neighborhood: "", city: "New York City" },   // "city" only in the label -> excluded
  { name: "Sushi City", neighborhood: "", city: "Tokyo" },           // name match -> included
  { name: "Ramen Shop", neighborhood: "City Center", city: "Tokyo" } // neighborhood match -> included
];
assert("rankSpots 'city' matches name/neighborhood only (city-label match excluded)",
  JSON.stringify(M.rankSpots(cityTradeoffSpots, "city").map((s) => s.name)) ===
  '["Sushi City","Ramen Shop"]');

// rankSpots is a two-pass partition, not a sort. It must be byte-identical to
// the decorate-sort-undecorate reference (sort by class desc, then input index)
// for every input — including both classes and duplicate names/neighborhoods.
// The reference reimplements the classification with the public fold API only,
// so this asserts the partition against an independent implementation of the
// settled two-rung semantics.
assert("rankSpots partition agrees with reference sort (both classes + duplicates)",
  (function () {
    const fixture = [
      { name: "Sushi Bar", neighborhood: "SoHo" },      // MATCH (name)
      { name: "Sushi", neighborhood: "Chelsea" },       // NAME_EXACT
      { name: "Ramen", neighborhood: "Sushi Town" },    // MATCH (neighborhood)
      { name: "Sushi", neighborhood: "" },              // NAME_EXACT (dup name)
      { name: "Sushi Ramen", neighborhood: "" },        // MATCH (name)
      { name: "Other", neighborhood: "" },              // no match
      { name: "Sushi Bar", neighborhood: "Chelsea" },   // MATCH (name, dup)
      { name: "Sushi", neighborhood: "Sushi Town" }     // NAME_EXACT (dup)
    ];
    function referenceRank(spots, query) {
      const foldedQuery = S.foldSearchText(query);
      const records = spots.map(function (spot, index) {
        const folded = spot._folded || M.foldSpot(spot);
        const name = folded.name || "";
        const neighborhood = folded.neighborhood || "";
        let cls = 0;
        if (name === foldedQuery) cls = 2;
        else if (name.indexOf(foldedQuery) >= 0 || neighborhood.indexOf(foldedQuery) >= 0) cls = 1;
        return { spot, cls, index };
      }).filter(function (record) { return record.cls > 0; });
      records.sort(function (a, b) {
        if (a.cls !== b.cls) return b.cls - a.cls;
        return a.index - b.index;
      });
      return records.map(function (record) { return record.spot; });
    }
    const partition = JSON.stringify(M.rankSpots(fixture, "sushi"));
    const reference = JSON.stringify(referenceRank(fixture, "sushi"));
    return partition === reference &&
           JSON.stringify(M.rankSpots(fixture, "sushi").map((s) => s.name)) ===
             '["Sushi","Sushi","Sushi","Sushi Bar","Ramen","Sushi Ramen","Sushi Bar"]';
  })());

// ----- computeNeighborhoodNames -----
// Sorted unique neighborhood names from buildNeighborhoodRecords output — the
// one pure definition feeding the view-scoped neighborhood options (filter
// sheet + chip strip) off the same scoped index the search dropdown reads.
assert("computeNeighborhoodNames empty records",
  JSON.stringify(M.computeNeighborhoodNames([])) === '[]');
assert("computeNeighborhoodNames null records",
  JSON.stringify(M.computeNeighborhoodNames(null)) === '[]');
assert("computeNeighborhoodNames sorts records by key",
  JSON.stringify(M.computeNeighborhoodNames([
    { key: "Midtown" }, { key: "SoHo" }, { key: "Chelsea" }
  ])) === '["Chelsea","Midtown","SoHo"]');
assert("computeNeighborhoodNames matches buildNeighborhoodRecords dedup output",
  (function () {
    const records = M.buildNeighborhoodRecords(
      [{ neighborhood: "Midtown" }, { neighborhood: "SoHo" }, { neighborhood: "Midtown" }, { neighborhood: "Chelsea" }],
      "nyc", "New York City"
    );
    return JSON.stringify(M.computeNeighborhoodNames(records)) === '["Chelsea","Midtown","SoHo"]';
  })());
assert("computeNeighborhoodNames drops nothing (records already exclude empties)",
  JSON.stringify(M.computeNeighborhoodNames(M.buildNeighborhoodRecords(
    [{ neighborhood: "" }, { neighborhood: "  " }, { neighborhood: null }, { neighborhood: "SoHo" }],
    "nyc", "New York City"
  ))) === '["SoHo"]');

// ----- buildNeighborhoodRecords -----
// One pure definition of the neighborhood-record shape (first-seen order, per-
// neighborhood count, first-coords representative), shared by the catalog-wide
// recordCityIndex and the scoped Wishlist/Journal index.
assert("buildNeighborhoodRecords first-seen order + counts + representative",
  (function () {
    const records = M.buildNeighborhoodRecords(
      [
        { neighborhood: "SoHo", lat: 40.7, lon: -74.0 },
        { neighborhood: "Midtown", lat: 40.75, lon: -73.98 },
        { neighborhood: "SoHo", lat: 40.71, lon: -74.01 }
      ],
      "nyc", "New York City"
    );
    return records.length === 2 &&
           records[0].key === "SoHo" && records[0].name === "SoHo" &&
           records[0].foldedName === "soho" &&
           records[0].cityKey === "nyc" && records[0].cityName === "New York City" &&
           records[0].count === 2 && records[0].lat === 40.7 && records[0].lon === -74.0 &&
           records[1].key === "Midtown" && records[1].count === 1 &&
           records[1].lat === 40.75 && records[1].lon === -73.98;
  })());

assert("buildNeighborhoodRecords String() guard survives a numeric neighborhood",
  (function () {
    const records = M.buildNeighborhoodRecords([{ neighborhood: 12345 }], "nyc", "New York City");
    return records.length === 1 && records[0].key === "12345" && records[0].name === "12345";
  })());

assert("buildNeighborhoodRecords drops empty/blank neighborhoods",
  M.buildNeighborhoodRecords([{ neighborhood: "" }, { neighborhood: null }, { neighborhood: "  " }], "nyc", "New York City").length === 0);

assert("buildNeighborhoodRecords empty/null spots -> empty records",
  M.buildNeighborhoodRecords([], "nyc", "New York City").length === 0 &&
  M.buildNeighborhoodRecords(null, "nyc", "New York City").length === 0);

// ----- buildScopedSearchIndex -----
// Scoped geography for the Wishlist/Journal dropdowns: a subset's cities,
// neighborhoods, and states, plus subset-local counts and state distances.

// (a) Acceptance: one spot in an otherwise-absent city still yields that city,
// its neighborhood, and its US state as suggestions.
assert("buildScopedSearchIndex single spot yields its city + neighborhood + state",
  (function () {
    const b = M.buildScopedSearchIndex(
      [{ spot: { name: "Solo Sushi", neighborhood: "SoHo", region_code: "NY", country: "US", lat: 40.7, lon: -74.0 }, cityKey: "nyc" }],
      () => 5
    );
    return JSON.stringify(b.cities) === '["nyc"]' &&
           b.names.nyc === "New York City" &&
           b.foldedNames.nyc === "new york city" &&
           b.foldedKeys.nyc === "nyc" &&
           b.counts.nyc === 1 &&
           b.byCity.nyc.length === 1 &&
           b.byCity.nyc[0].key === "SoHo" && b.byCity.nyc[0].cityName === "New York City" &&
           b.states.length === 1 && b.states[0].key === "NY" && b.states[0].count === 1 &&
           b.states[0].foldedCode === "ny" && b.states[0].foldedName === "new york" &&
           b.stateDistances.NY === 5;
  })());

// (b) counts are subset-local: one saved spot in NYC must count 1, not the
// catalog-wide NYC total (~214).
assert("buildScopedSearchIndex counts are subset-local, not catalog-wide",
  (function () {
    const b = M.buildScopedSearchIndex(
      [{ spot: { name: "Solo", neighborhood: "SoHo", region_code: "NY", country: "US" }, cityKey: "nyc" }],
      () => 5
    );
    return b.counts.nyc === 1 && b.states[0].count === 1;
  })());

// (c) two spots in one neighborhood aggregate to one neighborhood record and
// one state record; the representative stays the first located spot.
assert("buildScopedSearchIndex two spots in one neighborhood aggregate once",
  (function () {
    const b = M.buildScopedSearchIndex(
      [
        { spot: { name: "A", neighborhood: "SoHo", region_code: "NY", country: "US", lat: 40.7, lon: -74.0 }, cityKey: "nyc" },
        { spot: { name: "B", neighborhood: "SoHo", region_code: "NY", country: "US", lat: 40.71, lon: -74.01 }, cityKey: "nyc" }
      ],
      () => 5
    );
    return b.counts.nyc === 2 &&
           b.byCity.nyc.length === 1 && b.byCity.nyc[0].count === 2 &&
           b.byCity.nyc[0].lat === 40.7 &&
           b.states.length === 1 && b.states[0].count === 2 &&
           b.stateDistances.NY === 5;
  })());

// (d) empty/null input returns an empty bundle (never null, never throws).
assert("buildScopedSearchIndex empty entries -> empty bundle",
  (function () {
    const b = M.buildScopedSearchIndex([], () => 5);
    return b.cities.length === 0 && b.states.length === 0 && b.countries.length === 0 &&
           Object.keys(b.byCity).length === 0 && Object.keys(b.stateDistances).length === 0;
  })());
assert("buildScopedSearchIndex null entries -> empty bundle",
  (function () {
    const b = M.buildScopedSearchIndex(null, () => 5);
    return b.cities.length === 0 && b.states.length === 0;
  })());
assert("buildScopedSearchIndex null-spot entries skipped -> empty bundle",
  (function () {
    const b = M.buildScopedSearchIndex([null, { spot: null, cityKey: "x" }], () => 5);
    return b.cities.length === 0 && b.states.length === 0;
  })());
assert("buildScopedSearchIndex missing distanceFor does not throw",
  (function () {
    const b = M.buildScopedSearchIndex([{ spot: { name: "A", region_code: "NY", country: "US" }, cityKey: "nyc" }], undefined);
    return b.states.length === 1 && b.stateDistances.NY === undefined;
  })());

// (e) name-keyed maps are null-prototype, so a city key like "constructor" can
// never resolve to Object.prototype.
assert("buildScopedSearchIndex name-keyed maps are null-prototype",
  (function () {
    const b = M.buildScopedSearchIndex([{ spot: { name: "A" }, cityKey: "constructor" }], () => 5);
    return Object.getPrototypeOf(b.names) === null &&
           Object.getPrototypeOf(b.counts) === null &&
           Object.getPrototypeOf(b.byCity) === null &&
           Object.getPrototypeOf(b.foldedNames) === null &&
           Object.getPrototypeOf(b.foldedKeys) === null &&
           Object.getPrototypeOf(b.stateDistances) === null &&
           b.names.constructor === "Constructor";
  })());

// (f) countries are aggregated from the subset only (the country dropdown's
// view-scoped source), nearest country first — same sortedCountList order as the
// catalog-wide `countries` property.
assert("buildScopedSearchIndex countries subset-local with nearest first",
  (function () {
    const b = M.buildScopedSearchIndex(
      [
        { spot: { name: "A", country: "US", lat: 1, lon: 1 }, cityKey: "nyc" },
        { spot: { name: "B", country: "CA", lat: 2, lon: 2 }, cityKey: "toronto" },
        { spot: { name: "C", country: "US", lat: 3, lon: 3 }, cityKey: "la" }
      ],
      (s) => ({ A: 1, B: 5, C: 2 }[s.name])
    );
    return JSON.stringify(b.countries) === '[{"key":"US","count":2},{"key":"CA","count":1}]';
  })());
assert("buildScopedSearchIndex countries empty when no country present",
  JSON.stringify(M.buildScopedSearchIndex([{ spot: { name: "A" }, cityKey: "nyc" }], () => 5).countries) === '[]');

// ----- searchHitMatchesTerm (prefix-only below 2 chars, substring at 2+) -----
assert("searchHitMatchesTerm prefix matches below 2 chars",
  M.searchHitMatchesTerm("sushi", "s", true) === true &&
  M.searchHitMatchesTerm("sushi", "s", false) === true);
assert("searchHitMatchesTerm prefix-only rejects an interior match below 2 chars",
  M.searchHitMatchesTerm("sushi", "u", true) === false &&
  M.searchHitMatchesTerm("sushi", "u", false) === true);
assert("searchHitMatchesTerm substring at 2+",
  M.searchHitMatchesTerm("sushi bar", "ush", false) === true);
assert("searchHitMatchesTerm no match",
  M.searchHitMatchesTerm("sushi", "ramen", false) === false);

// ----- buildCitySearchHits (city + neighborhood hit shape, injected distances) -----
function cityHitIndex() {
  const index = {
    cities: ["nyc"],
    names: Object.create(null),
    foldedNames: Object.create(null),
    foldedKeys: Object.create(null),
    counts: Object.create(null),
    byCity: Object.create(null)
  };
  index.names.nyc = "New York City";
  index.foldedNames.nyc = "new york city";
  index.foldedKeys.nyc = "nyc";
  index.counts.nyc = 214;
  index.byCity.nyc = [];
  return index;
}
assert("buildCitySearchHits city hit carries name/count/distance",
  (function () {
    const hits = M.buildCitySearchHits("nyc", cityHitIndex(), "new", false,
      () => 3, () => Infinity);
    return hits.length === 1 && hits[0].type === "city" && hits[0].key === "nyc" &&
           hits[0].name === "New York City" && hits[0].count === 214 && hits[0].distance === 3;
  })());
assert("buildCitySearchHits neighborhood hit carries parent city + distance",
  (function () {
    const index = cityHitIndex();
    index.byCity.nyc = [{ key: "SoHo", name: "SoHo", foldedName: "soho", cityKey: "nyc", cityName: "New York City", count: 5 }];
    const hits = M.buildCitySearchHits("nyc", index, "soho", false,
      () => Infinity, (nb) => 13.6);
    return hits.length === 1 && hits[0].type === "neighborhood" && hits[0].key === "SoHo" &&
           hits[0].cityName === "New York City" && hits[0].count === 5 && hits[0].distance === 13.6;
  })());
assert("buildCitySearchHits key match (folded city key) yields a city hit",
  (function () {
    const hits = M.buildCitySearchHits("nyc", cityHitIndex(), "nyc", false,
      () => 3, () => Infinity);
    return hits.length === 1 && hits[0].type === "city" && hits[0].key === "nyc";
  })());
assert("buildCitySearchHits prefix-only below 2 chars rejects an interior match",
  (function () {
    // "n" is a prefix of both "nyc" and "new york city" -> city hit; "e" sits at
    // index 1 in "new york city" -> rejected under prefix-only.
    const prefixHits = M.buildCitySearchHits("nyc", cityHitIndex(), "n", true, () => 3, () => Infinity);
    const interiorHits = M.buildCitySearchHits("nyc", cityHitIndex(), "e", true, () => 3, () => Infinity);
    return prefixHits.length === 1 && interiorHits.length === 0;
  })());

// ----- buildStateSearchHit (code OR full name, code key + full name label) -----
assert("buildStateSearchHit full-name match keeps code key + full name + distance",
  (function () {
    const hit = M.buildStateSearchHit({ key: "NY", count: 214, foldedCode: "ny", foldedName: "new york" }, "new", false, { NY: 5 });
    return hit && hit.type === "state" && hit.key === "NY" && hit.name === "New York" && hit.count === 214 && hit.distance === 5;
  })());
assert("buildStateSearchHit code query matches the raw code",
  M.buildStateSearchHit({ key: "NY", count: 214, foldedCode: "ny", foldedName: "new york" }, "ny", false, {}).key === "NY");
assert("buildStateSearchHit no match returns null",
  M.buildStateSearchHit({ key: "NY", count: 214, foldedCode: "ny", foldedName: "new york" }, "zzz", false, {}) === null);
assert("buildStateSearchHit geo-less state carries undefined distance",
  M.buildStateSearchHit({ key: "NH", count: 8, foldedCode: "nh", foldedName: "new hampshire" }, "new", false, {}).distance === undefined);

// ----- buildSearchHits (full dropdown pipeline, injected distance resolvers) -----
assert("buildSearchHits end-to-end: city + state ordered by proximity",
  (function () {
    const index = cityHitIndex();
    const states = [{ key: "NY", count: 214, foldedCode: "ny", foldedName: "new york" }];
    const hits = M.buildSearchHits("new", index, states, { NY: 5 },
      () => 3, () => Infinity);
    // "new" matches the city (new york city, 3 km) and the state (new york, 5 km);
    // the neighborhood "soho" does not match. City outranks state by proximity.
    return hits.length === 2 && hits[0].type === "city" && hits[1].type === "state" &&
           hits[0].key === "nyc" && hits[1].key === "NY";
  })());
assert("buildSearchHits empty query returns empty",
  M.buildSearchHits("", cityHitIndex(), [], {}, () => 0, () => 0).length === 0);
assert("buildSearchHits null index returns empty",
  M.buildSearchHits("x", null, [], {}, () => 0, () => 0).length === 0);

// ----- entryMatchesQuery (shared Journal/Wishlist query predicate) -----
// Matches name, neighborhood, and notes only; the city label is deliberately
// excluded (see entryMatchesQuery in catalog-utils.js) so all three list
// contexts search the same fields. The fields arrive as an array — the caller
// passes only the fields its view has (a Journal row [name, notes], a Wishlist
// row [name, neighborhood]).
assert("entryMatchesQuery name match", M.entryMatchesQuery(["Saké", null, null], "sake") === true);
assert("entryMatchesQuery neighborhood match", M.entryMatchesQuery(["Plain", "SoHo", null], "soho") === true);
assert("entryMatchesQuery notes match", M.entryMatchesQuery(["Plain", null, "great omakase"], "omakase") === true);
// A query that would have matched only the resolved city label ("new york"
// against "New York City") must NOT match — the label is not searched.
assert("entryMatchesQuery city label is not matched",
  M.entryMatchesQuery(["Plain Spot", null, null], "new york") === false);
assert("entryMatchesQuery no match", M.entryMatchesQuery(["Ramen", null, null], "sushi") === false);
assert("entryMatchesQuery null neighborhood/notes safe",
  M.entryMatchesQuery(["Ramen", null, null], "sushi") === false);
assert("entryMatchesQuery empty query returns false",
  M.entryMatchesQuery(["Sushi"], "") === false);
assert("entryMatchesQuery empty fields array returns false",
  M.entryMatchesQuery([], "sushi") === false);

// ----- buildRatingMaps (journal -> ratingsBySpot + journalByName) -----
assert("buildRatingMaps totals + counts + last-write-wins",
  (function () {
    const r = M.buildRatingMaps([
      { name: "Sushi Sato", rating: 4 },
      { name: "Sushi Sato", rating: 5 },
      { name: "Ramen Row", rating: 3 }
    ]);
    return r.ratingsBySpot["sushi sato"].total === 9 && r.ratingsBySpot["sushi sato"].count === 2 &&
           r.ratingsBySpot["ramen row"].total === 3 && r.ratingsBySpot["ramen row"].count === 1 &&
           r.journalByName["sushi sato"].rating === 5;
  })());
assert("buildRatingMaps skips unrated and zero-rating entries",
  (function () {
    const r = M.buildRatingMaps([{ name: "A", rating: 4 }, { name: "B" }, { name: "A", rating: 0 }]);
    return Object.keys(r.ratingsBySpot).length === 1 && r.ratingsBySpot.a.count === 1 && r.ratingsBySpot.a.total === 4;
  })());
assert("buildRatingMaps maps are null-prototype",
  (function () {
    const r = M.buildRatingMaps([{ name: "constructor", rating: 4 }]);
    return Object.getPrototypeOf(r.ratingsBySpot) === null && Object.getPrototypeOf(r.journalByName) === null &&
           r.ratingsBySpot.constructor.total === 4;
  })());
assert("buildRatingMaps null journal returns empty maps",
  (function () {
    const r = M.buildRatingMaps(null);
    return Object.keys(r.ratingsBySpot).length === 0 && Object.keys(r.journalByName).length === 0;
  })());

// ----- buildLocationBundle (shared bundle shape, no field drift) -----
assert("buildLocationBundle assembles the nine-field shape",
  (function () {
    const names = Object.create(null);
    names.nyc = "New York City";
    const b = M.buildLocationBundle({
      cities: ["nyc"], names: names, counts: { nyc: 1 }, byCity: {}, foldedNames: {}, foldedKeys: {},
      states: [], countries: [], stateDistances: {}
    });
    return JSON.stringify(Object.keys(b).sort()) === '["byCity","cities","countries","counts","foldedKeys","foldedNames","names","stateDistances","states"]' &&
           b.cities[0] === "nyc" && b.names.nyc === "New York City";
  })());

// ----- indexSpot (foldSpot stamp + name→entries index step) -----
assert("indexSpot stamps _folded and records the name entry",
  (function () {
    const map = Object.create(null);
    const spot = { name: "Omi Omakase", neighborhood: "SoHo" };
    M.indexSpot(spot, "nyc", map);
    return spot._folded.name === "omi omakase" && spot._folded.neighborhood === "soho" &&
           map["omi omakase"].length === 1 &&
           map["omi omakase"][0].spot === spot && map["omi omakase"][0].cityKey === "nyc";
  })());
assert("indexSpot appends same-name spots across cities",
  (function () {
    const map = Object.create(null);
    M.indexSpot({ name: "Same" }, "nyc", map);
    M.indexSpot({ name: "Same" }, "la", map);
    return map.same.length === 2 && map.same[0].cityKey === "nyc" && map.same[1].cityKey === "la";
  })());
assert("indexSpot null name does not throw",
  (function () {
    const map = Object.create(null);
    M.indexSpot({ name: null }, "nyc", map);
    return Object.keys(map).length === 0;
  })());


report();
