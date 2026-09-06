// tests/catalog_utils_test.js — catalog-utils.js tests
const M = require("../catalog-utils.js");
const Spot = require("../spot-utils.js");
const { assert, report } = require("./_assert.js");

// ----- coordKey -----
assert("coordKey formats lat/lon", M.coordKey(40.7, -74.0) === "40.7|-74");
assert("coordKey stable across calls", M.coordKey(40.7, -74.0) === M.coordKey(40.7, -74.0));
assert("coordKey zero coords", M.coordKey(0, 0) === "0|0");
assert("coordKey missing coords default to zero", M.coordKey(null, undefined) === "0|0");
assert("coordKey distinguishes axis order", M.coordKey(1, 2) !== M.coordKey(2, 1));

// ----- compareSortValues -----
assert("compareSortValues ascending numeric", M.compareSortValues(1, 2, "price", false) < 0);
assert("compareSortValues equal values", M.compareSortValues(2, 2, "price", false) === 0);
assert("compareSortValues reversed flips ascending", M.compareSortValues(1, 2, "price", true) > 0);
assert("compareSortValues rating descends", M.compareSortValues(4.5, 4.0, "rating", false) < 0);
assert("compareSortValues rating reversed ascends", M.compareSortValues(4.5, 4.0, "rating", true) > 0);
assert("compareSortValues rating opposes distance", M.compareSortValues(1, 2, "rating", false) !== M.compareSortValues(1, 2, "distance", false));

// ----- sortDescending -----
assert("sortDescending rating descends by default", M.sortDescending("rating", false) === true);
assert("sortDescending rating reversed ascends", M.sortDescending("rating", true) === false);
assert("sortDescending distance ascends by default", M.sortDescending("distance", false) === false);
assert("sortDescending distance reversed descends", M.sortDescending("distance", true) === true);
assert("sortDescending price ascends by default", M.sortDescending("price", false) === false);
assert("sortDescending price reversed descends", M.sortDescending("price", true) === true);

// ----- SORT_KEYS / sortLabelFor -----
assert("SORT_KEYS order", JSON.stringify(M.SORT_KEYS) === '["distance","rating","price"]');
assert("sortLabelFor distance", M.sortLabelFor("distance") === "Distance");
assert("sortLabelFor rating", M.sortLabelFor("rating") === "Rating");
assert("sortLabelFor price", M.sortLabelFor("price") === "Price");

// ----- RADIUS_STEPS / nextRadiusStep -----
assert("RADIUS_STEPS value", JSON.stringify(M.RADIUS_STEPS) === "[0,5,10,20]");
assert("nextRadiusStep off -> 5", M.nextRadiusStep(0) === 5);
assert("nextRadiusStep 5 -> 10", M.nextRadiusStep(5) === 10);
assert("nextRadiusStep 10 -> 20", M.nextRadiusStep(10) === 20);
assert("nextRadiusStep 20 wraps to off", M.nextRadiusStep(20) === 0);
assert("nextRadiusStep unknown value wraps to off", M.nextRadiusStep(7) === 0);
assert("nextRadiusStep undefined wraps to off", M.nextRadiusStep(undefined) === 0);

// ----- decoratedSort -----
const decorateItems = [
  { name: "Beta", rating: 4.0 },
  { name: "Alpha", rating: 4.5 },
  { name: "Gamma", rating: 3.5 }
];
assert("decoratedSort rating desc",
  JSON.stringify(M.decoratedSort(decorateItems, (s) => s.rating, (s) => s.name, "rating", false)) === '["Alpha","Beta","Gamma"]');
const distanceItems = [
  { name: "Far", km: 15 },
  { name: "Near", km: 5 },
  { name: "Mid", km: 10 }
];
assert("decoratedSort distance asc",
  JSON.stringify(M.decoratedSort(distanceItems, (s) => s.km, (s) => s.name, "distance", false)) === '["Near","Mid","Far"]');
assert("decoratedSort distance reversed flips",
  JSON.stringify(M.decoratedSort(distanceItems, (s) => s.km, (s) => s.name, "distance", true)) === '["Far","Mid","Near"]');

// ----- compareSortValuesWithTie -----
assert("compareSortValuesWithTie primary decides before tie-break",
  M.compareSortValuesWithTie(4.5, 4.0, "rating", false, [1], [9999]) < 0);
assert("compareSortValuesWithTie tie-break descends on equal primary",
  M.compareSortValuesWithTie(4.5, 4.5, "rating", false, [10], [400]) > 0);
assert("compareSortValuesWithTie reversed flips tie-break",
  M.compareSortValuesWithTie(4.5, 4.5, "rating", true, [10], [400]) < 0);
assert("compareSortValuesWithTie missing secondary treated as 0",
  M.compareSortValuesWithTie(4.5, 4.5, "rating", false, [undefined], [0]) === 0);

// ----- decoratedSort rating tie-break (secondary review count) -----
const ratingTieItems = [
  { name: "OneReview", rating: 4.5, reviews: 1 },
  { name: "ManyReviews", rating: 4.5, reviews: 400 },
  { name: "NoReviews", rating: 4.5 } // missing count -> 0
];
assert("decoratedSort equal ratings order by higher review count first",
  JSON.stringify(M.decoratedSort(ratingTieItems, (s) => s.rating, (s) => s.name, "rating", false, [(s) => s.reviews])) === '["ManyReviews","OneReview","NoReviews"]');
const distinctRatingItems = [
  { name: "LowMany", rating: 3.0, reviews: 9000 },
  { name: "HighFew", rating: 5.0, reviews: 2 }
];
assert("decoratedSort distinct ratings unaffected by review count",
  JSON.stringify(M.decoratedSort(distinctRatingItems, (s) => s.rating, (s) => s.name, "rating", false, [(s) => s.reviews])) === '["HighFew","LowMany"]');
