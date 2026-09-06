// tests/journal_identity_test.js — journal-identity.js (the cluster extracted
// from Service.qml): alias canonicalization, name-first journal matching,
// newest-wins dedupe, and the user-spot merge. These functions previously had
// zero coverage; this suite pins their current behaviour.
const J = require("../journal-identity.js");
const Spot = require("../spot-utils.js");
const { assert, assertEq, report } = require("./_assert.js");

// A representative alias map, matching what rebuildCityAliases builds for a
// catalog holding nyc / los-angeles / sao-paulo.
const ALIASES = J.buildCityAliases(["nyc", "los-angeles", "sao-paulo"]);

// ----- cityAliasToken (module-private; reached via buildCityAliases) -----
// cityAliasToken is no longer exported; its tokenization (lowercase + strip
// spaces/hyphens/non-ASCII) is exercised through buildCityAliases, whose
// derived keys ARE the alias tokens.
assertEq("cityAliasToken lowercases + strips spaces (via buildCityAliases)",
  J.buildCityAliases(["Los Angeles"]).losangeles, "Los Angeles");
assertEq("cityAliasToken strips hyphen (via buildCityAliases)",
  J.buildCityAliases(["los-angeles"]).losangeles, "los-angeles");
assertEq("cityAliasToken strips non-ASCII (via buildCityAliases)",
  J.buildCityAliases(["São Paulo"]).sopaulo, "sao-paulo");
assertEq("cityAliasToken collapses to lowercase (via buildCityAliases)",
  J.buildCityAliases(["UPPER-City"]).uppercity, "UPPER-City");
assertEq("cityAliasToken empty token drops the derived key (via buildCityAliases)",
  Object.prototype.hasOwnProperty.call(J.buildCityAliases([""]), ""), false);

// ----- buildCityAliases (derived + curated) -----
assertEq("buildCityAliases derives token->slug", J.buildCityAliases(["los-angeles"]).losangeles, "los-angeles");
assertEq("buildCityAliases derives nyc key", ALIASES.nyc, "nyc");
assertEq("buildCityAliases curated newyork -> nyc", ALIASES.newyork, "nyc");
assertEq("buildCityAliases curated newyorkcity -> nyc", ALIASES.newyorkcity, "nyc");
assertEq("buildCityAliases curated sopaulo -> sao-paulo", ALIASES.sopaulo, "sao-paulo");
assertEq("buildCityAliases derives sao-paulo token too", ALIASES.saopaulo, "sao-paulo");
assertEq("buildCityAliases empty cities still curates", J.buildCityAliases([]).newyork, "nyc");
assertEq("buildCityAliases is null-prototype", Object.getPrototypeOf(ALIASES), null);

// ----- canonicalCityKey -----
assertEq("canonicalCityKey normalizes slug", J.canonicalCityKey("Los Angeles", ALIASES), "los-angeles");
assertEq("canonicalCityKey curated new york -> nyc", J.canonicalCityKey("new york", ALIASES), "nyc");
assertEq("canonicalCityKey curated New York City -> nyc", J.canonicalCityKey("New York City", ALIASES), "nyc");
assertEq("canonicalCityKey curated São Paulo -> sao-paulo", J.canonicalCityKey("São Paulo", ALIASES), "sao-paulo");
assertEq("canonicalCityKey unknown city -> ''", J.canonicalCityKey("flushing", ALIASES), "");
assertEq("canonicalCityKey null -> ''", J.canonicalCityKey(null, ALIASES), "");
assertEq("canonicalCityKey empty -> ''", J.canonicalCityKey("", ALIASES), "");

