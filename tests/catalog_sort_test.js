// tests/catalog_sort_test.js — catalog-utils.js sort/spec/price tests
const M = require("../catalog-utils.js");
const { assert, report } = require("./_assert.js");

// The scalar comparators (compareSortValues / compareSortValuesWithTie /
// decoratedSort) are module-private; sortBySpec is the public sort entry that
// reaches them. sortPairViaSortBySpec reconstructs a two-way comparison by
// sorting a two-element list of { id, value, tie } records and returning the
// resulting id order — "first"/"second". A comparator return of 0 (a tie) keeps
// input order under the stable sort, so a tie is observable as "first" staying
// before "second" in BOTH directions. `firstTie`/`secondTie` carry the
// pre-extracted tie-break scalars (the comparator's firstTieValues/
// secondTieValues) when a tie-break is in play; the spec's tieBreakers index
// into them, so one helper serves both plain and tie comparisons.
function sortPairViaSortBySpec(first, second, sortKey, reversed, firstTie, secondTie) {
  var hasTie = firstTie !== undefined;
  var spec = {};
  spec[sortKey] = { extract: function (item) { return item.value; } };
  if (hasTie) {
    spec[sortKey].tieBreakers = firstTie.map(function (_, index) { return function (item) { return item.tie[index]; }; });
  }
  return M.sortBySpec(
    [{ id: "first", value: first, tie: firstTie }, { id: "second", value: second, tie: secondTie }],
    sortKey, reversed, spec
  ).map(function (item) { return item.id; });
}
// ----- compareSortValues (reached via sortBySpec) -----
assert("compareSortValues ascending numeric", JSON.stringify(sortPairViaSortBySpec(1, 2, "price", false)) === '["first","second"]');
assert("compareSortValues equal values tie (either direction)",
  JSON.stringify(sortPairViaSortBySpec(2, 2, "price", false)) === '["first","second"]' &&
  JSON.stringify(sortPairViaSortBySpec(2, 2, "price", true)) === '["first","second"]');
assert("compareSortValues reversed flips ascending", JSON.stringify(sortPairViaSortBySpec(1, 2, "price", true)) === '["second","first"]');
assert("compareSortValues rating descends", JSON.stringify(sortPairViaSortBySpec(4.5, 4.0, "rating", false)) === '["first","second"]');
assert("compareSortValues rating reversed ascends", JSON.stringify(sortPairViaSortBySpec(4.5, 4.0, "rating", true)) === '["second","first"]');
assert("compareSortValues rating opposes distance",
  JSON.stringify(sortPairViaSortBySpec(1, 2, "rating", false)) !== JSON.stringify(sortPairViaSortBySpec(1, 2, "distance", false)));

// ----- isSortDescending -----
assert("isSortDescending rating descends by default", M.isSortDescending("rating", false) === true);
assert("isSortDescending rating reversed ascends", M.isSortDescending("rating", true) === false);
assert("isSortDescending distance ascends by default", M.isSortDescending("distance", false) === false);
assert("isSortDescending distance reversed descends", M.isSortDescending("distance", true) === true);
assert("isSortDescending price ascends by default", M.isSortDescending("price", false) === false);
assert("isSortDescending price reversed descends", M.isSortDescending("price", true) === true);

// intrinsicDescends is module-private; the agreement between the sort direction
// (compareSortValues, reached via sortBySpec) and the arrow glyph direction
// (isSortDescending) is pinned through the public API for every key, so the two
// can never drift to opposite glyphs.
["distance", "rating", "price"].forEach((key) => {
  const ordered = M.sortBySpec(
    [{ id: "lo", value: 1 }, { id: "hi", value: 2 }],
    key, false,
    {
      distance: { extract: (s) => s.value },
      rating: { extract: (s) => s.value },
      price: { extract: (s) => s.value }
    }
  ).map((s) => s.id);
  const higherFirst = ordered[0] === "hi";
  assert("sort direction agrees with isSortDescending for " + key,
    higherFirst === M.isSortDescending(key, false));
});

// ----- SORT_KEYS -----
assert("SORT_KEYS order", JSON.stringify(M.SORT_KEYS) === '["distance","rating","price"]');

// ----- nextRadiusStep -----
assert("nextRadiusStep off -> 5", M.nextRadiusStep(0) === 5);
assert("nextRadiusStep 5 -> 10", M.nextRadiusStep(5) === 10);
assert("nextRadiusStep 10 -> 20", M.nextRadiusStep(10) === 20);
assert("nextRadiusStep 20 wraps to off", M.nextRadiusStep(20) === 0);
assert("nextRadiusStep unknown value wraps to off", M.nextRadiusStep(7) === 0);
assert("nextRadiusStep undefined wraps to off", M.nextRadiusStep(undefined) === 0);

// ----- compareSortValuesWithTie (reached via sortBySpec) -----
assert("compareSortValuesWithTie primary decides before tie-break",
  JSON.stringify(sortPairViaSortBySpec(4.5, 4.0, "rating", false, [1], [9999])) === '["first","second"]');
assert("compareSortValuesWithTie tie-break descends on equal primary",
  JSON.stringify(sortPairViaSortBySpec(4.5, 4.5, "rating", false, [10], [400])) === '["second","first"]');
assert("compareSortValuesWithTie reversed flips tie-break",
  JSON.stringify(sortPairViaSortBySpec(4.5, 4.5, "rating", true, [10], [400])) === '["first","second"]');