assert("decoratedSort rating tie-break reversed flips both keys",
  JSON.stringify(M.decoratedSort(ratingTieItems, (s) => s.rating, (s) => s.name, "rating", true, [(s) => s.reviews])) === '["NoReviews","OneReview","ManyReviews"]');

// ----- price sort: unpriced always last, discount cheapest, rating tie-break -----
assert("compareSortValues price unpriced last ascending",
  M.compareSortValues(Infinity, 30, "price", false) > 0);
assert("compareSortValues price unpriced last descending",
  M.compareSortValues(Infinity, 30, "price", true) > 0);
assert("compareSortValues price priced before unpriced ascending",
  M.compareSortValues(30, Infinity, "price", false) < 0);
assert("compareSortValues price priced before unpriced descending",
  M.compareSortValues(30, Infinity, "price", true) < 0);
assert("compareSortValues price discount cheapest ascending",
  M.compareSortValues(-1, 30, "price", false) < 0);
assert("compareSortValues price discount last descending",
  M.compareSortValues(-1, 30, "price", true) > 0);
assert("compareSortValues price both unpriced tie",
  M.compareSortValues(Infinity, Infinity, "price", false) === 0);
assert("compareSortValues price normal ascending",
  M.compareSortValues(10, 30, "price", false) < 0);
assert("compareSortValues price normal reversed",
  M.compareSortValues(10, 30, "price", true) > 0);

assert("compareSortValuesWithTie price rating tie descends on equal price",
  M.compareSortValuesWithTie(30, 30, "price", false, [4.5, 0, ""], [4.0, 0, ""]) < 0);
assert("compareSortValuesWithTie price rating tie not flipped by direction",
  M.compareSortValuesWithTie(30, 30, "price", true, [4.5, 0, ""], [4.0, 0, ""]) < 0);
assert("compareSortValuesWithTie price equal rating falls back to review count",
  M.compareSortValuesWithTie(30, 30, "price", false, [4.5, 10, ""], [4.5, 400, ""]) > 0);
assert("compareSortValuesWithTie price review count tie not flipped by direction",
  M.compareSortValuesWithTie(30, 30, "price", true, [4.5, 10, ""], [4.5, 400, ""]) > 0);
assert("compareSortValuesWithTie price equal rating + reviews falls back to name",
  M.compareSortValuesWithTie(30, 30, "price", false, [4.5, 50, "alpha"], [4.5, 50, "beta"]) < 0);
assert("compareSortValuesWithTie price name fallback compares pre-lowercased ascending",
  M.compareSortValuesWithTie(30, 30, "price", false, [4.5, 50, "beta"], [4.5, 50, "alpha"]) > 0);
assert("compareSortValuesWithTie price equal names tie",
  M.compareSortValuesWithTie(30, 30, "price", false, [4.5, 50, "alpha"], [4.5, 50, "alpha"]) === 0);
assert("compareSortValuesWithTie price missing name treated as empty",
  M.compareSortValuesWithTie(30, 30, "price", false, [4.5, 50, ""], [4.5, 50, "alpha"]) < 0);

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
assert("decoratedSort price asc discount first, unpriced last, rating tie",
  JSON.stringify(M.decoratedSort(priceSpots, (s) => s.value, (s) => s.name, "price", false, [(s) => s.rating, (s) => s.reviews, (s) => s.name])) ===
  '["Deal","Cheap","Zeta","Alpha","Unpriced"]');
assert("decoratedSort price desc unpriced still last, discount last, rating tie",
  JSON.stringify(M.decoratedSort(priceSpots, (s) => s.value, (s) => s.name, "price", true, [(s) => s.rating, (s) => s.reviews, (s) => s.name])) ===
  '["Zeta","Alpha","Cheap","Deal","Unpriced"]');

const priceRatingTieSpots = [
  { name: "LowRating", value: 30, rating: 4.0, reviews: 100 },
  { name: "HighRating", value: 30, rating: 4.8, reviews: 1 }
];
assert("decoratedSort price rating tie-break not flipped by reversed",
  JSON.stringify(M.decoratedSort(priceRatingTieSpots, (s) => s.value, (s) => s.name, "price", true, [(s) => s.rating, (s) => s.reviews, (s) => s.name])) ===
  '["HighRating","LowRating"]');

const priceReviewTieSpots = [
  { name: "FewReviews", value: 30, rating: 4.5, reviews: 3 },
  { name: "ManyReviews", value: 30, rating: 4.5, reviews: 900 },
  { name: "NoReviews", value: 30, rating: 4.5 } // missing count -> 0
];
assert("decoratedSort price equal rating orders more reviews first",
  JSON.stringify(M.decoratedSort(priceReviewTieSpots, (s) => s.value, (s) => s.name, "price", false, [(s) => s.rating, (s) => s.reviews, (s) => s.name])) ===
  '["ManyReviews","FewReviews","NoReviews"]');
assert("decoratedSort price review tie-break not flipped by reversed",
  JSON.stringify(M.decoratedSort(priceReviewTieSpots, (s) => s.value, (s) => s.name, "price", true, [(s) => s.rating, (s) => s.reviews, (s) => s.name])) ===
  '["ManyReviews","FewReviews","NoReviews"]');

const priceRatingNameTieSpots = [
  { name: "Beta", value: 30, rating: 4.5, reviews: 10 },
  { name: "Alpha", value: 30, rating: 4.5, reviews: 10 }
];
assert("decoratedSort price equal rating + reviews falls back to name",
  JSON.stringify(M.decoratedSort(priceRatingNameTieSpots, (s) => s.value, (s) => s.name, "price", false, [(s) => s.rating, (s) => s.reviews, (s) => s.name])) ===
  '["Alpha","Beta"]');