// ----- journalSpotKey -----
assertEq("journalSpotKey name + canonical city", J.journalSpotKey({ name: "Omi Omakase", city: "nyc" }, ALIASES), "omi omakase\u0000nyc");
assertEq("journalSpotKey curated city canonicalizes", J.journalSpotKey({ name: "OMI OMAKASE", city: "New York" }, ALIASES), "omi omakase\u0000nyc");
assertEq("journalSpotKey un-mappable city -> name only", J.journalSpotKey({ name: "Omi Omakase", city: "flushing" }, ALIASES), "omi omakase");
assertEq("journalSpotKey missing city -> name only", J.journalSpotKey({ name: "Omi Omakase" }, ALIASES), "omi omakase");
assertEq("journalSpotKey missing name -> ''", J.journalSpotKey({}, ALIASES), "");
assertEq("journalSpotKey blank name -> ''", J.journalSpotKey({ name: "   " }, ALIASES), "");

// ----- findJournalIndex (name-first + city disambiguation) -----
// Newest name match wins when no lookup city is given.
assertEq("findJournalIndex wildcard returns newest name match",
  J.findJournalIndex([
    { name: "Omi Omakase", city: "nyc", timestamp: 1000 },
    { name: "Sushi Bar", city: "nyc", timestamp: 2000 },
    { name: "Omi Omakase", city: "nyc", timestamp: 3000 }
  ], "Omi Omakase", "", ALIASES), 2);

// City disambiguates two same-named spots in different canonical cities.
const sameNameTwoCities = [
  { name: "Sushi Bar", city: "nyc" },
  { name: "Sushi Bar", city: "los-angeles" }
];
assertEq("findJournalIndex city disambiguates (LA)", J.findJournalIndex(sameNameTwoCities, "Sushi Bar", "Los Angeles", ALIASES), 1);
assertEq("findJournalIndex city disambiguates (nyc)", J.findJournalIndex(sameNameTwoCities, "Sushi Bar", "nyc", ALIASES), 0);

// Entry city that can't be canonicalized ("flushing") falls back to the newest
// name-only match when no exact-city entry exists.
assertEq("findJournalIndex falls back to newest name-only match",
  J.findJournalIndex([
    { name: "Sushi Bar", city: "nyc" },
    { name: "Sushi Bar", city: "flushing" }
  ], "Sushi Bar", "los-angeles", ALIASES), 1);

// An exact city match is preferred over the name-only fallback.
assertEq("findJournalIndex exact city beats fallback",
  J.findJournalIndex([
    { name: "Sushi Bar", city: "flushing" },
    { name: "Sushi Bar", city: "nyc" },
    { name: "Sushi Bar", city: "los-angeles" }
  ], "Sushi Bar", "nyc", ALIASES), 1);

// No match, and an empty lookup name.
assertEq("findJournalIndex no match -> -1", J.findJournalIndex(sameNameTwoCities, "Ramen House", "", ALIASES), -1);
assertEq("findJournalIndex empty name -> -1", J.findJournalIndex(sameNameTwoCities, "", "", ALIASES), -1);

// ----- dedupeJournalEntries (newest wins, order preserved) -----
assertEq("dedupeJournalEntries collapses to newest and preserves order",
  JSON.stringify(J.dedupeJournalEntries([
    { name: "Omi", timestamp: 1000, rating: 3 },
    { name: "Sushi Bar", timestamp: 2000, rating: 4 },
    { name: "Omi", timestamp: 3000, rating: 5 },
    { name: "Sushi Bar", timestamp: 4000, rating: 4 }
  ], ALIASES).entries),
  JSON.stringify([
    { name: "Omi", timestamp: 3000, rating: 5 },
    { name: "Sushi Bar", timestamp: 4000, rating: 4 }
  ]));

// merged counts the number of collapsed duplicates.
assertEq("dedupeJournalEntries merged count",
  J.dedupeJournalEntries([
    { name: "Omi", timestamp: 1000 },
    { name: "Omi", timestamp: 3000 }
  ], ALIASES).merged, 1);

