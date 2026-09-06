// tests/spot_utils_test.js — spot-utils.js tests
const M = require("../spot-utils.js");
const Catalog = require("../catalog-utils.js");
const { assert, report } = require("./_assert.js");

// ----- spotKind -----
assert("spotKind omakase", M.spotKind({courses:"20",price:"$550"}) === "omakase");
assert("spotKind discount", M.spotKind({time:"8pm",discount:"50%"}) === "discount");
assert("spotKind empty", M.spotKind({name:"x"}) === "");
assert("spotKind null", M.spotKind(null) === "");
assert("spotKind empty courses", M.spotKind({courses:"",price:"$10"}) === "");
assert("spotKind zero price ok", M.spotKind({courses:"10",price:"$0"}) === "omakase");
assert("spotKind cuisine omakase has no fallback", M.spotKind({cuisine:"omakase"}) === "");
assert("spotKind cuisine kaiseki has no fallback", M.spotKind({cuisine:"kaiseki"}) === "");

// ----- normalizeName -----
assert("normalizeName trims + lowercases", M.normalizeName("  Omi Omakase  ") === "omi omakase");
assert("normalizeName upper to lower", M.normalizeName("OMI OMAKASE") === "omi omakase");
assert("normalizeName empty string", M.normalizeName("") === "");
assert("normalizeName whitespace only", M.normalizeName("   ") === "");
assert("normalizeName null", M.normalizeName(null) === "");
assert("normalizeName undefined", M.normalizeName(undefined) === "");
assert("normalizeName number", M.normalizeName(123) === "123");

// ----- foldSearchText -----
assert("foldSearchText lowercases", M.foldSearchText("SUSHI") === "sushi");
assert("foldSearchText trims + collapses whitespace", M.foldSearchText("  Sushi   Sato  ") === "sushi sato");
assert("foldSearchText collapses tabs/newlines", M.foldSearchText("a\tb\n c") === "a b c");
assert("foldSearchText folds Saké", M.foldSearchText("Saké") === "sake");
assert("foldSearchText folds Poké King", M.foldSearchText("Poké King") === "poke king");
assert("foldSearchText folds Poké Me", M.foldSearchText("Poké Me") === "poke me");
assert("foldSearchText folds Komé", M.foldSearchText("Komé") === "kome");
assert("foldSearchText folds Côté Sushi", M.foldSearchText("Côté Sushi") === "cote sushi");
assert("foldSearchText folds Kifuné", M.foldSearchText("Kifuné") === "kifune");
assert("foldSearchText folds Kisumé", M.foldSearchText("Kisumé") === "kisume");
assert("foldSearchText folds Uchibā macron", M.foldSearchText("Uchibā") === "uchiba");
assert("foldSearchText folds São Paulo", M.foldSearchText("São Paulo") === "sao paulo");
assert("foldSearchText folds Barfüsser", M.foldSearchText("Barfüsser") === "barfusser");
assert("foldSearchText folds Kaïten", M.foldSearchText("Kaïten") === "kaiten");
assert("foldSearchText folds eszett to ss", M.foldSearchText("Straße") === "strasse");
assert("foldSearchText folds ae ligature", M.foldSearchText("Æon") === "aeon");
assert("foldSearchText folds oe ligature", M.foldSearchText("œuf") === "oeuf");
assert("foldSearchText folds o-slash", M.foldSearchText("Øl") === "ol");
assert("foldSearchText folds uppercase acute", M.foldSearchText("É") === "e");
assert("foldSearchText folds uppercase umlaut", M.foldSearchText("Ö") === "o");
assert("foldSearchText folds uppercase ae", M.foldSearchText("Æ") === "ae");
assert("foldSearchText folds caron s", M.foldSearchText("š") === "s");
assert("foldSearchText passes CJK through", M.foldSearchText("鮨") === "鮨");
assert("foldSearchText null", M.foldSearchText(null) === "");
assert("foldSearchText undefined", M.foldSearchText(undefined) === "");
assert("foldSearchText empty", M.foldSearchText("") === "");
assert("foldSearchText number", M.foldSearchText(123) === "123");

// ----- haversine -----
const nycLat = 40.7128, nycLon = -74.0060;
const laLat = 34.0522, laLon = -118.2437;
const dist = M.haversine(nycLat, nycLon, laLat, laLon);
assert("haversine NYC-LA ~3944km", Math.abs(dist - 3944) < 50);