// The name fallback compares pre-lowercased strings with a plain `<`/`>`; the
// caller lowercases at decorate time. Mixed-case names still sort case-
// insensitively when the extractor lowercases.
const priceMixedCaseNameSpots = [
  { name: "beta", value: 30, rating: 4.5, reviews: 10 },
  { name: "Alpha", value: 30, rating: 4.5, reviews: 10 }
];
assert("decoratedSort price name tie-break case-insensitive via pre-lowercased extractor",
  JSON.stringify(M.decoratedSort(priceMixedCaseNameSpots, (s) => s.value, (s) => s.name, "price", false, [(s) => s.rating, (s) => s.reviews, (s) => s.name.toLowerCase()])) ===
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

// ----- aggregateList -----
assert("aggregateList sorts alphabetically",
  JSON.stringify(M.aggregateList({ TX: 2, CA: 3, NY: 1 }, "")) === '[{"key":"CA","count":3},{"key":"NY","count":1},{"key":"TX","count":2}]');
assert("aggregateList moves nearest first",
  JSON.stringify(M.aggregateList({ CA: 3, NY: 1, TX: 2 }, "TX")) === '[{"key":"TX","count":2},{"key":"CA","count":3},{"key":"NY","count":1}]');
assert("aggregateList absent nearest stays alphabetical",
  JSON.stringify(M.aggregateList({ CA: 3, NY: 1 }, "TX")) === '[{"key":"CA","count":3},{"key":"NY","count":1}]');
assert("aggregateList empty map", JSON.stringify(M.aggregateList({}, "")) === "[]");

// ----- displayNameFor -----
assert("displayNameFor title-cases slug", M.displayNameFor("los-angeles") === "Los Angeles");
assert("displayNameFor multi-hyphen slug", M.displayNameFor("san-francisco-bay-area") === "San Francisco Bay Area");
assert("displayNameFor plain key title-cases", M.displayNameFor("nyc") === "Nyc");
assert("displayNameFor empty", M.displayNameFor("") === "");
assert("displayNameFor null", M.displayNameFor(null) === "");

// ----- search rank constants -----
assert("NAME_EXACT value", M.NAME_EXACT === 2);
assert("MATCH value", M.MATCH === 1);
assert("search constants strictly descend",
  M.NAME_EXACT > M.MATCH && M.MATCH > 0);

// ----- foldSpot -----
assert("foldSpot folds name/neighborhood",
  JSON.stringify(M.foldSpot({ name: "Saké", neighborhood: "SoHo" })) ===
  '{"name":"sake","neighborhood":"soho"}');
assert("foldSpot empty spot folds empty strings",
  JSON.stringify(M.foldSpot({})) === '{"name":"","neighborhood":""}');
assert("foldSpot null spot",
  JSON.stringify(M.foldSpot(null)) === '{"name":"","neighborhood":""}');

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

// ----- matchClass tiers -----
assert("matchClass exact",
  M.matchClass({ name: "sushi", neighborhood: "" }, "sushi") === M.NAME_EXACT);
assert("matchClass name-prefix",
  M.matchClass({ name: "sushi bar", neighborhood: "" }, "sushi") === M.MATCH);
assert("matchClass word-start",
  M.matchClass({ name: "soba sushi", neighborhood: "" }, "sushi") === M.MATCH);
assert("matchClass mid-word substring",
  M.matchClass({ name: "asushiya", neighborhood: "" }, "sushi") === M.MATCH);
assert("matchClass neighborhood substring",
  M.matchClass({ name: "", neighborhood: "soho" }, "soho") === M.MATCH);
assert("matchClass city-label-only match returns 0",
  M.matchClass({ name: "", neighborhood: "", city: "tokyo" }, "tokyo") === 0);
assert("matchClass no match",
  M.matchClass({ name: "sushi", neighborhood: "" }, "ramen") === 0);
assert("matchClass empty query",
  M.matchClass({ name: "sushi", neighborhood: "" }, "") === 0);
assert("matchClass blank name does not throw",
  M.matchClass({ name: null, neighborhood: "" }, "sushi") === 0);

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

// Trade-off: city-label matching left the card list, so a query like "city" now
// returns only spots whose name or neighborhood contains "city" — not the 200+
// spots that used to match via their city's label alone.
const cityTradeoffSpots = [];
for (var cityIdx = 0; cityIdx < 200; cityIdx++) {
  cityTradeoffSpots.push({ name: "Sushi Spot " + cityIdx, neighborhood: "", city: "New York City" });
}
cityTradeoffSpots.push({ name: "Sushi City", neighborhood: "", city: "Tokyo" });
cityTradeoffSpots.push({ name: "Ramen Shop", neighborhood: "City Center", city: "Tokyo" });
assert("rankSpots 'city' matches name/neighborhood only (2, not 200+)",
  JSON.stringify(M.rankSpots(cityTradeoffSpots, "city").map((s) => s.name)) ===
  '["Sushi City","Ramen Shop"]');

// ----- spotCountLabel -----
assert("spotCountLabel zero", M.spotCountLabel(0) === "0 spots");
assert("spotCountLabel one", M.spotCountLabel(1) === "1 spot");
assert("spotCountLabel two", M.spotCountLabel(2) === "2 spots");
assert("spotCountLabel undefined", M.spotCountLabel(undefined) === "0 spots");

// ----- countLabel (invariant nouns — never pluralized) -----
assert("countLabel saved singular", M.countLabel(1, "saved") === "1 saved");
assert("countLabel saved plural stays invariant", M.countLabel(2, "saved") === "2 saved");
assert("countLabel rated plural stays invariant", M.countLabel(3, "rated") === "3 rated");
assert("countLabel undefined", M.countLabel(undefined, "saved") === "0 saved");

// ----- capitalize -----
assert("capitalize lower", M.capitalize("omakase") === "Omakase");
assert("capitalize already upper", M.capitalize("Omakase") === "Omakase");
assert("capitalize empty", M.capitalize("") === "");
assert("capitalize undefined", M.capitalize(undefined) === "");
assert("capitalize null", M.capitalize(null) === "");
assert("capitalize single char", M.capitalize("a") === "A");

// ----- formatRadius -----
assert("formatRadius", M.formatRadius(10) === "Within 10 km");
assert("formatRadius five", M.formatRadius(5) === "Within 5 km");
assert("formatRadius zero", M.formatRadius(0) === "Within 0 km");

// ----- SEP -----
assert("SEP value", M.SEP === " · ");
assert("SEP matches spot-utils", M.SEP === Spot.SEP);
assert("SEP_LEAD value", M.SEP_LEAD === "· ");
assert("SEP_LEAD matches spot-utils", M.SEP_LEAD === Spot.SEP_LEAD);

// ----- filterDescription -----
// The search term is deliberately NOT a segment (no searchText parameter): the
// query's effect is owned by CityHeader's ` matching "…"` suffix (Explore) and
// the spotlight search field shows it directly, so it never appears here twice.
assert("filterDescription default", M.filterDescription("", "all", false, "distance", 0, "") === "All cities");
assert("filterDescription city label only", M.filterDescription("New York City", "all", false, "distance", 0, "") === "New York City");
assert("filterDescription kind filter", M.filterDescription("", "omakase", false, "distance", 0, "") === "All cities · Omakase");
assert("filterDescription unratedOnly", M.filterDescription("", "all", true, "distance", 0, "") === "All cities · Unrated");
assert("filterDescription sort filter", M.filterDescription("", "all", false, "rating", 0, "") === "All cities · Rating");
assert("filterDescription radius filter", M.filterDescription("", "all", false, "distance", 10, "") === "All cities · Within 10 km");
assert("filterDescription neighborhood filter", M.filterDescription("", "all", false, "distance", 0, "SoHo") === "All cities · SoHo");
assert("filterDescription omits the search term", M.filterDescription("New York City", "all", false, "rating", 0, "") === "New York City · Rating");
assert("filterDescription multi-filter", M.filterDescription("Tokyo", "omakase", true, "rating", 5, "Shibuya") === 'Tokyo · Omakase · Unrated · Rating · Within 5 km · Shibuya');

// ----- surprisePoolCriteria -----
// The surprise pool is the filtered AND searched set, so the criteria line
// reports the search query as a restriction and omits the sort (the sort
// orders the displayed list but cannot change pool membership). Unlike
// filterDescription there is no sortBy parameter, so a sort can never leak in.
assert("QUERY_DISPLAY_CAP value", M.QUERY_DISPLAY_CAP === 24);
assert("surprisePoolCriteria default", M.surprisePoolCriteria("", "all", false, 0, "", "") === "All cities");
assert("surprisePoolCriteria city label only", M.surprisePoolCriteria("New York City", "all", false, 0, "", "") === "New York City");
assert("surprisePoolCriteria kind filter", M.surprisePoolCriteria("", "omakase", false, 0, "", "") === "All cities · Omakase");
assert("surprisePoolCriteria unratedOnly", M.surprisePoolCriteria("", "all", true, 0, "", "") === "All cities · Unrated");
assert("surprisePoolCriteria radius filter", M.surprisePoolCriteria("", "all", false, 10, "", "") === "All cities · Within 10 km");
assert("surprisePoolCriteria neighborhood filter", M.surprisePoolCriteria("", "all", false, 0, "SoHo", "") === "All cities · SoHo");
assert("surprisePoolCriteria query (reported case)", M.surprisePoolCriteria("", "all", false, 0, "", "new") === 'All cities · "new"');
assert("surprisePoolCriteria query trims surrounding whitespace", M.surprisePoolCriteria("", "all", false, 0, "", "  new york  ") === 'All cities · "new york"');
assert("surprisePoolCriteria whitespace-only query omits the segment", M.surprisePoolCriteria("", "all", false, 0, "", "   ") === "All cities");
assert("surprisePoolCriteria scope + kind + radius", M.surprisePoolCriteria("New York City", "discount", false, 10, "", "") === "New York City · Discount · Within 10 km");
// Fully loaded: every pool-restricting filter plus the query, and no sort
// segment anywhere (sortBy is not a parameter, so "Rating"/"Distance"/"Price"
// cannot appear).
assert("surprisePoolCriteria fully loaded omits sort and includes query", M.surprisePoolCriteria("Tokyo", "omakase", true, 5, "Shibuya", "sushi") === 'Tokyo · Omakase · Unrated · Within 5 km · Shibuya · "sushi"');
// A 24-char query fits the cap verbatim; a 25-char query is truncated to 24
// plus an ellipsis — the same convention CityHeader's hint and the search
// dropdown's query row apply.
assert("surprisePoolCriteria 24-char query fits the cap", M.surprisePoolCriteria("", "all", false, 0, "", "abcdefghijklmnopqrstuvwx") === 'All cities · "abcdefghijklmnopqrstuvwx"');
assert("surprisePoolCriteria longer query capped with ellipsis", M.surprisePoolCriteria("", "all", false, 0, "", "abcdefghijklmnopqrstuvwxy") === 'All cities · "abcdefghijklmnopqrstuvwx…"');

// ----- computeNeighborhoodOptions -----
assert("computeNeighborhoodOptions empty index",
  JSON.stringify(M.computeNeighborhoodOptions([])) === '[]');
assert("computeNeighborhoodOptions null spots",
  JSON.stringify(M.computeNeighborhoodOptions(null)) === '[]');
assert("computeNeighborhoodOptions single spot",
  JSON.stringify(M.computeNeighborhoodOptions([{ neighborhood: "SoHo" }])) === '["SoHo"]');
assert("computeNeighborhoodOptions sorted + dedup",
  JSON.stringify(M.computeNeighborhoodOptions([
    { neighborhood: "Midtown" }, { neighborhood: "SoHo" }, { neighborhood: "Midtown" }, { neighborhood: "Chelsea" }
  ])) === '["Chelsea","Midtown","SoHo"]');
assert("computeNeighborhoodOptions trims and drops empty",
  JSON.stringify(M.computeNeighborhoodOptions([
    { neighborhood: "  SoHo  " }, { neighborhood: "" }, { neighborhood: "   " }, { neighborhood: null }
  ])) === '["SoHo"]');
// The 13 single-neighborhood cities (amsterdam, austin, barcelona, denver,
// melbourne, montreal, munich, philadelphia, prague, rome, san-antonio,
// san-diego, seattle) each yield exactly one real neighborhood. With the ""
// sentinel dropped, showNeighborhoodChips/hasNeighborhoods gate on
// `length > 0`, so one neighborhood must still satisfy that.
assert("computeNeighborhoodOptions one neighborhood keeps > 0 gate",
  M.computeNeighborhoodOptions([{ neighborhood: "SoHo" }]).length > 0 === true);
assert("computeNeighborhoodOptions zero neighborhoods hides the row",
  M.computeNeighborhoodOptions([{ neighborhood: "" }, { neighborhood: null }]).length > 0 === false);

// ----- computeSortedCities -----
const cityDistances = Object.create(null);
cityDistances.nyc = 12;
cityDistances.chi = 8;
cityDistances.la = 30;
cityDistances.geoless = Infinity;
assert("computeSortedCities orders by distance",
  JSON.stringify(M.computeSortedCities(["la", "nyc", "chi"], (k) => cityDistances[k])) === '["chi","nyc","la"]');
assert("computeSortedCities geo-less last",
  JSON.stringify(M.computeSortedCities(["geoless", "la", "chi"], (k) => cityDistances[k])) === '["chi","la","geoless"]');
assert("computeSortedCities all geo-less keeps input order",
  JSON.stringify(M.computeSortedCities(["geoless", "chi", "la"], (k) => Infinity)) === '["geoless","chi","la"]');
const tieDistances = { a: 5, b: 5, c: 5 };
assert("computeSortedCities ties stable",
  JSON.stringify(M.computeSortedCities(["b", "a", "c"], (k) => tieDistances[k])) === '["b","a","c"]');
assert("computeSortedCities empty list", JSON.stringify(M.computeSortedCities([], (k) => 0)) === "[]");
assert("computeSortedCities null list", JSON.stringify(M.computeSortedCities(null, (k) => 0)) === "[]");

// ----- sortSearchHits -----
// The sort reads each hit's own `distance` (km, may be Infinity/undefined when
// geo-less): cities/neighborhoods carry their representative spot's distance,
// states carry their nearest spot's distance. Order is uniform — finite
// distance ascending, geo-less last, type as the tie-break, then name/key —
// with a count-descending fallback for geo-less states.

assert("sortSearchHits nearby neighborhood outranks far city (reported case)",
  JSON.stringify(M.sortSearchHits([
    { type: "city", key: "mexico-city", name: "Mexico City", count: 5, distance: 3374 },
    { type: "neighborhood", key: "Long Island City", name: "Long Island City", cityKey: "nyc", cityName: "New York City", count: 1, distance: 13.6 }
  ]).map((h) => h.type + ":" + h.name)) ===
  '["neighborhood:Long Island City","city:Mexico City"]');

assert("sortSearchHits nearest located hit first overall",
  JSON.stringify(M.sortSearchHits([
    { type: "city", key: "mexico-city", name: "Mexico City", count: 5, distance: 3374 },
    { type: "city", key: "nyc", name: "New York City", count: 214, distance: 17.9 },
    { type: "neighborhood", key: "Long Island City", name: "Long Island City", cityKey: "nyc", cityName: "New York City", count: 1, distance: 13.6 }
  ]).map((h) => h.name)) ===
  '["Long Island City","New York City","Mexico City"]');

assert("sortSearchHits nearby city outranks farther city",
  JSON.stringify(M.sortSearchHits([
    { type: "city", key: "auckland", name: "Auckland", count: 88, distance: 14000 },
    { type: "city", key: "nyc", name: "New York City", count: 214, distance: 3 }
  ]).map((h) => h.key)) === '["nyc","auckland"]');

assert("sortSearchHits geo-less city sorts after located city",
  JSON.stringify(M.sortSearchHits([
    { type: "city", key: "geoless", name: "Geoless", count: 1, distance: Infinity },
    { type: "city", key: "nyc", name: "New York City", count: 214, distance: 3 }
  ]).map((h) => h.key)) === '["nyc","geoless"]');

assert("sortSearchHits type tie-break on equal distance: city before neighborhood before state",
  JSON.stringify(M.sortSearchHits([
    { type: "state", key: "NY", name: "New York", count: 214, distance: 5 },
    { type: "neighborhood", key: "Soho", name: "Soho", cityKey: "nyc", cityName: "New York City", count: 5, distance: 5 },
    { type: "city", key: "nyc", name: "New York City", count: 214, distance: 5 }
  ]).map((h) => h.type)) === '["city","neighborhood","state"]');

assert("sortSearchHits type tie-break when both geo-less: city before neighborhood",
  JSON.stringify(M.sortSearchHits([
    { type: "neighborhood", key: "Soho", name: "Soho", cityKey: "nyc", cityName: "New York City", count: 5, distance: Infinity },
    { type: "city", key: "nyc", name: "New York City", count: 214, distance: Infinity }
  ]).map((h) => h.type)) === '["city","neighborhood"]');

assert("sortSearchHits two same-city neighborhoods order by own distance (LIC before Jersey City)",
  JSON.stringify(M.sortSearchHits([
    { type: "neighborhood", key: "Jersey City", name: "Jersey City", cityKey: "nyc", cityName: "New York City", count: 1, distance: 21.2 },
    { type: "neighborhood", key: "Long Island City", name: "Long Island City", cityKey: "nyc", cityName: "New York City", count: 1, distance: 13.6 }
  ]).map((h) => h.key)) === '["Long Island City","Jersey City"]');

assert("sortSearchHits true distance tie falls back to name",
  JSON.stringify(M.sortSearchHits([
    { type: "neighborhood", key: "Zebra", name: "Zebra", cityKey: "nyc", cityName: "New York City", count: 1, distance: 10 },
    { type: "neighborhood", key: "Alpha", name: "Alpha", cityKey: "nyc", cityName: "New York City", count: 1, distance: 10 }
  ]).map((h) => h.key)) === '["Alpha","Zebra"]');

assert("sortSearchHits geo-less states fall back to count descending",
  JSON.stringify(M.sortSearchHits([
    { type: "state", key: "NJ", name: "New Jersey", count: 10 },
    { type: "state", key: "NY", name: "New York", count: 214 },
    { type: "state", key: "NM", name: "New Mexico", count: 5 }
  ]).map((h) => h.key)) === '["NY","NJ","NM"]');

assert("sortSearchHits equal geo-less state counts tie-break by name",
  JSON.stringify(M.sortSearchHits([
    { type: "state", key: "TX", name: "Texas", count: 10 },
    { type: "state", key: "CA", name: "California", count: 10 }
  ]).map((h) => h.key)) === '["CA","TX"]');

assert("sortSearchHits located hits precede states, even a geo-less one",
  JSON.stringify(M.sortSearchHits([
    { type: "state", key: "NY", name: "New York", count: 214 },
    { type: "neighborhood", key: "Soho", name: "Soho", cityKey: "nyc", cityName: "New York City", count: 5, distance: Infinity },
    { type: "city", key: "nyc", name: "New York City", count: 214, distance: 17.9 }
  ]).map((h) => h.type)) === '["city","neighborhood","state"]');

assert("sortSearchHits geo-less state sorts after a geo-less neighborhood",
  JSON.stringify(M.sortSearchHits([
    { type: "state", key: "NY", name: "New York", count: 214 },
    { type: "neighborhood", key: "Soho", name: "Soho", cityKey: "nyc", cityName: "New York City", count: 5, distance: Infinity }
  ]).map((h) => h.type)) === '["neighborhood","state"]');

// The reported case: a near state outranks a far neighborhood, and also
// outranks a farther city — proximity now orders states uniformly with the
// located hits instead of pushing them to the end.
assert("sortSearchHits near state outranks far neighborhood and farther city",
  JSON.stringify(M.sortSearchHits([
    { type: "city", key: "mexico-city", name: "Mexico City", count: 5, distance: 3374 },
    { type: "neighborhood", key: "Newmarket", name: "Newmarket", cityKey: "auckland", cityName: "Auckland", count: 4, distance: 14211 },
    { type: "state", key: "NY", name: "New York", count: 169, distance: 5 }
  ]).map((h) => h.type + ":" + h.name)) ===
  '["state:New York","city:Mexico City","neighborhood:Newmarket"]');

// A state whose spots all lack coordinates carries no usable distance and still
// sorts last, keeping count-descending then name among its geo-less peers.
assert("sortSearchHits geo-less state sorts last with count-descending fallback",
  JSON.stringify(M.sortSearchHits([
    { type: "state", key: "NH", name: "New Hampshire", count: 8 },
    { type: "city", key: "nyc", name: "New York City", count: 214, distance: 3 },
    { type: "state", key: "NY", name: "New York", count: 214 },
    { type: "state", key: "NM", name: "New Mexico", count: 5 }
  ]).map((h) => h.type + ":" + h.name)) ===
  '["city:New York City","state:New York","state:New Hampshire","state:New Mexico"]');

assert("sortSearchHits equal distance + name falls back to key",
  JSON.stringify(M.sortSearchHits([
    { type: "city", key: "springfield-mo", name: "Springfield", count: 1, distance: 10 },
    { type: "city", key: "springfield-il", name: "Springfield", count: 1, distance: 10 }
  ]).map((h) => h.key)) === '["springfield-il","springfield-mo"]');

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

// The user's "new" case, end to end: the near city, then the New* states by
// their own proximity (nearest spot in the state), then the far Auckland
// neighborhoods. The states no longer sort last by count — New Jersey (23,
// ~10 km) outranks New Hampshire (66, ~350 km) because distance now dominates.
assert("sortSearchHits 'new' case: states by proximity, before far neighborhoods",
  JSON.stringify(M.sortSearchHits([
    { type: "neighborhood", key: "Newmarket", name: "Newmarket", cityKey: "auckland", cityName: "Auckland", count: 4, distance: 14211 },
    { type: "state", key: "NJ", name: "New Jersey", count: 23, distance: 10 },
    { type: "city", key: "nyc", name: "New York City", count: 214, distance: 3 },
    { type: "neighborhood", key: "Newton", name: "Newton", cityKey: "auckland", cityName: "Auckland", count: 2, distance: 14211 },
    { type: "state", key: "NH", name: "New Hampshire", count: 66, distance: 350 },
    { type: "state", key: "NY", name: "New York", count: 169, distance: 5 }
  ]).map((h) => h.type + ":" + h.name)) ===
  '["city:New York City","state:New York","state:New Jersey","state:New Hampshire","neighborhood:Newmarket","neighborhood:Newton"]');

// ----- computeLocationAggregates -----
const noDistance = () => undefined;

assert("computeLocationAggregates empty list",
  JSON.stringify(M.computeLocationAggregates([], noDistance)) ===
  '{"stateCounts":{},"countryCounts":{},"nearestState":"","nearestCountry":"","stateDistances":{}}');

assert("computeLocationAggregates single location",
  JSON.stringify(M.computeLocationAggregates(
    [{ name: "Solo", state: "NY", country: "US" }], () => 5)) ===
  '{"stateCounts":{"NY":1},"countryCounts":{"US":1},"nearestState":"NY","nearestCountry":"US","stateDistances":{"NY":5}}');

assert("computeLocationAggregates multiple locations counts + nearest",
  (function () {
    const spots = [
      { name: "Far", state: "CA", country: "US" },
      { name: "Near", state: "NY", country: "US" },
      { name: "Mid", state: "TX", country: "US" },
      { name: "OtherNY", state: "NY", country: "US" }
    ];
    const distances = { Far: 3000, Near: 5, Mid: 2000, OtherNY: 800 };
    const agg = M.computeLocationAggregates(spots, (s) => distances[s.name]);
    return JSON.stringify(agg) ===
      '{"stateCounts":{"CA":1,"NY":2,"TX":1},"countryCounts":{"US":4},"nearestState":"NY","nearestCountry":"US","stateDistances":{"CA":3000,"NY":5,"TX":2000}}';
  })());

assert("computeLocationAggregates stateDistances keeps nearest spot per state",
  (function () {
    const spots = [
      { name: "NearNY", state: "NY", country: "US" },
      { name: "FarNY", state: "NY", country: "US" },
      { name: "NJSpot", state: "NJ", country: "US" }
    ];
    const agg = M.computeLocationAggregates(spots, (s) =>
      s.name === "NearNY" ? 5 : s.name === "FarNY" ? 800 : 10);
    return agg.stateDistances.NY === 5 && agg.stateDistances.NJ === 10;
  })());

assert("computeLocationAggregates undefined distance never wins nearest",
  (function () {
    const agg = M.computeLocationAggregates(
      [{ name: "Geoless", state: "NY", country: "US" }], noDistance);
    return agg.stateCounts.NY === 1 && agg.countryCounts.US === 1 &&
           agg.nearestState === "" && agg.nearestCountry === "" &&
           agg.stateDistances.NY === undefined;
  })());

assert("computeLocationAggregates non-US region code not counted as state",
  (function () {
    const agg = M.computeLocationAggregates(
      [{ name: "Melb", state: "VIC", country: "AU" }], () => 1);
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
      [{ name: "Ken-Ichi", state: "NH", country: "NL" }], () => 5857);
    return JSON.stringify(agg.stateCounts) === "{}" &&
           agg.countryCounts.NL === 1 &&
           agg.nearestState === "" &&
           JSON.stringify(agg.stateDistances) === "{}";
  })());