assert("compareSortValuesWithTie missing secondary treated as 0 (tie either direction)",
  JSON.stringify(sortPairViaSortBySpec(4.5, 4.5, "rating", false, [undefined], [0])) === '["first","second"]' &&
  JSON.stringify(sortPairViaSortBySpec(4.5, 4.5, "rating", true, [undefined], [0])) === '["first","second"]');

// ----- decoratedSort rating tie-break (secondary review count) -----
const ratingTieItems = [
  { name: "OneReview", rating: 4.5, reviews: 1 },
  { name: "ManyReviews", rating: 4.5, reviews: 400 },
  { name: "NoReviews", rating: 4.5 } // missing count -> 0
];
const ratingTieSpec = {
  rating: { extract: (s) => s.rating, tieBreakers: [(s) => s.reviews] },
  distance: { extract: () => 0 }
};
assert("decoratedSort equal ratings order by higher review count first",
  JSON.stringify(M.sortBySpec(ratingTieItems, "rating", false, ratingTieSpec).map((s) => s.name)) === '["ManyReviews","OneReview","NoReviews"]');
const distinctRatingItems = [
  { name: "LowMany", rating: 3.0, reviews: 9000 },
  { name: "HighFew", rating: 5.0, reviews: 2 }
];
assert("decoratedSort distinct ratings unaffected by review count",
  JSON.stringify(M.sortBySpec(distinctRatingItems, "rating", false, ratingTieSpec).map((s) => s.name)) === '["HighFew","LowMany"]');
assert("decoratedSort rating tie-break reversed flips both keys",
  JSON.stringify(M.sortBySpec(ratingTieItems, "rating", true, ratingTieSpec).map((s) => s.name)) === '["NoReviews","OneReview","ManyReviews"]');

// ----- price sort: unpriced always last, discount cheapest, rating tie-break -----
assert("compareSortValues price unpriced last ascending",
  JSON.stringify(sortPairViaSortBySpec(Infinity, 30, "price", false)) === '["second","first"]');
assert("compareSortValues price unpriced last descending",
  JSON.stringify(sortPairViaSortBySpec(Infinity, 30, "price", true)) === '["second","first"]');
assert("compareSortValues price priced before unpriced ascending",
  JSON.stringify(sortPairViaSortBySpec(30, Infinity, "price", false)) === '["first","second"]');
assert("compareSortValues price priced before unpriced descending",
  JSON.stringify(sortPairViaSortBySpec(30, Infinity, "price", true)) === '["first","second"]');
assert("compareSortValues price discount cheapest ascending",
  JSON.stringify(sortPairViaSortBySpec(-1, 30, "price", false)) === '["first","second"]');
assert("compareSortValues price discount last descending",
  JSON.stringify(sortPairViaSortBySpec(-1, 30, "price", true)) === '["second","first"]');
assert("compareSortValues price both unpriced tie (either direction)",
  JSON.stringify(sortPairViaSortBySpec(Infinity, Infinity, "price", false)) === '["first","second"]' &&
  JSON.stringify(sortPairViaSortBySpec(Infinity, Infinity, "price", true)) === '["first","second"]');
assert("compareSortValues price normal ascending",
  JSON.stringify(sortPairViaSortBySpec(10, 30, "price", false)) === '["first","second"]');
assert("compareSortValues price normal reversed",
  JSON.stringify(sortPairViaSortBySpec(10, 30, "price", true)) === '["second","first"]');

assert("compareSortValuesWithTie price rating tie descends on equal price",
  JSON.stringify(sortPairViaSortBySpec(30, 30, "price", false, [4.5, 0, ""], [4.0, 0, ""])) === '["first","second"]');
assert("compareSortValuesWithTie price rating tie not flipped by direction",
  JSON.stringify(sortPairViaSortBySpec(30, 30, "price", true, [4.5, 0, ""], [4.0, 0, ""])) === '["first","second"]');
assert("compareSortValuesWithTie price equal rating falls back to review count",
  JSON.stringify(sortPairViaSortBySpec(30, 30, "price", false, [4.5, 10, ""], [4.5, 400, ""])) === '["second","first"]');
assert("compareSortValuesWithTie price review count tie not flipped by direction",
  JSON.stringify(sortPairViaSortBySpec(30, 30, "price", true, [4.5, 10, ""], [4.5, 400, ""])) === '["second","first"]');
assert("compareSortValuesWithTie price equal rating + reviews falls back to name",
  JSON.stringify(sortPairViaSortBySpec(30, 30, "price", false, [4.5, 50, "alpha"], [4.5, 50, "beta"])) === '["first","second"]');
assert("compareSortValuesWithTie price name fallback compares pre-lowercased ascending",
  JSON.stringify(sortPairViaSortBySpec(30, 30, "price", false, [4.5, 50, "beta"], [4.5, 50, "alpha"])) === '["second","first"]');
assert("compareSortValuesWithTie price equal names tie (either direction)",
  JSON.stringify(sortPairViaSortBySpec(30, 30, "price", false, [4.5, 50, "alpha"], [4.5, 50, "alpha"])) === '["first","second"]' &&
  JSON.stringify(sortPairViaSortBySpec(30, 30, "price", true, [4.5, 50, "alpha"], [4.5, 50, "alpha"])) === '["first","second"]');
assert("compareSortValuesWithTie price missing name treated as empty",
  JSON.stringify(sortPairViaSortBySpec(30, 30, "price", false, [4.5, 50, ""], [4.5, 50, "alpha"])) === '["first","second"]');