assert("haversine null returns Infinity", M.haversine(null, 0, 0, 0) === Infinity);
assert("haversine zero distance", M.haversine(0, 0, 0, 0) === 0);

// ----- priceNumber -----
assert("priceNumber basic", M.priceNumber("500") === 500);
assert("priceNumber range", M.priceNumber("68-150") === 68);
assert("priceNumber thousands", M.priceNumber("420000") === 420000);
assert("priceNumber undefined", M.priceNumber(undefined) === Infinity);
assert("priceNumber empty", M.priceNumber("") === Infinity);
assert("priceNumber non-numeric", M.priceNumber("ask chef") === Infinity);
assert("priceNumber leading numeric run", M.priceNumber("1.2.3") === 1.2);
assert("priceNumber leading minus", M.priceNumber("-500") === -500);
assert("priceNumber lone hyphen", M.priceNumber("-") === Infinity);

// ----- priceSortValue -----
assert("priceSortValue numeric price", M.priceSortValue({price:"550"}) === 550);
assert("priceSortValue range price", M.priceSortValue({price:"68-150"}) === 68);
assert("priceSortValue numeric price wins over discount", M.priceSortValue({price:"10",discount:"50%"}) === 10);
assert("priceSortValue discount cheapest", M.priceSortValue({discount:"50%"}) === -1);
assert("priceSortValue discount beats yelp bucket", M.priceSortValue({discount:"50%",yelp_price:"$$$$"}) === -1);
assert("priceSortValue discount with empty price", M.priceSortValue({price:"",discount:"50%"}) === -1);
assert("priceSortValue yelp bucket three", M.priceSortValue({yelp_price:"$$$"}) === 30);
assert("priceSortValue yelp bucket four", M.priceSortValue({yelp_price:"$$$$"}) === 40);
assert("priceSortValue numeric beats yelp bucket", M.priceSortValue({price:"10",yelp_price:"$$$$"}) === 10);
assert("priceSortValue unpriced", M.priceSortValue({name:"x"}) === Infinity);
assert("priceSortValue empty yelp price unpriced", M.priceSortValue({yelp_price:""}) === Infinity);
assert("priceSortValue null", M.priceSortValue(null) === Infinity);
assert("priceSortValue undefined", M.priceSortValue(undefined) === Infinity);

// ----- currencySymbol -----
assert("currencySymbol AUD", M.currencySymbol("AUD") === "A$");
assert("currencySymbol KRW", M.currencySymbol("KRW") === "\u20a9");
assert("currencySymbol AED trailing space", M.currencySymbol("AED") === "AED ");
assert("currencySymbol CHF trailing space", M.currencySymbol("CHF") === "CHF ");
assert("currencySymbol unknown", M.currencySymbol("XYZ") === "");

// ----- formatPrice -----
assert("formatPrice USD", M.formatPrice({price:"500",currency:"USD"}) === "$500");
assert("formatPrice JPY", M.formatPrice({price:"40000",currency:"JPY"}) === "\u00a540000");
assert("formatPrice range", M.formatPrice({price:"68-150",currency:"USD"}) === "$68 \u2013 150");
assert("formatPrice discount fallback", M.formatPrice({discount:"50%"}) === "50%");
assert("formatPrice price over discount", M.formatPrice({price:"10",currency:"USD",discount:"50%"}) === "$10");
assert("formatPrice empty", M.formatPrice({}) === "");
assert("formatPrice null", M.formatPrice(null) === "");

// ----- formatCourses -----
assert("formatCourses omakase", M.formatCourses({courses:"20"}) === "20 courses");
assert("formatCourses discount time", M.formatCourses({time:"8pm"}) === "8pm");
assert("formatCourses empty", M.formatCourses({}) === "");
assert("formatCourses null", M.formatCourses(null) === "");

// ----- formatDate -----
const thisYear = new Date().getFullYear();
assert("formatDate same year short form", M.formatDate(new Date(thisYear, 8, 7).getTime()) === "Sep 7");
assert("formatDate other year long form", M.formatDate(new Date(2000, 0, 15).getTime()) === "Jan 15, 2000");
assert("formatDate null", M.formatDate(null) === "");
assert("formatDate undefined", M.formatDate(undefined) === "");

// ----- formatDistance -----
assert("formatDistance under 10 one decimal", M.formatDistance(3.2) === "3.2 km");
assert("formatDistance sub-km one decimal", M.formatDistance(0.9) === "0.9 km");
assert("formatDistance over 10 rounded", M.formatDistance(12.4) === "12 km");
assert("formatDistance exactly 10", M.formatDistance(10) === "10 km");
assert("formatDistance Infinity", M.formatDistance(Infinity) === "");
assert("formatDistance null", M.formatDistance(null) === "");