// The same code, but a genuine US spot (country US), is still the real state.
assert("computeLocationAggregates genuine US state with colliding code still counted",
  (function () {
    const agg = M.computeLocationAggregates(
      [{ name: "Concord", state: "NH", country: "US" }], () => 5);
    return agg.stateCounts.NH === 1 && agg.countryCounts.US === 1 &&
           agg.nearestState === "NH" && agg.stateDistances.NH === 5;
  })());

// A genuine US state whose spots all lack coordinates still counts, but carries
// no distance and never wins "nearest" (the geo-less fallback).
assert("computeLocationAggregates geo-less US state counts but carries no distance",
  (function () {
    const agg = M.computeLocationAggregates(
      [{ name: "Geoless NH", state: "NH", country: "US" }], noDistance);
    return agg.stateCounts.NH === 1 && agg.countryCounts.US === 1 &&
           agg.nearestState === "" && agg.stateDistances.NH === undefined;
  })());

assert("computeLocationAggregates trims and uppercases state/country",
  (function () {
    const agg = M.computeLocationAggregates(
      [{ name: "A", state: "  ny ", country: " us " }], noDistance);
    return agg.stateCounts.NY === 1 && agg.countryCounts.US === 1 &&
           JSON.stringify(agg.stateDistances) === "{}";
  })());