// End-to-end: discount cheapest, unpriced last in both directions; equal
// prices order by rating (best first), then review count (most first), then
// name — all tie-break keys direction-independent.
const priceSpots = [
  { name: "Zeta", value: 30, rating: 4.5, reviews: 5 },
  { name: "Alpha", value: 30, rating: 4.0, reviews: 900 },
  { name: "Cheap", value: 10, rating: 3.0, reviews: 1 },
  { name: "Unpriced", value: Infinity, rating: 5.0, reviews: 9999 },
  { name: "Deal", value: -1, rating: 4.0, reviews: 50 }
];
const priceSpec = {
  price: { extract: (s) => s.value, tieBreakers: [(s) => s.rating, (s) => s.reviews, (s) => s.name] },
  distance: { extract: () => 0 }
};
assert("decoratedSort price asc discount first, unpriced last, rating tie",
  JSON.stringify(M.sortBySpec(priceSpots, "price", false, priceSpec).map((s) => s.name)) ===
  '["Deal","Cheap","Zeta","Alpha","Unpriced"]');
assert("decoratedSort price desc unpriced still last, discount last, rating tie",
  JSON.stringify(M.sortBySpec(priceSpots, "price", true, priceSpec).map((s) => s.name)) ===
  '["Zeta","Alpha","Cheap","Deal","Unpriced"]');

const priceRatingTieSpots = [
  { name: "LowRating", value: 30, rating: 4.0, reviews: 100 },
  { name: "HighRating", value: 30, rating: 4.8, reviews: 1 }
];
assert("decoratedSort price rating tie-break not flipped by reversed",
  JSON.stringify(M.sortBySpec(priceRatingTieSpots, "price", true, priceSpec).map((s) => s.name)) ===
  '["HighRating","LowRating"]');

const priceReviewTieSpots = [
  { name: "FewReviews", value: 30, rating: 4.5, reviews: 3 },
  { name: "ManyReviews", value: 30, rating: 4.5, reviews: 900 },
  { name: "NoReviews", value: 30, rating: 4.5 } // missing count -> 0
];
assert("decoratedSort price equal rating orders more reviews first",
  JSON.stringify(M.sortBySpec(priceReviewTieSpots, "price", false, priceSpec).map((s) => s.name)) ===
  '["ManyReviews","FewReviews","NoReviews"]');
assert("decoratedSort price review tie-break not flipped by reversed",
  JSON.stringify(M.sortBySpec(priceReviewTieSpots, "price", true, priceSpec).map((s) => s.name)) ===
  '["ManyReviews","FewReviews","NoReviews"]');

const priceRatingNameTieSpots = [
  { name: "Beta", value: 30, rating: 4.5, reviews: 10 },
  { name: "Alpha", value: 30, rating: 4.5, reviews: 10 }
];
assert("decoratedSort price equal rating + reviews falls back to name",
  JSON.stringify(M.sortBySpec(priceRatingNameTieSpots, "price", false, priceSpec).map((s) => s.name)) ===
  '["Alpha","Beta"]');

// The name fallback compares pre-lowercased strings with a plain `<`/`>`; the
// caller lowercases at decorate time. Mixed-case names still sort case-
// insensitively when the extractor lowercases.
const priceMixedCaseNameSpots = [
  { name: "beta", value: 30, rating: 4.5, reviews: 10 },
  { name: "Alpha", value: 30, rating: 4.5, reviews: 10 }
];
const priceMixedCaseSpec = {
  price: { extract: (s) => s.value, tieBreakers: [(s) => s.rating, (s) => s.reviews, (s) => s.name.toLowerCase()] },
  distance: { extract: () => 0 }
};
assert("decoratedSort price name tie-break case-insensitive via pre-lowercased extractor",
  JSON.stringify(M.sortBySpec(priceMixedCaseNameSpots, "price", false, priceMixedCaseSpec).map((s) => s.name)) ===
  '["Alpha","beta"]');

// ----- sortBySpec (single spec-lookup dispatch) -----
const sortBySpecItems = [
  { name: "Beta", rating: 4.0, reviews: 900, price: 30, km: 15 },
  { name: "Alpha", rating: 4.5, reviews: 2, price: 30, km: 5 },
  { name: "Gamma", rating: 3.5, reviews: 50, price: 10, km: 10 }
];
const sortSpecs = {
  rating: { extract: (s) => s.rating, tieBreakers: [(s) => s.reviews] },
  price: { extract: (s) => s.price, tieBreakers: [(s) => s.rating, (s) => s.reviews, (s) => s.name] },
  distance: { extract: (s) => s.km }
};
assert("sortBySpec rating desc",
  JSON.stringify(M.sortBySpec(sortBySpecItems, "rating", false, sortSpecs).map((s) => s.name)) === '["Alpha","Beta","Gamma"]');
assert("sortBySpec price asc with rating tie-break",
  JSON.stringify(M.sortBySpec(sortBySpecItems, "price", false, sortSpecs).map((s) => s.name)) === '["Gamma","Alpha","Beta"]');
assert("sortBySpec distance asc",
  JSON.stringify(M.sortBySpec(sortBySpecItems, "distance", false, sortSpecs).map((s) => s.name)) === '["Alpha","Gamma","Beta"]');
assert("sortBySpec distance reversed flips",
  JSON.stringify(M.sortBySpec(sortBySpecItems, "distance", true, sortSpecs).map((s) => s.name)) === '["Beta","Gamma","Alpha"]');
assert("sortBySpec unknown key falls back to distance",
  JSON.stringify(M.sortBySpec(sortBySpecItems, "bogus", false, sortSpecs).map((s) => s.name)) === '["Alpha","Gamma","Beta"]');
assert("sortBySpec missing distance spec returns items unchanged",
  JSON.stringify(M.sortBySpec(sortBySpecItems, "bogus", false, {}).map((s) => s.name)) === '["Beta","Alpha","Gamma"]');