// ----- parseJson -----
assert("parseJson valid array", JSON.stringify(M.parseJson('["a","b"]', [])) === '["a","b"]');
assert("parseJson valid object", JSON.stringify(M.parseJson('{"a":1}', {})) === '{"a":1}');
assert("parseJson empty string fallback", JSON.stringify(M.parseJson("", [])) === "[]");
assert("parseJson null fallback", JSON.stringify(M.parseJson(null, [])) === "[]");
assert("parseJson undefined fallback", JSON.stringify(M.parseJson(undefined, {})) === "{}");
assert("parseJson malformed fallback", JSON.stringify(M.parseJson("{", [])) === "[]");
assert("parseJson numeric zero fallback", M.parseJson("0", "fb") === "fb");
assert("parseJson false fallback", M.parseJson("false", "fb") === "fb");
assert("parseJson null literal fallback", M.parseJson("null", "fb") === "fb");

// ----- canBook -----
assert("canBook with reservation", M.canBook({transactions:["restaurant_reservation"]}) === true);
assert("canBook without reservation", M.canBook({transactions:["delivery"]}) === false);
assert("canBook empty transactions", M.canBook({transactions:[]}) === false);
assert("canBook missing transactions", M.canBook({name:"x"}) === false);
assert("canBook null spot", M.canBook(null) === false);
assert("canBook undefined spot", M.canBook(undefined) === false);

// ----- isClosed -----
assert("isClosed true", M.isClosed({is_closed:true}) === true);
assert("isClosed false", M.isClosed({is_closed:false}) === false);
assert("isClosed missing", M.isClosed({name:"x"}) === false);
assert("isClosed null spot", M.isClosed(null) === false);

// ----- spotImageUrl -----
assert("spotImageUrl with https", M.spotImageUrl({image_url:"https://x/y.jpg"}) === "https://x/y.jpg");
assert("spotImageUrl without image", M.spotImageUrl({name:"x"}) === "");
assert("spotImageUrl null spot", M.spotImageUrl(null) === "");
assert("spotImageUrl rejects file scheme", M.spotImageUrl({image_url:"file:///etc/passwd"}) === "");
assert("spotImageUrl rejects qrc scheme", M.spotImageUrl({image_url:"qrc:/icons/evil.png"}) === "");
assert("spotImageUrl rejects http", M.spotImageUrl({image_url:"http://x/y.jpg"}) === "");
assert("spotImageUrl allows png data", M.spotImageUrl({image_url:"data:image/png;base64,AAAA"}) === "data:image/png;base64,AAAA");
assert("spotImageUrl allows jpeg data", M.spotImageUrl({image_url:"data:image/jpeg;base64,AAAA"}) === "data:image/jpeg;base64,AAAA");
assert("spotImageUrl allows webp data", M.spotImageUrl({image_url:"data:image/webp;base64,AAAA"}) === "data:image/webp;base64,AAAA");
assert("spotImageUrl rejects svg data", M.spotImageUrl({image_url:"data:image/svg+xml;base64,PHN2Zz4="}) === "");
assert("spotImageUrl rejects bare data image", M.spotImageUrl({image_url:"data:image/gif;base64,AAAA"}) === "");

// ----- mapsUrl -----
assert("mapsUrl full address", M.mapsUrl({display_address:["123 Main St","New York, NY 10012"]}) === "https://www.google.com/maps?q=123%20Main%20St%2C%20New%20York%2C%20NY%2010012");
assert("mapsUrl lat/lon fallback", M.mapsUrl({lat:40.7, lon:-74.0}) === "https://www.google.com/maps?q=40.7,-74");
assert("mapsUrl missing lon", M.mapsUrl({lat:40.7}) === "");
assert("mapsUrl zero coords", M.mapsUrl({lat:0, lon:0}) === "");
assert("mapsUrl empty spot", M.mapsUrl({}) === "");
assert("mapsUrl null spot", M.mapsUrl(null) === "");
assert("mapsUrl hostile lat rejected", M.mapsUrl({lat:"40.7&label=phish", lon:"-74.0"}) === "");
assert("mapsUrl hostile lon rejected", M.mapsUrl({lat:40.7, lon:"-74.0&foo=bar"}) === "");
assert("mapsUrl non-numeric coords rejected", M.mapsUrl({lat:"abc", lon:"def"}) === "");
assert("mapsUrl numeric string coords", M.mapsUrl({lat:"40.7", lon:"-74.0"}) === "https://www.google.com/maps?q=40.7,-74");
assert("mapsUrl address wins over hostile coords", M.mapsUrl({display_address:["123 Main St"], lat:"40.7&x=1", lon:"-74"}) === "https://www.google.com/maps?q=123%20Main%20St");