assert("computeLocationAggregates null spots treated as empty",
  JSON.stringify(M.computeLocationAggregates(null, noDistance)) ===
  '{"stateCounts":{},"countryCounts":{},"nearestState":"","nearestCountry":"","stateDistances":{}}');

// ----- CITY_META / cityMetaFor (locks the moved data literal) -----
assert("CITY_META has 23 entries", Object.keys(M.CITY_META).length === 23);
assert("cityMetaFor nyc name", M.cityMetaFor("nyc").name === "New York City");
assert("cityMetaFor nyc center", M.cityMetaFor("nyc").lat === 40.7128 && M.cityMetaFor("nyc").lon === -74.0060);
assert("cityMetaFor sao-paulo keeps accent", M.cityMetaFor("sao-paulo").name === "São Paulo");
assert("cityMetaFor sao-paulo center", M.cityMetaFor("sao-paulo").lat === -23.5505 && M.cityMetaFor("sao-paulo").lon === -46.6333);
assert("cityMetaFor washington-dc name", M.cityMetaFor("washington-dc").name === "Washington DC");
assert("cityMetaFor australia country-level", M.cityMetaFor("australia").name === "Australia" && M.cityMetaFor("australia").lat === -33.8688 && M.cityMetaFor("australia").lon === 151.2093);
assert("cityMetaFor tokyo name", M.cityMetaFor("tokyo").name === "Tokyo");
assert("cityMetaFor unknown key returns null", M.cityMetaFor("atlantis") === null);
assert("cityMetaFor constructor-safe", M.cityMetaFor("constructor") === null);
assert("cityMetaFor empty key returns null", M.cityMetaFor("") === null);

