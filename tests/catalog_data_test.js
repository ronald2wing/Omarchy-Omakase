// tests/catalog_data_test.js — catalog-utils.js data literals
// (CITY_META/US_STATES/US_STATE_NAMES), the label/state lookups (cityLabelFor,
// stateNameFor, isUsState), computeLocationAggregates constructor-safety, and
// the dual-use export guard (QML references resolve to exports).
const M = require("../catalog-utils.js");
const Spot = require("../spot-utils.js");
const JournalIdentity = require("../journal-identity.js");
const fs = require("fs");
const path = require("path");
const { assert, report } = require("./_assert.js");

// ----- hasOwn (module-private null-safe own-property check) -----
// hasOwn is module-private; its guard is reached through cityMetaFor and
// stateNameFor, both of which return null (not an Object.prototype member) for
// a prototype-key lookup.
assert("hasOwn own key via cityMetaFor", M.cityMetaFor("nyc") !== null);
assert("hasOwn inherited key rejected via cityMetaFor", M.cityMetaFor("toString") === null);
assert("hasOwn constructor key rejected via cityMetaFor", M.cityMetaFor("constructor") === null);
assert("hasOwn constructor key rejected via stateNameFor", M.stateNameFor("constructor") === null);

// ----- CITY_META / cityMetaFor (locks the moved data literal) -----
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
// rankSpots/matchClass/foldSpot. BarWidget.buildSearchHits still resolves a city
// label (via cityLabelFor) and folds it for the dropdown, so a city-name query
// still yields a city hit even though rankSpots no longer matches the label.
assert("city-name query still resolves a city label for the dropdown",
  Spot.foldSearchText(M.cityLabelFor("nyc")).indexOf(Spot.foldSearchText("new york")) === 0);

// ----- US_STATES (locks the moved data literal) -----
assert("US_STATES contains CA", M.US_STATES.CA === 1);
assert("US_STATES contains NY", M.US_STATES.NY === 1);
assert("US_STATES contains TX", M.US_STATES.TX === 1);
assert("US_STATES contains DC", M.US_STATES.DC === 1);
assert("US_STATES rejects non-US VIC", M.US_STATES.VIC === undefined);
assert("US_STATES rejects Lisbon region 11", M.US_STATES["11"] === undefined);

// ----- US_STATE_NAMES / stateNameFor -----
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
assert("isUsState US state + US country", M.isUsState({ region_code: "NY", country: "US" }) === true);
assert("isUsState colliding foreign region rejected", M.isUsState({ region_code: "NH", country: "NL" }) === false);
assert("isUsState US code with absent country rejected", M.isUsState({ region_code: "NY" }) === false);
assert("isUsState US code with foreign country rejected", M.isUsState({ region_code: "NY", country: "CA" }) === false);
assert("isUsState non-US region code rejected", M.isUsState({ region_code: "VIC", country: "AU" }) === false);
assert("isUsState null spot", M.isUsState(null) === false);
assert("isUsState trims and uppercases", M.isUsState({ region_code: "  ny ", country: " us " }) === true);

// ----- isUsStateCode (module-private country-gated predicate) -----
// isUsStateCode is module-private; the country-gated US-state predicate is
// reached through isUsState (a spot in, boolean out) and
// computeLocationAggregates (already-normalized fields). The constructor-safety
// of the US_STATES lookup is observed through the aggregate: a prototype-key
// state must never be counted.
assert("isUsStateCode constructor-safe via computeLocationAggregates",
  (function () {
    const agg = M.computeLocationAggregates([{ name: "X", region_code: "constructor", country: "US" }], () => 5);
    return JSON.stringify(agg.stateCounts) === "{}" && agg.countryCounts.US === 1;
  })());

// A "new"-style query reaches all four New* states by full name (the raw code
// "NY"/"NJ"/"NM"/"NH" could never match "new"), and a "ny" code query still
// matches the raw code — both folded with the shared search path.
assert("'new' query reaches all four New* states by full name",
  ["NJ", "NM", "NH", "NY"].every((code) =>
    Spot.foldSearchText(M.stateNameFor(code)).indexOf(Spot.foldSearchText("new")) === 0));
assert("'ny' code query still matches the raw NY code",
  Spot.foldSearchText("NY").indexOf(Spot.foldSearchText("ny")) >= 0);

// ----- dual-use export guard -----
// An exported dual-use JS symbol renamed or added without updating every QML
// call site passes qmllint, `omarchy plugin validate .`, and the Node suites,
// yet degrades only at runtime: a QML import qualifier exposes only
// module.exports names, so a call to an unexported symbol resolves to
// undefined. This test closes the class permanently — it parses every .qml
// file the shell loads (repo root + components/) for `CatalogUtils.<symbol>` /
// `SpotUtils.<symbol>` / `JournalIdentity.<symbol>` references and asserts each
// referenced symbol is actually exported by its module. The export sets are
// derived from the required modules (never hard-coded), so the test cannot
// drift from the source of truth.
const repoRoot = path.join(__dirname, "..");
const qmlFiles = fs.readdirSync(repoRoot)
  .filter((name) => name.endsWith(".qml"))
  .map((name) => path.join(repoRoot, name))
  .concat(
    fs.readdirSync(path.join(repoRoot, "components"))
      .filter((name) => name.endsWith(".qml"))
      .map((name) => path.join(repoRoot, "components", name))
  );

// `Qualifier.symbol` reads. CatalogUtils resolves against the catalog module,
// SpotUtils against the spot module, JournalIdentity against the
// journal-identity module — each qualifier checked against its own export set,
// so the modules may legitimately export different names.
// The guard asserts per unique symbol (not per occurrence): the distinct set of
// `Qualifier.symbol` names across every QML file, keyed by qualifier, with the
// first file each name appeared in recorded for the failure message.
const QUALIFIER_REF = /(CatalogUtils|SpotUtils|JournalIdentity)\.([A-Za-z_$][A-Za-z0-9_$]*)/g;
const MODULE_BY_QUALIFIER = { CatalogUtils: M, SpotUtils: Spot, JournalIdentity: JournalIdentity };

// Map of qualifier -> Map(symbol -> first relative file path).
const referencedSymbols = { CatalogUtils: new Map(), SpotUtils: new Map(), JournalIdentity: new Map() };
qmlFiles.forEach((file) => {
  const source = fs.readFileSync(file, "utf8");
  const relative = path.relative(repoRoot, file);
  let match;
  while ((match = QUALIFIER_REF.exec(source)) !== null) {
    const qualifier = match[1];
    const symbol = match[2];
    const bySymbol = referencedSymbols[qualifier];
    if (!bySymbol.has(symbol)) {
      bySymbol.set(symbol, relative);
    }
  }
});

Object.keys(referencedSymbols).forEach((qualifier) => {
  referencedSymbols[qualifier].forEach((file, symbol) => {
    assert(
      file + " references " + qualifier + "." + symbol + " which is not exported",
      Object.prototype.hasOwnProperty.call(MODULE_BY_QUALIFIER[qualifier], symbol)
    );
  });
});

// Floor: a broken scan (no QML files, or a pattern that matches nothing) must
// fail rather than pass vacuously.
assert("export guard scanned QML files and found qualifier references",
  qmlFiles.length > 0 && referencedSymbols.CatalogUtils.size > 0 &&
  referencedSymbols.SpotUtils.size > 0 && referencedSymbols.JournalIdentity.size > 0);


report();