const sortBySpecTieItems = [
  { name: "OneReview", rating: 4.5, reviews: 1 },
  { name: "ManyReviews", rating: 4.5, reviews: 400 }
];
assert("sortBySpec equal ratings order by review count",
  JSON.stringify(M.sortBySpec(sortBySpecTieItems, "rating", false, {
    rating: { extract: (s) => s.rating, tieBreakers: [(s) => s.reviews] },
    distance: { extract: (s) => 0 }
  }).map((s) => s.name)) === '["ManyReviews","OneReview"]');
assert("sortBySpec journal-style spec without tie-breakers sorts fine",
  JSON.stringify(M.sortBySpec(sortBySpecItems, "distance", false, {
    distance: { extract: (s) => s.km }
  }).map((s) => s.name)) === '["Alpha","Gamma","Beta"]');

// ----- sortedCountList -----
// Flatten each { key, count } entry to "key:count" so the assertion pins the
// array order (the real contract) without pinning the object's incidental field
// order.
function sortedCountPairs(counts, nearestValue) {
  return M.sortedCountList(counts, nearestValue).map(function (entry) {
    return entry.key + ":" + entry.count;
  });
}
assert("sortedCountList sorts alphabetically",
  JSON.stringify(sortedCountPairs({ TX: 2, CA: 3, NY: 1 }, "")) === '["CA:3","NY:1","TX:2"]');
assert("sortedCountList moves nearest first",
  JSON.stringify(sortedCountPairs({ CA: 3, NY: 1, TX: 2 }, "TX")) === '["TX:2","CA:3","NY:1"]');
assert("sortedCountList absent nearest stays alphabetical",
  JSON.stringify(sortedCountPairs({ CA: 3, NY: 1 }, "TX")) === '["CA:3","NY:1"]');
assert("sortedCountList empty map", JSON.stringify(M.sortedCountList({}, "")) === "[]");

// ----- buildStateOptions -----
// sortedCountList + folded code/name stamping. `aggregates` is the
// computeLocationAggregates output shape ({ stateCounts, nearestState }); the
// folded name resolves through stateNameFor so a "new"-style query reaches the
// New* states.
assert("buildStateOptions stamps folded code and name, nearest first",
  (function () {
    const opts = M.buildStateOptions({ stateCounts: { NY: 2, CA: 1 }, nearestState: "NY" });
    return opts.length === 2 &&
           opts[0].key === "NY" && opts[0].count === 2 &&
           opts[0].foldedCode === "ny" && opts[0].foldedName === "new york" &&
           opts[1].key === "CA" && opts[1].count === 1 &&
           opts[1].foldedCode === "ca" && opts[1].foldedName === "california";
  })());
assert("buildStateOptions absent nearest stays alphabetical",
  (function () {
    const opts = M.buildStateOptions({ stateCounts: { NY: 1, CA: 2 } });
    return opts[0].key === "CA" && opts[1].key === "NY";
  })());
assert("buildStateOptions empty aggregates", JSON.stringify(M.buildStateOptions({ stateCounts: {}, nearestState: "" })) === "[]");

// ----- computeSortedCities -----
const cityDistances = Object.create(null);
cityDistances.nyc = 12;
cityDistances.chi = 8;
cityDistances.la = 30;
cityDistances.geoless = Infinity;
assert("computeSortedCities orders by distance",
  JSON.stringify(M.computeSortedCities(["la", "nyc", "chi"], (k) => cityDistances[k])) ===
  '[{"key":"chi","distance":8},{"key":"nyc","distance":12},{"key":"la","distance":30}]');
assert("computeSortedCities geo-less last",
  JSON.stringify(M.computeSortedCities(["geoless", "la", "chi"], (k) => cityDistances[k])) ===
  '[{"key":"chi","distance":8},{"key":"la","distance":30},{"key":"geoless","distance":null}]');
assert("computeSortedCities all geo-less keeps input order",
  JSON.stringify(M.computeSortedCities(["geoless", "chi", "la"], (k) => Infinity)) ===
  '[{"key":"geoless","distance":null},{"key":"chi","distance":null},{"key":"la","distance":null}]');
const tieDistances = { a: 5, b: 5, c: 5 };
assert("computeSortedCities ties stable",
  JSON.stringify(M.computeSortedCities(["b", "a", "c"], (k) => tieDistances[k])) ===
  '[{"key":"b","distance":5},{"key":"a","distance":5},{"key":"c","distance":5}]');
assert("computeSortedCities empty list", JSON.stringify(M.computeSortedCities([], (k) => 0)) === "[]");
assert("computeSortedCities null list", JSON.stringify(M.computeSortedCities(null, (k) => 0)) === "[]");