// ----- cityLabelFor -----
assert("cityLabelFor nyc resolves CITY_META name", M.cityLabelFor("nyc") === "New York City");
assert("cityLabelFor sao-paulo keeps accent", M.cityLabelFor("sao-paulo") === "São Paulo");
assert("cityLabelFor unknown key title-cases", M.cityLabelFor("atlantis") === "Atlantis");
assert("cityLabelFor multi-hyphen unknown title-cases", M.cityLabelFor("san-jose") === "San Jose");
assert("cityLabelFor constructor-safe", M.cityLabelFor("constructor") === "Constructor");
assert("cityLabelFor empty key safe", M.cityLabelFor("") === "");
assert("cityLabelFor null safe", M.cityLabelFor(null) === "");

// Dropdown unaffected: the card-list rank change touched only
// rankSpots/matchClass/foldSpot. BarWidget.searchMatches still resolves a city
// label (via cityLabelFor) and folds it for the dropdown, so a city-name query
// still yields a city hit even though rankSpots no longer matches the label.
assert("city-name query still resolves a city label for the dropdown",
  Spot.foldSearchText(M.cityLabelFor("nyc")).indexOf(Spot.foldSearchText("new york")) === 0);

// ----- US_STATES (locks the moved data literal) -----
assert("US_STATES has 51 entries (50 states + DC)", Object.keys(M.US_STATES).length === 51);
assert("US_STATES contains CA", M.US_STATES.CA === 1);
assert("US_STATES contains NY", M.US_STATES.NY === 1);
assert("US_STATES contains TX", M.US_STATES.TX === 1);
assert("US_STATES contains DC", M.US_STATES.DC === 1);
assert("US_STATES rejects non-US VIC", M.US_STATES.VIC === undefined);
assert("US_STATES rejects Lisbon region 11", M.US_STATES["11"] === undefined);

