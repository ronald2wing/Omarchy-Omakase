// tests/city_consistency_test.js — reconcile CITY_META (catalog-utils.js) with
// CITIES (bin/cities.rb). QML can't read Ruby, so the two tables independently
// carry the display name + center coordinates for curated cities; this test
// locks their agreement so a city added/renamed in one place but not the other
// fails instead of silently drifting.
//
// Assertions:
//   (a) every CITY_META key exists in CITIES
//   (b) where CITIES has a `name`, it equals CITY_META's `name`
//   (c) where CITIES has a `center`, its coords equal CITY_META's after rounding
//       both to 4 decimal places (CITIES stores 2 dp, CITY_META 4 dp)
//   (d) the runtime-only / pipeline-only key counts are reported, not asserted.

const path = require("path");
const fs = require("fs");
const { execFileSync } = require("child_process");
const M = require("../catalog-utils.js");
const { assert, report } = require("./_assert.js");

// Load the CITIES table by shelling out once. cwd is the repo root (derived
// from __dirname), so the test runs regardless of the invoking directory.
const repoRoot = path.join(__dirname, "..");
const rubyOut = execFileSync(
  "ruby",
  ["-rjson", "-e", 'require_relative "bin/cities"; puts JSON.generate(CITIES)'],
  { cwd: repoRoot, encoding: "utf8" }
);
const CITIES = JSON.parse(rubyOut);
const CITY_META = M.CITY_META;

// Round to 4 decimal places via string formatting (avoids binary-float
// accumulation noise and expresses the precision contract directly).
const round4 = (value) => Number(value).toFixed(4);

const metaKeys = Object.keys(CITY_META);

// (a) every CITY_META key exists in CITIES.
metaKeys.forEach((key) => {
  assert("CITY_META key present in CITIES: " + key,
    Object.prototype.hasOwnProperty.call(CITIES, key));
});

// (b) + (c) name and center agreement; (d) count the asymmetric keys.
const runtimeOnly = [];
const pipelineOnly = Object.keys(CITIES).filter(
  (key) => !Object.prototype.hasOwnProperty.call(CITY_META, key)
);

metaKeys.forEach((key) => {
  const cities = CITIES[key];
  if (!cities) return; // missing key already reported in (a)
  const meta = CITY_META[key];
  const hasName = cities.name != null;
  const hasCenter = Array.isArray(cities.center);

  if (!hasName && !hasCenter) {
    runtimeOnly.push(key);
    return;
  }
  if (hasName) {
    assert("name matches for " + key, cities.name === meta.name);
  }
  if (hasCenter) {
    assert("center lat matches (4 dp) for " + key,
      round4(meta.lat) === round4(cities.center[0]));
    assert("center lon matches (4 dp) for " + key,
      round4(meta.lon) === round4(cities.center[1]));
  }
});

// (floor) The (b)/(c) checks above only run when the field is present on the
// CITIES entry, so deleting `name` or `center` from an entry would silently drop
// that key's coverage while the suite stayed green. Pin the asserted-key set:
// 13 of the 23 CITY_META keys carry both fields today, and the floor must only
// shrink if those assertions are deliberately removed.
const nameCenterFloor = 13;
const nameCenterKeys = metaKeys.filter((key) => {
  const cities = CITIES[key];
  return cities && cities.name != null && Array.isArray(cities.center);
});
assert("CITY_META keys carrying name+center in CITIES (floor " + nameCenterFloor + ", have " + nameCenterKeys.length + ")",
  nameCenterKeys.length >= nameCenterFloor);

console.log("info: " + runtimeOnly.length + " runtime-only keys (CITY_META, no name/center in CITIES): " + runtimeOnly.join(", "));
console.log("info: " + pipelineOnly.length + " pipeline-only keys (CITIES, not in CITY_META)");

// (e) every data/*.jsonl filename stem must have a CITIES entry (the documented
// invariant in CONTRIBUTING.md § Adding a city). Reads the same on-disk data
// dir the seed loader walks, so an orphaned file fails instead of silently
// drifting out of the city table.
const dataStems = fs.readdirSync(path.join(repoRoot, "data"))
  .filter((name) => name.endsWith(".jsonl"))
  .map((name) => name.slice(0, -".jsonl".length));

dataStems.forEach((stem) => {
  assert("data stem present in CITIES: " + stem,
    Object.prototype.hasOwnProperty.call(CITIES, stem));
});

report();