// ----- streetAddress -----
assert("streetAddress address present", M.streetAddress({address:"1 Main St", display_address:["ignored"]}) === "1 Main St");
assert("streetAddress display_address array", M.streetAddress({display_address:["123 Main St","New York, NY 10012"]}) === "123 Main St");
assert("streetAddress empty array", M.streetAddress({display_address:[]}) === "");
assert("streetAddress both missing", M.streetAddress({}) === "");
assert("streetAddress null spot", M.streetAddress(null) === "");
assert("streetAddress empty address falls back", M.streetAddress({address:"", display_address:["Fallback St"]}) === "Fallback St");

// ----- formatSpotClipboard -----
const fullSpot = {
  name: "Sushi Sato",
  state: "NY",
  country: "US",
  neighborhood: "SoHo",
  display_address: ["123 Main St", "New York, NY 10012"],
  price: "500",
  currency: "USD",
  courses: "20",
  yelp_price: "$$$$",
  yelp_rating: 4.5,
  yelp_review_count: 120,
  yelp_url: "https://yelp.com/x",
  website: "https://sushi.com",
  phone: "+12125550123",
  lat: 40.7,
  lon: -74.0
};
assert("formatSpotClipboard full spot", M.formatSpotClipboard(fullSpot, "Sushi Sato", "New York City") ===
  "Sushi Sato\n" +
  "New York City · NY · US · SoHo\n" +
  "123 Main St, New York, NY 10012\n" +
  "$500 · 20 courses\n" +
  "Price: $$$$\n" +
  "Yelp: 4.5 (120 reviews)\n" +
  "Yelp: https://yelp.com/x\n" +
  "Maps: https://www.google.com/maps?q=123%20Main%20St%2C%20New%20York%2C%20NY%2010012\n" +
  "Website: https://sushi.com\n" +
  "Phone: +12125550123");

assert("formatSpotClipboard discount spot", M.formatSpotClipboard({time:"8pm", discount:"50%", neighborhood:"SoHo"}, "Happy Sushi", "New York City") ===
  "Happy Sushi\n" +
  "New York City · SoHo\n" +
  "8pm · 50% off");

assert("formatSpotClipboard name only", M.formatSpotClipboard(null, "Solo", "") === "Solo");

// ----- SEP / joinNonEmpty -----
assert("SEP value", M.SEP === " · ");
assert("SEP matches catalog-utils", M.SEP === Catalog.SEP);
assert("SEP_LEAD value", M.SEP_LEAD === "· ");
assert("SEP_LEAD matches catalog-utils", M.SEP_LEAD === Catalog.SEP_LEAD);
assert("joinNonEmpty three parts", M.joinNonEmpty(["a", "b", "c"]) === "a · b · c");
assert("joinNonEmpty drops empties", M.joinNonEmpty(["a", "", "b", null, undefined]) === "a · b");
assert("joinNonEmpty all empty", M.joinNonEmpty(["", null]) === "");
assert("joinNonEmpty empty array", M.joinNonEmpty([]) === "");
assert("joinNonEmpty null input", M.joinNonEmpty(null) === "");

// ----- safeExternalUrl -----
assert("safeExternalUrl https", M.safeExternalUrl("https://x.com") === "https://x.com");
assert("safeExternalUrl https normalizes scheme case", M.safeExternalUrl("HTTPS://x.com") === "https://x.com");
assert("safeExternalUrl tel", M.safeExternalUrl("tel:+12125550123") === "tel:+12125550123");
assert("safeExternalUrl tel punctuation", M.safeExternalUrl("tel:(212) 555-0123") === "tel:(212) 555-0123");
assert("safeExternalUrl tel rejects letters", M.safeExternalUrl("tel:abc") === "");
assert("safeExternalUrl mailto", M.safeExternalUrl("mailto:hello@example.com") === "mailto:hello@example.com");
assert("safeExternalUrl rejects http", M.safeExternalUrl("http://x.com") === "");
assert("safeExternalUrl rejects file", M.safeExternalUrl("file:///etc/passwd") === "");
assert("safeExternalUrl rejects javascript", M.safeExternalUrl("javascript:alert(1)") === "");
assert("safeExternalUrl rejects scheme-less", M.safeExternalUrl("example.com") === "");
assert("safeExternalUrl rejects empty", M.safeExternalUrl("") === "");
assert("safeExternalUrl rejects null", M.safeExternalUrl(null) === "");
assert("safeExternalUrl trims whitespace", M.safeExternalUrl("  https://x.com  ") === "https://x.com");