// Ties keep the later index (>=), so the later entry wins.
assertEq("dedupeJournalEntries timestamp tie keeps later index",
  JSON.stringify(J.dedupeJournalEntries([
    { name: "X", timestamp: 100, rating: 1 },
    { name: "X", timestamp: 100, rating: 2 }
  ], ALIASES).entries),
  JSON.stringify([{ name: "X", timestamp: 100, rating: 2 }]));

// Same name in different canonical cities are distinct entries — not merged.
assertEq("dedupeJournalEntries different cities not merged",
  J.dedupeJournalEntries([
    { name: "Sushi Bar", city: "nyc", timestamp: 1000 },
    { name: "Sushi Bar", city: "los-angeles", timestamp: 2000 }
  ], ALIASES).merged, 0);

// Same name + curated-city spellings collapse to one (newest wins).
assertEq("dedupeJournalEntries curated city spellings merge",
  JSON.stringify(J.dedupeJournalEntries([
    { name: "Sushi Bar", city: "nyc", timestamp: 1000, rating: 3 },
    { name: "Sushi Bar", city: "New York", timestamp: 2000, rating: 5 }
  ], ALIASES).entries),
  JSON.stringify([{ name: "Sushi Bar", city: "New York", timestamp: 2000, rating: 5 }]));

// Single entry / empty / non-array pass through unchanged (merged 0).
const single = [{ name: "A", timestamp: 1 }];
assertEq("dedupeJournalEntries single entry untouched",
  J.dedupeJournalEntries(single, ALIASES).entries, single);
assertEq("dedupeJournalEntries empty untouched", J.dedupeJournalEntries([], ALIASES).merged, 0);
assertEq("dedupeJournalEntries non-array untouched", J.dedupeJournalEntries(null, ALIASES).merged, 0);

// ----- mergeUserSpots (dedupe by normalized name + append) -----
const identity = (spot) => spot;

// The user spot re-states an existing catalog spot under a different case; the
// stale catalog copy is dropped and the user's copy appended (latest edit wins).
assertEq("mergeUserSpots dedupes by normalized name and appends",
  JSON.stringify(J.mergeUserSpots({
    "nyc": [
      { name: "Omi Omakase", price: "100" },
      { name: "Sushi Bar", price: "50" }
    ],
    "los-angeles": [
      { name: "LA Sushi", price: "80" }
    ]
  }, [
    { name: "OMI OMAKASE", city: "nyc", price: "120" }
  ], identity)),
  JSON.stringify({
    "nyc": [
      { name: "Sushi Bar", price: "50" },
      { name: "OMI OMAKASE", city: "nyc", price: "120" }
    ],
    "los-angeles": [
      { name: "LA Sushi", price: "80" }
    ]
  }));

// A user spot in a city the catalog doesn't have creates that city bucket.
assertEq("mergeUserSpots creates a new city bucket",
  JSON.stringify(J.mergeUserSpots({ "nyc": [] }, [
    { name: "New Spot", city: "tokyo", price: "10" }
  ], identity)),
  JSON.stringify({ "nyc": [], "tokyo": [{ name: "New Spot", city: "tokyo", price: "10" }] }));

// Case-insensitive city matching: "NYC" normalizes to the "nyc" bucket.
assertEq("mergeUserSpots matches case-insensitive city",
  JSON.stringify(J.mergeUserSpots({
    "nyc": [{ name: "Sushi Bar", price: "50" }]
  }, [
    { name: "Sushi Bar", city: "NYC", price: "60" }
  ], identity)),
  JSON.stringify({ "nyc": [{ name: "Sushi Bar", city: "NYC", price: "60" }] }));

// sanitize is applied to every surviving spot (kept catalog spots and appended
// user spots), once each.
assertEq("mergeUserSpots sanitizes kept and appended spots",
  JSON.stringify(J.mergeUserSpots({
    "nyc": [
      { name: "Omi Omakase" },
      { name: "Sushi Bar" }
    ]
  }, [
    { name: "OMI OMAKASE", city: "nyc" }
  ], (spot) => ({ name: spot.name, marked: true }))),
  JSON.stringify({
    "nyc": [
      { name: "Sushi Bar", marked: true },
      { name: "OMI OMAKASE", marked: true }
    ]
  }));