// ----- sortSearchHits -----
// The sort reads each hit's own `distance` (km, may be Infinity/undefined when
// geo-less): cities/neighborhoods carry their representative spot's distance,
// states carry their nearest spot's distance. Order is uniform — finite
// distance ascending, geo-less last, type as the tie-break, then name/key —
// with a count-descending fallback for geo-less states.
//
// Table-driven: each case supplies its hits, a per-hit projection (what the
// assertion compares, e.g. "type:name" or "key"), and the expected projected
// order — a new case is one row.
const sortSearchHitsCases = [
  {
    label: "sortSearchHits nearby neighborhood outranks far city (reported case)",
    project: (h) => h.type + ":" + h.name,
    hits: [
      { type: "city", key: "mexico-city", name: "Mexico City", count: 5, distance: 3374 },
      { type: "neighborhood", key: "Long Island City", name: "Long Island City", cityKey: "nyc", cityName: "New York City", count: 1, distance: 13.6 }
    ],
    expected: ["neighborhood:Long Island City", "city:Mexico City"]
  },
  {
    label: "sortSearchHits nearest located hit first overall",
    project: (h) => h.name,
    hits: [
      { type: "city", key: "mexico-city", name: "Mexico City", count: 5, distance: 3374 },
      { type: "city", key: "nyc", name: "New York City", count: 214, distance: 17.9 },
      { type: "neighborhood", key: "Long Island City", name: "Long Island City", cityKey: "nyc", cityName: "New York City", count: 1, distance: 13.6 }
    ],
    expected: ["Long Island City", "New York City", "Mexico City"]
  },
  {
    label: "sortSearchHits nearby city outranks farther city",
    project: (h) => h.key,
    hits: [
      { type: "city", key: "auckland", name: "Auckland", count: 88, distance: 14000 },
      { type: "city", key: "nyc", name: "New York City", count: 214, distance: 3 }
    ],
    expected: ["nyc", "auckland"]
  },
  {
    label: "sortSearchHits geo-less city sorts after located city",
    project: (h) => h.key,
    hits: [
      { type: "city", key: "geoless", name: "Geoless", count: 1, distance: Infinity },
      { type: "city", key: "nyc", name: "New York City", count: 214, distance: 3 }
    ],
    expected: ["nyc", "geoless"]
  },
  {
    label: "sortSearchHits type tie-break on equal distance: city before neighborhood before state",
    project: (h) => h.type,
    hits: [
      { type: "state", key: "NY", name: "New York", count: 214, distance: 5 },
      { type: "neighborhood", key: "Soho", name: "Soho", cityKey: "nyc", cityName: "New York City", count: 5, distance: 5 },
      { type: "city", key: "nyc", name: "New York City", count: 214, distance: 5 }
    ],
    expected: ["city", "neighborhood", "state"]
  },
  {
    label: "sortSearchHits type tie-break when both geo-less: city before neighborhood",
    project: (h) => h.type,
    hits: [
      { type: "neighborhood", key: "Soho", name: "Soho", cityKey: "nyc", cityName: "New York City", count: 5, distance: Infinity },
      { type: "city", key: "nyc", name: "New York City", count: 214, distance: Infinity }
    ],
    expected: ["city", "neighborhood"]
  },
  {
    label: "sortSearchHits two same-city neighborhoods order by own distance (LIC before Jersey City)",
    project: (h) => h.key,
    hits: [
      { type: "neighborhood", key: "Jersey City", name: "Jersey City", cityKey: "nyc", cityName: "New York City", count: 1, distance: 21.2 },
      { type: "neighborhood", key: "Long Island City", name: "Long Island City", cityKey: "nyc", cityName: "New York City", count: 1, distance: 13.6 }
    ],
    expected: ["Long Island City", "Jersey City"]
  },
  {
    label: "sortSearchHits true distance tie falls back to name",
    project: (h) => h.key,
    hits: [
      { type: "neighborhood", key: "Zebra", name: "Zebra", cityKey: "nyc", cityName: "New York City", count: 1, distance: 10 },
      { type: "neighborhood", key: "Alpha", name: "Alpha", cityKey: "nyc", cityName: "New York City", count: 1, distance: 10 }
    ],
    expected: ["Alpha", "Zebra"]
  },
  {
    label: "sortSearchHits geo-less states fall back to count descending",
    project: (h) => h.key,
    hits: [
      { type: "state", key: "NJ", name: "New Jersey", count: 10 },
      { type: "state", key: "NY", name: "New York", count: 214 },
      { type: "state", key: "NM", name: "New Mexico", count: 5 }
    ],
    expected: ["NY", "NJ", "NM"]
  },
  {
    label: "sortSearchHits equal geo-less state counts tie-break by name",
    project: (h) => h.key,
    hits: [
      { type: "state", key: "TX", name: "Texas", count: 10 },
      { type: "state", key: "CA", name: "California", count: 10 }
    ],
    expected: ["CA", "TX"]
  },
  {
    label: "sortSearchHits located hits precede states, even a geo-less one",
    project: (h) => h.type,
    hits: [
      { type: "state", key: "NY", name: "New York", count: 214 },
      { type: "neighborhood", key: "Soho", name: "Soho", cityKey: "nyc", cityName: "New York City", count: 5, distance: Infinity },
      { type: "city", key: "nyc", name: "New York City", count: 214, distance: 17.9 }
    ],
    expected: ["city", "neighborhood", "state"]
  },
  {
    label: "sortSearchHits geo-less state sorts after a geo-less neighborhood",
    project: (h) => h.type,
    hits: [
      { type: "state", key: "NY", name: "New York", count: 214 },
      { type: "neighborhood", key: "Soho", name: "Soho", cityKey: "nyc", cityName: "New York City", count: 5, distance: Infinity }
    ],
    expected: ["neighborhood", "state"]
  },
  {
    // The reported case: a near state outranks a far neighborhood, and also
    // outranks a farther city — proximity now orders states uniformly with the
    // located hits instead of pushing them to the end.
    label: "sortSearchHits near state outranks far neighborhood and farther city",
    project: (h) => h.type + ":" + h.name,
    hits: [
      { type: "city", key: "mexico-city", name: "Mexico City", count: 5, distance: 3374 },
      { type: "neighborhood", key: "Newmarket", name: "Newmarket", cityKey: "auckland", cityName: "Auckland", count: 4, distance: 14211 },
      { type: "state", key: "NY", name: "New York", count: 169, distance: 5 }
    ],
    expected: ["state:New York", "city:Mexico City", "neighborhood:Newmarket"]
  },
  {
    // A state whose spots all lack coordinates carries no usable distance and
    // still sorts last, keeping count-descending then name among its geo-less
    // peers.
    label: "sortSearchHits geo-less state sorts last with count-descending fallback",
    project: (h) => h.type + ":" + h.name,
    hits: [
      { type: "state", key: "NH", name: "New Hampshire", count: 8 },
      { type: "city", key: "nyc", name: "New York City", count: 214, distance: 3 },
      { type: "state", key: "NY", name: "New York", count: 214 },
      { type: "state", key: "NM", name: "New Mexico", count: 5 }
    ],
    expected: ["city:New York City", "state:New York", "state:New Hampshire", "state:New Mexico"]
  },
  {
    label: "sortSearchHits equal distance + name falls back to key",
    project: (h) => h.key,
    hits: [
      { type: "city", key: "springfield-mo", name: "Springfield", count: 1, distance: 10 },
      { type: "city", key: "springfield-il", name: "Springfield", count: 1, distance: 10 }
    ],
    expected: ["springfield-il", "springfield-mo"]
  },
  {
    // The user's "new" case, end to end: the near city, then the New* states by
    // their own proximity (nearest spot in the state), then the far Auckland
    // neighborhoods. The states no longer sort last by count — New Jersey (23,
    // ~10 km) outranks New Hampshire (66, ~350 km) because distance now
    // dominates.
    label: "sortSearchHits 'new' case: states by proximity, before far neighborhoods",
    project: (h) => h.type + ":" + h.name,
    hits: [
      { type: "neighborhood", key: "Newmarket", name: "Newmarket", cityKey: "auckland", cityName: "Auckland", count: 4, distance: 14211 },
      { type: "state", key: "NJ", name: "New Jersey", count: 23, distance: 10 },
      { type: "city", key: "nyc", name: "New York City", count: 214, distance: 3 },
      { type: "neighborhood", key: "Newton", name: "Newton", cityKey: "auckland", cityName: "Auckland", count: 2, distance: 14211 },
      { type: "state", key: "NH", name: "New Hampshire", count: 66, distance: 350 },
      { type: "state", key: "NY", name: "New York", count: 169, distance: 5 }
    ],
    expected: ["city:New York City", "state:New York", "state:New Jersey", "state:New Hampshire", "neighborhood:Newmarket", "neighborhood:Newton"]
  }
];

