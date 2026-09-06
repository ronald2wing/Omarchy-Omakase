// tests/catalog_utils_test.js — catalog-utils.js tests
const M = require("../catalog-utils.js");
let passed = 0, failed = 0;

function assert(label, cond) {
  if (cond) { passed++; } else { console.log("FAIL: " + label); failed++; }
}

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

// ----- aggregateList -----
assert("aggregateList sorts alphabetically",
  JSON.stringify(M.aggregateList({ TX: 2, CA: 3, NY: 1 }, "")) === '[{"key":"CA","name":"CA","count":3},{"key":"NY","name":"NY","count":1},{"key":"TX","name":"TX","count":2}]');
assert("aggregateList moves nearest first",
  JSON.stringify(M.aggregateList({ CA: 3, NY: 1, TX: 2 }, "TX")) === '[{"key":"TX","name":"TX","count":2},{"key":"CA","name":"CA","count":3},{"key":"NY","name":"NY","count":1}]');
assert("aggregateList absent nearest stays alphabetical",
  JSON.stringify(M.aggregateList({ CA: 3, NY: 1 }, "TX")) === '[{"key":"CA","name":"CA","count":3},{"key":"NY","name":"NY","count":1}]');
assert("aggregateList empty map", JSON.stringify(M.aggregateList({}, "")) === "[]");

// ----- displayNameFor -----
assert("displayNameFor title-cases slug", M.displayNameFor("los-angeles") === "Los Angeles");
assert("displayNameFor multi-hyphen slug", M.displayNameFor("san-francisco-bay-area") === "San Francisco Bay Area");
assert("displayNameFor plain key title-cases", M.displayNameFor("nyc") === "Nyc");
assert("displayNameFor empty", M.displayNameFor("") === "");
assert("displayNameFor null", M.displayNameFor(null) === "");

// ----- applySearchFilter -----
const searchSpots = [
  { name: "Sushi Sato", neighborhood: "SoHo", _cityKey: "nyc" },
  { name: "Ramen Row", neighborhood: "Midtown", _cityKey: "nyc" },
  { name: "Tempura Tavern", neighborhood: "SoHo", _cityKey: "tokyo" }
];
const cityNames = Object.create(null);
cityNames.nyc = "New York City";
cityNames.tokyo = "Tokyo";

assert("applySearchFilter name match",
  JSON.stringify(M.applySearchFilter(searchSpots, "sushi", cityNames).map((s) => s.name)) === '["Sushi Sato"]');
assert("applySearchFilter neighborhood match",
  JSON.stringify(M.applySearchFilter(searchSpots, "soho", cityNames).map((s) => s.name)) === '["Sushi Sato","Tempura Tavern"]');
assert("applySearchFilter city key match",
  JSON.stringify(M.applySearchFilter(searchSpots, "tokyo", cityNames).map((s) => s.name)) === '["Tempura Tavern"]');
assert("applySearchFilter city display name match",
  JSON.stringify(M.applySearchFilter(searchSpots, "new york", cityNames).map((s) => s.name)) === '["Sushi Sato","Ramen Row"]');
assert("applySearchFilter empty query returns all",
  JSON.stringify(M.applySearchFilter(searchSpots, "", cityNames).map((s) => s.name)) === '["Sushi Sato","Ramen Row","Tempura Tavern"]');
assert("applySearchFilter empty spots", JSON.stringify(M.applySearchFilter([], "x", cityNames)) === "[]");
assert("applySearchFilter no match", JSON.stringify(M.applySearchFilter(searchSpots, "zzz", cityNames)) === "[]");

// ----- Results -----
console.log("tests " + (passed + failed));
console.log("pass " + passed);
console.log("fail " + failed);
if (failed) process.exit(1);