// ----- normalizeSavedEntries (wishlist shape normalization + migration) -----
// The wishlist now stores { name, city } objects mirroring the journal; the
// normalizer converts legacy bare strings and canonicalizes/optionally resolves
// each city. A name that resolves to a catalog city via `resolveCity` is
// stamped with its slug; one that does not keeps city "" (the wildcard).
const resolveCity = (name) => (name === "Omi Omakase" ? "nyc" : "");

assertEq("normalizeSavedEntries bare string -> object and resolver fills city",
  JSON.stringify(J.normalizeSavedEntries(["Omi Omakase"], ALIASES, resolveCity).entries),
  JSON.stringify([{ name: "Omi Omakase", city: "nyc" }]));
assertEq("normalizeSavedEntries bare string without resolver keeps city ''",
  JSON.stringify(J.normalizeSavedEntries(["Sushi Bar"], ALIASES, null).entries),
  JSON.stringify([{ name: "Sushi Bar", city: "" }]));
assertEq("normalizeSavedEntries canonical object round-trips unchanged",
  JSON.stringify(J.normalizeSavedEntries([{ name: "Sushi Bar", city: "nyc" }], ALIASES, null).entries),
  JSON.stringify([{ name: "Sushi Bar", city: "nyc" }]));
assertEq("normalizeSavedEntries canonical object reports changed === false",
  J.normalizeSavedEntries([{ name: "Sushi Bar", city: "nyc" }], ALIASES, null).changed, false);
assertEq("normalizeSavedEntries drops non-object/non-string elements",
  JSON.stringify(J.normalizeSavedEntries(["Sushi Bar", 42, null, true], ALIASES, null).entries),
  JSON.stringify([{ name: "Sushi Bar", city: "" }]));
assertEq("normalizeSavedEntries drops empty-name entries",
  JSON.stringify(J.normalizeSavedEntries([{ name: "", city: "nyc" }, "Sushi Bar"], ALIASES, null).entries),
  JSON.stringify([{ name: "Sushi Bar", city: "" }]));
assertEq("normalizeSavedEntries null input -> empty unchanged",
  JSON.stringify(J.normalizeSavedEntries(null, ALIASES, null)),
  JSON.stringify({ entries: [], changed: false }));
assertEq("normalizeSavedEntries non-array input -> empty unchanged",
  JSON.stringify(J.normalizeSavedEntries({ name: "X" }, ALIASES, null)),
  JSON.stringify({ entries: [], changed: false }));
assertEq("normalizeSavedEntries unresolved name keeps city ''",
  JSON.stringify(J.normalizeSavedEntries([{ name: "Ramen House", city: "" }], ALIASES, resolveCity).entries),
  JSON.stringify([{ name: "Ramen House", city: "" }]));

// The produced entries feed findJournalIndex/dedupeJournalEntries name-first
// with city disambiguation, exactly like journal entries: a bare name becomes a
// city-"" wildcard that still matches name-only, while a canonical city keeps
// two same-named spots distinct.
const sameNameSaved = J.normalizeSavedEntries([
  "Sushi Bar",
  { name: "Sushi Bar", city: "los-angeles" }
], ALIASES, null).entries;
assertEq("normalizeSavedEntries entries feed findJournalIndex city disambiguation",
  J.findJournalIndex(sameNameSaved, "Sushi Bar", "los-angeles", ALIASES), 1);
assertEq("normalizeSavedEntries entries feed findJournalIndex name-only fallback",
  J.findJournalIndex(sameNameSaved, "Sushi Bar", "nyc", ALIASES), 0);
assertEq("normalizeSavedEntries entries feed dedupeJournalEntries (city keeps distinct)",
  J.dedupeJournalEntries(sameNameSaved, ALIASES).merged, 0);

report();