sortSearchHitsCases.forEach((c) => {
  assert(c.label, JSON.stringify(M.sortSearchHits(c.hits).map(c.project)) === JSON.stringify(c.expected));
});

// The remaining sortSearchHits cases don't reduce to a projected-order
// comparison (mutation, empty/null input), so they stay standalone.
assert("sortSearchHits does not mutate its input",
  (function () {
    const hits = [
      { type: "city", key: "nyc", name: "New York City", count: 214, distance: 3 },
      { type: "state", key: "NY", name: "New York", count: 214 }
    ];
    const before = JSON.stringify(hits);
    M.sortSearchHits(hits);
    return JSON.stringify(hits) === before;
  })());

assert("sortSearchHits empty list", JSON.stringify(M.sortSearchHits([])) === "[]");
assert("sortSearchHits null list", JSON.stringify(M.sortSearchHits(null)) === "[]");

// ----- computeLocationAggregates -----
const noDistance = () => undefined;

assert("computeLocationAggregates empty list",
  (function () {
    const agg = M.computeLocationAggregates([], noDistance);
    return Object.keys(agg.stateCounts).length === 0 &&
           Object.keys(agg.countryCounts).length === 0 &&
           agg.nearestState === "" &&
           agg.nearestCountry === "" &&
           Object.keys(agg.stateDistances).length === 0;
  })());

assert("computeLocationAggregates single location",
  (function () {
    const agg = M.computeLocationAggregates([{ name: "Solo", region_code: "NY", country: "US" }], () => 5);
    return agg.stateCounts.NY === 1 &&
           agg.countryCounts.US === 1 &&
           agg.nearestState === "NY" &&
           agg.nearestCountry === "US" &&
           agg.stateDistances.NY === 5;
  })());

assert("computeLocationAggregates multiple locations counts + nearest",
  (function () {
    const spots = [
      { name: "Far", region_code: "CA", country: "US" },
      { name: "Near", region_code: "NY", country: "US" },
      { name: "Mid", region_code: "TX", country: "US" },
      { name: "OtherNY", region_code: "NY", country: "US" }
    ];
    const distances = { Far: 3000, Near: 5, Mid: 2000, OtherNY: 800 };
    const agg = M.computeLocationAggregates(spots, (s) => distances[s.name]);
    return agg.stateCounts.CA === 1 && agg.stateCounts.NY === 2 && agg.stateCounts.TX === 1 &&
           agg.countryCounts.US === 4 &&
           agg.nearestState === "NY" && agg.nearestCountry === "US" &&
           agg.stateDistances.CA === 3000 && agg.stateDistances.NY === 5 && agg.stateDistances.TX === 2000;
  })());

assert("computeLocationAggregates stateDistances keeps nearest spot per state",
  (function () {
    const spots = [
      { name: "NearNY", region_code: "NY", country: "US" },
      { name: "FarNY", region_code: "NY", country: "US" },
      { name: "NJSpot", region_code: "NJ", country: "US" }
    ];
    const agg = M.computeLocationAggregates(spots, (s) =>
      s.name === "NearNY" ? 5 : s.name === "FarNY" ? 800 : 10);
    return agg.stateDistances.NY === 5 && agg.stateDistances.NJ === 10;
  })());