// ----- US_STATE_NAMES / stateNameFor -----
assert("US_STATE_NAMES has 51 entries (50 states + DC)", Object.keys(M.US_STATE_NAMES).length === 51);
assert("US_STATE_NAMES keys all pass US_STATES validity",
  Object.keys(M.US_STATE_NAMES).every((code) => M.US_STATES[code] === 1));
assert("every US_STATES code resolves a state name",
  Object.keys(M.US_STATES).every((code) => typeof M.US_STATE_NAMES[code] === "string" && M.US_STATE_NAMES[code].length > 0));
assert("stateNameFor NY resolves full name", M.stateNameFor("NY") === "New York");
assert("stateNameFor NJ resolves full name", M.stateNameFor("NJ") === "New Jersey");
assert("stateNameFor NM resolves full name", M.stateNameFor("NM") === "New Mexico");
assert("stateNameFor NH resolves full name", M.stateNameFor("NH") === "New Hampshire");
assert("stateNameFor DC resolves", M.stateNameFor("DC") === "Washington DC");
assert("stateNameFor unknown code returns null", M.stateNameFor("VIC") === null);
assert("stateNameFor constructor-safe", M.stateNameFor("constructor") === null);
assert("stateNameFor empty code returns null", M.stateNameFor("") === null);

// ----- isUsState (country-gated US-state predicate) -----
assert("isUsState US state + US country", M.isUsState({ state: "NY", country: "US" }) === true);
assert("isUsState colliding foreign region rejected", M.isUsState({ state: "NH", country: "NL" }) === false);
assert("isUsState US code with absent country rejected", M.isUsState({ state: "NY" }) === false);
assert("isUsState US code with foreign country rejected", M.isUsState({ state: "NY", country: "CA" }) === false);
assert("isUsState non-US region code rejected", M.isUsState({ state: "VIC", country: "AU" }) === false);
assert("isUsState null spot", M.isUsState(null) === false);
assert("isUsState trims and uppercases", M.isUsState({ state: "  ny ", country: " us " }) === true);