// ----- stampDerivedFields -----
(function () {
  const spot = {
    name: "Sushi Sato",
    courses: "20",
    price: "550",
    currency: "USD",
    yelp_rating: 4.5,
    yelp_review_count: 120,
    yelp_price: "$$$$",
    is_closed: true,
    transactions: ["restaurant_reservation"],
    image_url: "https://x/y.jpg",
    display_address: ["123 Main St"],
    lat: 40.7,
    lon: -74.0
  };
  const stamped = M.stampDerivedFields(spot, "nyc");
  assert("stampDerivedFields returns the spot", stamped === spot);
  assert("stampDerivedFields _cityKey", spot._cityKey === "nyc");
  assert("stampDerivedFields _spotKind", spot._spotKind === "omakase");
  assert("stampDerivedFields _isClosed", spot._isClosed === true);
  assert("stampDerivedFields _canBook", spot._canBook === true);
  assert("stampDerivedFields _imageUrl", spot._imageUrl === "https://x/y.jpg");
  assert("stampDerivedFields _priceLabel", spot._priceLabel === "$550");
  assert("stampDerivedFields _courses", spot._courses === "20 courses");
  assert("stampDerivedFields _yelpRating", spot._yelpRating === 4.5);
  assert("stampDerivedFields _yelpReviewCount", spot._yelpReviewCount === 120);
  assert("stampDerivedFields _yelpPrice", spot._yelpPrice === "$$$$");
  assert("stampDerivedFields _mapsUrl", spot._mapsUrl === "https://www.google.com/maps?q=123%20Main%20St");
})();

(function () {
  const discount = { time: "8pm", discount: "50%" };
  M.stampDerivedFields(discount, "tokyo");
  assert("stampDerivedFields discount _spotKind", discount._spotKind === "discount");
  assert("stampDerivedFields discount _priceLabel", discount._priceLabel === "50%");
  assert("stampDerivedFields discount _courses", discount._courses === "8pm");
  assert("stampDerivedFields discount _yelpRating zero", discount._yelpRating === 0);
  assert("stampDerivedFields discount _yelpReviewCount zero", discount._yelpReviewCount === 0);
  assert("stampDerivedFields discount _yelpPrice empty", discount._yelpPrice === "");
  assert("stampDerivedFields discount _mapsUrl empty", discount._mapsUrl === "");
})();

(function () {
  // Non-object entries must be skipped, not throw (a corrupt/truncated
  // state.json can carry a null element in a city array).
  assert("stampDerivedFields null skipped", M.stampDerivedFields(null, "nyc") === null);
  assert("stampDerivedFields undefined skipped", M.stampDerivedFields(undefined, "nyc") === undefined);
  assert("stampDerivedFields string skipped", M.stampDerivedFields("not a spot", "nyc") === "not a spot");
  assert("stampDerivedFields number skipped", M.stampDerivedFields(42, "nyc") === 42);
  assert("stampDerivedFields array skipped", M.stampDerivedFields([], "nyc").length === 0);
})();

(function () {
  // A valid spot still stamps identically after the null guard.
  const spot = {
    name: "Sushi Sato",
    courses: "20",
    price: "550",
    currency: "USD",
    yelp_rating: 4.5,
    is_closed: false,
    display_address: ["123 Main St"],
    lat: 40.7,
    lon: -74.0
  };
  M.stampDerivedFields(spot, "nyc");
  assert("stampDerivedFields valid _cityKey", spot._cityKey === "nyc");
  assert("stampDerivedFields valid _spotKind", spot._spotKind === "omakase");
  assert("stampDerivedFields valid _priceLabel", spot._priceLabel === "$550");
  assert("stampDerivedFields valid _courses", spot._courses === "20 courses");
  assert("stampDerivedFields valid _yelpRating", spot._yelpRating === 4.5);
  assert("stampDerivedFields valid _mapsUrl", spot._mapsUrl === "https://www.google.com/maps?q=123%20Main%20St");
})();

// ----- Results -----
report();