assert("computeLocationAggregates undefined distance never wins nearest",
  (function () {
    const agg = M.computeLocationAggregates(
      [{ name: "Geoless", region_code: "NY", country: "US" }], noDistance);
    return agg.stateCounts.NY === 1 && agg.countryCounts.US === 1 &&
           agg.nearestState === "" && agg.nearestCountry === "" &&
           agg.stateDistances.NY === undefined;
  })());

assert("computeLocationAggregates non-US region code not counted as state",
  (function () {
    const agg = M.computeLocationAggregates(
      [{ name: "Melb", region_code: "VIC", country: "AU" }], () => 1);
    return JSON.stringify(agg.stateCounts) === "{}" && agg.countryCounts.AU === 1 &&
           agg.nearestState === "" && agg.nearestCountry === "AU" &&
           JSON.stringify(agg.stateDistances) === "{}";
  })());

// The collision class: a foreign region code that happens to be a US state code
// must not be attributed to the American state. Amsterdam's "NH" is
// Noord-Holland (country NL), not New Hampshire.
assert("computeLocationAggregates foreign region colliding with US code not counted",
  (function () {
    const agg = M.computeLocationAggregates(
      [{ name: "Ken-Ichi", region_code: "NH", country: "NL" }], () => 5857);
    return JSON.stringify(agg.stateCounts) === "{}" &&
           agg.countryCounts.NL === 1 &&
           agg.nearestState === "" &&
           JSON.stringify(agg.stateDistances) === "{}";
  })());

// The same code, but a genuine US spot (country US), is still the real state.
assert("computeLocationAggregates genuine US state with colliding code still counted",
  (function () {
    const agg = M.computeLocationAggregates(
      [{ name: "Concord", region_code: "NH", country: "US" }], () => 5);
    return agg.stateCounts.NH === 1 && agg.countryCounts.US === 1 &&
           agg.nearestState === "NH" && agg.stateDistances.NH === 5;
  })());

// A genuine US state whose spots all lack coordinates still counts, but carries
// no distance and never wins "nearest" (the geo-less fallback).
assert("computeLocationAggregates geo-less US state counts but carries no distance",
  (function () {
    const agg = M.computeLocationAggregates(
      [{ name: "Geoless NH", region_code: "NH", country: "US" }], noDistance);
    return agg.stateCounts.NH === 1 && agg.countryCounts.US === 1 &&
           agg.nearestState === "" && agg.stateDistances.NH === undefined;
  })());

assert("computeLocationAggregates trims and uppercases state/country",
  (function () {
    const agg = M.computeLocationAggregates(
      [{ name: "A", region_code: "  ny ", country: " us " }], noDistance);
    return agg.stateCounts.NY === 1 && agg.countryCounts.US === 1 &&
           JSON.stringify(agg.stateDistances) === "{}";
  })());

assert("computeLocationAggregates null spots treated as empty",
  (function () {
    const agg = M.computeLocationAggregates(null, noDistance);
    return Object.keys(agg.stateCounts).length === 0 &&
           Object.keys(agg.countryCounts).length === 0 &&
           agg.nearestState === "" &&
           agg.nearestCountry === "" &&
           Object.keys(agg.stateDistances).length === 0;
  })());

// ----- makeSortSpecs (moved from BarWidget.qml, injected rating/distance) -----
// The factory takes spotOf/nameOf plus injected ratingFor/distanceFor so the
// tie-break ladder (rating → review count → name, all direction-independent
// under Price ↑/↓) is unit-tested. sortBySpec drives the produced specs.
const spotSpecs = M.makeSortSpecs(
  (s) => s,                       // spotOf: items are spots
  (s) => s.name,                  // nameOf
  (spot, name) => spot.rating,    // ratingFor: user rating else Yelp rating
  (spot) => spot.km               // distanceFor
);

assert("makeSortSpecs rating tie-break by review count",
  JSON.stringify(M.sortBySpec([
    { name: "OneReview", rating: 4.5, _yelpReviewCount: 1, km: 0 },
    { name: "ManyReviews", rating: 4.5, _yelpReviewCount: 400, km: 0 },
    { name: "NoReviews", rating: 4.5, km: 0 }
  ], "rating", false, spotSpecs).map((s) => s.name)) === '["ManyReviews","OneReview","NoReviews"]');

const makeSortSpecsPriceSpots = [
  { name: "Zeta", price: "30", rating: 4.5, _yelpReviewCount: 5, km: 0 },
  { name: "Alpha", price: "30", rating: 4.0, _yelpReviewCount: 900, km: 0 },
  { name: "Cheap", price: "10", rating: 3.0, _yelpReviewCount: 1, km: 0 },
  { name: "Unpriced", rating: 5.0, _yelpReviewCount: 9999, km: 0 },
  { name: "Deal", discount: "50%", rating: 4.0, _yelpReviewCount: 50, km: 0 }
];
assert("makeSortSpecs price asc discount first, unpriced last, rating tie",
  JSON.stringify(M.sortBySpec(makeSortSpecsPriceSpots, "price", false, spotSpecs).map((s) => s.name)) ===
  '["Deal","Cheap","Zeta","Alpha","Unpriced"]');
assert("makeSortSpecs price desc unpriced still last, tie-break not flipped",
  JSON.stringify(M.sortBySpec(makeSortSpecsPriceSpots, "price", true, spotSpecs).map((s) => s.name)) ===
  '["Zeta","Alpha","Cheap","Deal","Unpriced"]');