// A "new"-style query reaches all four New* states by full name (the raw code
// "NY"/"NJ"/"NM"/"NH" could never match "new"), and a "ny" code query still
// matches the raw code — both folded with the shared search path.
assert("'new' query reaches all four New* states by full name",
  ["NJ", "NM", "NH", "NY"].every((code) =>
    Spot.foldSearchText(M.stateNameFor(code)).indexOf(Spot.foldSearchText("new")) === 0));
assert("'ny' code query still matches the raw NY code",
  Spot.foldSearchText("NY").indexOf(Spot.foldSearchText("ny")) >= 0);

// ----- build*FilterItems -----
assert("buildCityFilterItems name + distance + count",
  JSON.stringify(M.buildCityFilterItems(
    ["nyc", "los-angeles"],
    (k) => ({ nyc: "3.2 km", "los-angeles": "" }[k]),
    { nyc: [{}, {}], "los-angeles": [{}] }
  )) === '[{"key":"nyc","label":"New York City · 3.2 km · 2 spots"},{"key":"los-angeles","label":"Los Angeles · 1 spot"}]');

assert("buildCityFilterItems empty distance omitted",
  JSON.stringify(M.buildCityFilterItems(["nyc"], () => "", { nyc: [{}, {}, {}] })) === '[{"key":"nyc","label":"New York City · 3 spots"}]');

assert("buildStateFilterItems",
  JSON.stringify(M.buildStateFilterItems([{ key: "NY", count: 2 }, { key: "CA", count: 1 }])) === '[{"key":"NY","label":"NY · 2 spots"},{"key":"CA","label":"CA · 1 spot"}]');

assert("buildCountryFilterItems",
  JSON.stringify(M.buildCountryFilterItems([{ key: "US", count: 3 }])) === '[{"key":"US","label":"US · 3 spots"}]');

assert("buildNeighborhoodFilterItems",
  JSON.stringify(M.buildNeighborhoodFilterItems(["SoHo", "Chelsea"])) === '[{"key":"SoHo","label":"SoHo"},{"key":"Chelsea","label":"Chelsea"}]');

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

// ----- Results -----
report();