assert("makeSortSpecs distance asc",
  JSON.stringify(M.sortBySpec([
    { name: "Far", rating: 0, km: 15 },
    { name: "Near", rating: 0, km: 5 },
    { name: "Mid", rating: 0, km: 10 }
  ], "distance", false, spotSpecs).map((s) => s.name)) === '["Near","Mid","Far"]');

// Wishlist-style instantiations: spotOf resolves item.spot (null for a saved name
// with no catalog match), nameOf substitutes item.name, and the rating/distance
// resolvers null-guard so a null spot sorts 0 (rating) / Infinity (distance).
const wishlistSpecs = M.makeSortSpecs(
  (item) => item.spot,
  (item) => item.spot ? item.spot.name : item.name,
  (spot, name) => (spot ? spot.rating : 0),
  (spot) => (spot ? spot.km : Infinity)
);
assert("makeSortSpecs null spot (no catalog match) sorts last for rating",
  JSON.stringify(M.sortBySpec([
    { name: "Missing", spot: null },
    { name: "Rated", spot: { name: "Rated", rating: 4.5, _yelpReviewCount: 10, km: 3 } }
  ], "rating", false, wishlistSpecs).map((i) => i.name)) === '["Rated","Missing"]');

// ----- resolveFilterSort (shared Journal/Wishlist filter+sort pipeline) -----
// resolve-once → passesFilters → entryMatchesQuery → sortBySpec → mapItem. The
// injected locate/passesFilters/matchFields/sortSpecs/mapItem mirror the two
// BarWidget call sites (computeSortedJournal / computeSortedWishlist).

assert("resolveFilterSort locates each item exactly once",
  (function () {
    var calls = 0;
    var result = M.resolveFilterSort(
      ["a", "b", "c"],
      function (item) { calls++; return { name: item }; },
      "",
      {
        passesFilters: function () { return true; },
        matchFields: function () { return []; },
        sortSpecs: { distance: { extract: function () { return 0; } } },
        sortBy: "distance",
        sortReversed: false
      }
    );
    return calls === 3 && result.length === 3;
  })());

assert("resolveFilterSort hoists the neighborhood fold (once per pass)",
  (function () {
    var folds = 0;
    M.resolveFilterSort(
      ["a", "b", "c"],
      function (item) { return { name: item }; },
      "",
      {
        foldNeighborhood: function () { folds++; return "soho"; },
        passesFilters: function (record, folded) { return folded === "soho"; },
        matchFields: function () { return []; },
        sortSpecs: { distance: { extract: function () { return 0; } } },
        sortBy: "distance",
        sortReversed: false
      }
    );
    return folds === 1;
  })());

assert("resolveFilterSort journal: query + rating sort + reshape",
  (function () {
    var located = {
      "Saké": { name: "Saké" },
      "Ramen Row": { name: "Ramen Row" },
      "Tempura": { name: "Tempura" }
    };
    var entries = [
      { name: "Saké", city: "nyc", rating: 4, notes: "" },
      { name: "Ramen Row", city: "nyc", rating: 5, notes: "great omakase" },
      { name: "Tempura", city: "nyc", rating: 3, notes: "" }
    ];
    var result = M.resolveFilterSort(
      entries,
      function (entry) { return { entry: entry, located: { spot: located[entry.name] } }; },
      "omakase",
      {
        passesFilters: function (record) { return !!record.located; },
        matchFields: function (record) { return [record.entry.name, record.entry.notes]; },
        sortSpecs: {
          rating: { extract: function (record) { return record.entry.rating || 0; } },
          distance: { extract: function () { return 0; } }
        },
        sortBy: "rating",
        sortReversed: false,
        mapItem: function (record) {
          return { name: record.entry.name, cityKey: record.entry.city, spot: record.located.spot, entry: record.entry };
        }
      }
    );
    // "omakase" matches only "Ramen Row" (its notes); the reshape keys off the
    // resolved located spot and the entry's own fields.
    return result.length === 1 &&
           result[0].name === "Ramen Row" &&
           result[0].cityKey === "nyc" &&
           result[0].spot === located["Ramen Row"] &&
           result[0].entry.rating === 5;
  })());

assert("resolveFilterSort wishlist: kind filter + neighborhood query + distance sort",
  (function () {
    var saved = ["Saké", "Ramen Row", "Sushi Bar"];
    var spots = {
      "Saké": { name: "Saké", neighborhood: "SoHo", _spotKind: "omakase" },
      "Ramen Row": { name: "Ramen Row", neighborhood: "Midtown", _spotKind: "omakase" },
      "Sushi Bar": { name: "Sushi Bar", neighborhood: "SoHo", _spotKind: "ayce" }
    };
    var km = { "Saké": 5, "Ramen Row": 12, "Sushi Bar": 8 };
    var result = M.resolveFilterSort(
      saved,
      function (name) { var spot = spots[name]; return { name: name, spot: spot, cityKey: "nyc" }; },
      "soho",
      {
        passesFilters: function (record) { return record.spot._spotKind === "omakase"; },
        matchFields: function (record) { return [record.name, record.spot.neighborhood]; },
        sortSpecs: {
          distance: { extract: function (record) { return km[record.name]; } },
          rating: { extract: function () { return 0; } }
        },
        sortBy: "distance",
        sortReversed: false
      }
    );
    // "soho" matches "Saké" and "Sushi Bar" by neighborhood, but the kind filter
    // drops the ayce "Sushi Bar"; "Ramen Row" (Midtown) does not match. Distance
    // ascending keeps [Saké], already in the delegate shape (no mapItem).
    return result.length === 1 && result[0].name === "Saké" && result[0].spot === spots["Saké"];
  })());


report();
