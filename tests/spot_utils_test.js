// tests/spot_utils_test.js — spot-utils.js tests
const M = require("../spot-utils.js");
const { assert, report } = require("./_assert.js");

// ----- spotKind -----
assert("spotKind omakase", M.spotKind({courses:"20",price:"$550"}) === "omakase");
assert("spotKind discount", M.spotKind({discount_window:"8pm",discount:"50%"}) === "discount");
assert("spotKind empty", M.spotKind({name:"x"}) === "");
assert("spotKind null", M.spotKind(null) === "");
assert("spotKind empty courses", M.spotKind({courses:"",price:"$10"}) === "");
assert("spotKind zero price ok", M.spotKind({courses:"10",price:"$0"}) === "omakase");
assert("spotKind cuisine omakase has no fallback", M.spotKind({cuisine:"omakase"}) === "");
assert("spotKind cuisine kaiseki has no fallback", M.spotKind({cuisine:"kaiseki"}) === "");

// ----- spotKind AYCE -----
// The four courses:"AYCE" spots also carry a price, so AYCE must be tested
// before the omakase branch or they classify as omakase.
assert("spotKind ayce courses AYCE (precedence over omakase)", M.spotKind({courses:"AYCE",price:"95"}) === "ayce");

// ----- spotKind precedence (ayce > discount > omakase) -----
// A spot carrying every signal resolves to exactly one kind, and discount
// outranks omakase when both the set-menu and happy-hour fields are present.
// Discount and courses never co-occur in the current seed, so this pins the
// policy for future data rather than changing any existing classification.
assert("spotKind all signals + AYCE courses -> ayce", M.spotKind({courses:"AYCE",price:"95",discount_window:"8pm",discount:"50%"}) === "ayce");
assert("spotKind all signals without AYCE -> discount", M.spotKind({courses:"20",price:"550",discount_window:"8pm",discount:"50%"}) === "discount");
assert("spotKind courses+price only -> omakase", M.spotKind({courses:"20",price:"550"}) === "omakase");
assert("spotKind discount_window+discount only -> discount", M.spotKind({discount_window:"8pm",discount:"50%"}) === "discount");
assert("spotKind ayce name token ayce", M.spotKind({name:"Hanami AYCE Sushi"}) === "ayce");
assert("spotKind ayce name all you can eat", M.spotKind({name:"Takumi Sushi All You Can Eat"}) === "ayce");
assert("spotKind ayce name all-you-can-eat", M.spotKind({name:"All-You-Can-Eat Sushi"}) === "ayce");
assert("spotKind ayce name substring payce", M.spotKind({name:"Sushi Payce"}) === "ayce");
assert("spotKind ayce website ayce host", M.spotKind({website:"https://sumoayce.com"}) === "ayce");
assert("spotKind ayce website allyoucaneat host", M.spotKind({website:"https://izumiallyoucaneat.com"}) === "ayce");
assert("spotKind ayce website buffet host", M.spotKind({website:"https://takumisushibuffet.com"}) === "ayce");
assert("spotKind ayce tabehoudai romanized", M.spotKind({name:"Tabehoudai Sushi"}) === "ayce");
assert("spotKind ayce tabehoudai kanji", M.spotKind({name:"食べ放題 寿司"}) === "ayce");
assert("spotKind not ayce unlimited sake", M.spotKind({courses:"unlimited sake"}) === "");
assert("spotKind not ayce viking name", M.spotKind({name:"Viking Sushi"}) === "");

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

// Coordinate convention (shared with mapsUrl via hasCoords): a pair is valid
// only when both values are non-empty finite numbers. (0, 0) is a real location
// (Gulf of Guinea), so zero is a valid coordinate — missing/blank/NaN is not.
assert("haversine null returns Infinity", M.haversine(null, 0, 0, 0) === Infinity);
assert("haversine blank string returns Infinity", M.haversine("", 0, 0, 0) === Infinity);
assert("haversine zero distance (0,0 is a valid coordinate)", M.haversine(0, 0, 0, 0) === 0);

// ----- leadingPriceNumber (via priceSortKey) -----
// leadingPriceNumber is internal; its numeric-run extraction is reached through
// priceSortKey, the public sort key that calls it. Each spot carries only a
// `price` field so the numeric path (no discount, no yelp_price_level) is exercised.
assert("leadingPriceNumber basic", M.priceSortKey({price:"500"}) === 500);
assert("leadingPriceNumber range", M.priceSortKey({price:"68-150"}) === 68);
assert("leadingPriceNumber thousands", M.priceSortKey({price:"420000"}) === 420000);
assert("leadingPriceNumber undefined", M.priceSortKey({price:undefined}) === Infinity);
assert("leadingPriceNumber empty", M.priceSortKey({price:""}) === Infinity);
assert("leadingPriceNumber non-numeric", M.priceSortKey({price:"ask chef"}) === Infinity);
assert("leadingPriceNumber leading numeric run", M.priceSortKey({price:"1.2.3"}) === 1.2);
assert("leadingPriceNumber leading minus", M.priceSortKey({price:"-500"}) === -500);
assert("leadingPriceNumber lone hyphen", M.priceSortKey({price:"-"}) === Infinity);

// ----- priceSortKey -----
assert("priceSortKey numeric price", M.priceSortKey({price:"550"}) === 550);
assert("priceSortKey numeric price wins over discount", M.priceSortKey({price:"10",discount:"50%"}) === 10);
assert("priceSortKey discount cheapest", M.priceSortKey({discount:"50%"}) === -1);
assert("priceSortKey discount beats yelp bucket", M.priceSortKey({discount:"50%",yelp_price_level:"$$$$"}) === -1);
assert("priceSortKey discount with empty price", M.priceSortKey({price:"",discount:"50%"}) === -1);
assert("priceSortKey yelp bucket three", M.priceSortKey({yelp_price_level:"$$$"}) === 30);
assert("priceSortKey yelp bucket four", M.priceSortKey({yelp_price_level:"$$$$"}) === 40);
// YELP_PRICE_BUCKET_SCALE is 10: each "$" symbol is one bucket unit, so one
// symbol sorts at 10 and five at 50 (the scale, not the symbol count, is the
// multiplier priceSortKey applies).
assert("priceSortKey yelp price one symbol sorts at 10", M.priceSortKey({yelp_price_level:"$"}) === 10);
assert("priceSortKey yelp price five symbols sort at 50", M.priceSortKey({yelp_price_level:"$$$$$"}) === 50);
assert("priceSortKey numeric beats yelp bucket", M.priceSortKey({price:"10",yelp_price_level:"$$$$"}) === 10);
assert("priceSortKey unpriced", M.priceSortKey({name:"x"}) === Infinity);
assert("priceSortKey empty yelp price unpriced", M.priceSortKey({yelp_price_level:""}) === Infinity);
assert("priceSortKey null", M.priceSortKey(null) === Infinity);
assert("priceSortKey undefined", M.priceSortKey(undefined) === Infinity);

// ----- currency symbol (via priceLabel) -----
// The currency-symbol lookup is inlined in priceLabel; each symbol is asserted
// through the public label (symbol prefix + raw price). An unknown code falls
// back to the bare code, proving the lookup returned "".
assert("currency symbol AUD", M.priceLabel({price:"500",currency:"AUD"}) === "A$500");
assert("currency symbol KRW", M.priceLabel({price:"500",currency:"KRW"}) === "\u20a9500");
assert("currency symbol AED trailing space", M.priceLabel({price:"500",currency:"AED"}) === "AED 500");
assert("currency symbol CHF trailing space", M.priceLabel({price:"500",currency:"CHF"}) === "CHF 500");
assert("currency symbol unknown", M.priceLabel({price:"500",currency:"XYZ"}) === "XYZ500");

// ----- priceLabel -----
assert("priceLabel USD", M.priceLabel({price:"500",currency:"USD"}) === "$500");
assert("priceLabel JPY", M.priceLabel({price:"40000",currency:"JPY"}) === "\u00a540000");
assert("priceLabel range", M.priceLabel({price:"68-150",currency:"USD"}) === "$68 \u2013 150");
assert("priceLabel discount fallback", M.priceLabel({discount:"50%"}) === "50%");
assert("priceLabel price over discount", M.priceLabel({price:"10",currency:"USD",discount:"50%"}) === "$10");
assert("priceLabel empty", M.priceLabel({}) === "");
assert("priceLabel null", M.priceLabel(null) === "");

// ----- CURRENCY_SYMBOLS null-prototype regression -----
// `currency` is stored data, so CURRENCY_SYMBOLS is a null-prototype map. Before
// the fix it was a plain object literal, so a crafted currency value resolved to
// an Object.prototype member: priceLabel({price:"50",currency:"constructor"})
// rendered "function Object() { [native code] }50". The null-prototype map makes
// that lookup miss, so the lookup returns "" and priceLabel falls back to
// the code itself; real codes render byte-identically. The constructor miss is
// asserted through priceLabel (the symbol-level check now has no public route),
// so it merges with the "does not leak prototype" assertion below.
assert("priceLabel currency constructor does not leak prototype", M.priceLabel({ price: "50", currency: "constructor" }) === "constructor50");
assert("priceLabel currency hasOwnProperty does not leak prototype", M.priceLabel({ price: "50", currency: "hasOwnProperty" }) === "hasOwnProperty50");
assert("priceLabel currency USD still renders symbol", M.priceLabel({ price: "50", currency: "USD" }) === "$50");

// ----- formatCoursesOrTime (via formatCoursesSegment) -----
// formatCoursesOrTime is internal; the card renders its output through
// formatCoursesSegment, so the behaviour is asserted through the public
// function. Non-AYCE inputs (courses/discount_window/empty/null) are never suppressed.
assert("formatCoursesOrTime omakase", M.formatCoursesSegment({courses:"20"}) === "20 courses");
assert("formatCoursesOrTime discount_window", M.formatCoursesSegment({discount_window:"8pm"}) === "from 8pm");
assert("formatCoursesOrTime empty", M.formatCoursesSegment({}) === "");
assert("formatCoursesOrTime null", M.formatCoursesSegment(null) === "");

// A bare discount_window is labelled "from" so the spec line ("Discount · 50% ·
// from 6pm") can't be read as the discount ending or applying at that hour. A
// value already expressing a range (dash, en-dash, slash, or "to") is a
// complete window and is left untouched, and an empty value stays "".
assert("formatDiscountTime bare time -> from", M.formatCoursesSegment({discount_window:"6pm"}) === "from 6pm");
assert("formatDiscountTime bare time with minutes -> from", M.formatCoursesSegment({discount_window:"8:30pm"}) === "from 8:30pm");
assert("formatDiscountTime empty -> empty", M.formatCoursesSegment({discount_window:""}) === "");
assert("formatDiscountTime hyphen range untouched", M.formatCoursesSegment({discount_window:"5-7pm"}) === "5-7pm");
assert("formatDiscountTime en-dash range untouched", M.formatCoursesSegment({discount_window:"5\u20137pm"}) === "5\u20137pm");
assert("formatDiscountTime slash range untouched", M.formatCoursesSegment({discount_window:"7pm/10pm"}) === "7pm/10pm");
assert("formatDiscountTime to range untouched", M.formatCoursesSegment({discount_window:"5pm to 7pm"}) === "5pm to 7pm");

// ----- formatCoursesSegment -----
// The card's courses segment drops only when it would restate the "AYCE" kind
// label: an AYCE spot whose courses value is itself the AYCE token. An AYCE
// spot with any other courses value keeps its segment; a non-AYCE spot is
// never suppressed. Calls the helper with only the spot's own fields, as the
// card does.
assert("formatCoursesSegment ayce courses AYCE -> omitted", M.formatCoursesSegment({courses:"AYCE"}) === "");
assert("formatCoursesSegment ayce courses AYCE + price -> omitted", M.formatCoursesSegment({name:"Sumo AYCE", courses:"AYCE", price:"95"}) === "");
assert("formatCoursesSegment ayce courses range -> kept", M.formatCoursesSegment({name:"Sumo AYCE", courses:"18-20"}) === "18-20 courses");
assert("formatCoursesSegment ayce no courses -> empty", M.formatCoursesSegment({name:"Sumo AYCE"}) === "");

// ----- formatDate -----
const thisYear = new Date().getFullYear();
assert("formatDate same year short form", M.formatDate(new Date(thisYear, 8, 7).getTime()) === "Sep 7");
assert("formatDate other year long form", M.formatDate(new Date(2000, 0, 15).getTime()) === "Jan 15, 2000");
// The current year is read fresh per call, so a prior-year date — including the
// immediately preceding year — always carries its ", <year>" suffix.
assert("formatDate prior year gets the year suffix", M.formatDate(new Date(thisYear - 1, 0, 15).getTime()) === "Jan 15, " + (thisYear - 1));
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
const arrayFallback = [];
const objectFallback = {};
const parsedArray = M.parseJson('["a","b"]', arrayFallback);
assert("parseJson valid array", Array.isArray(parsedArray) && parsedArray.length === 2 && parsedArray[0] === "a" && parsedArray[1] === "b");
const parsedObject = M.parseJson('{"a":1}', objectFallback);
assert("parseJson valid object", parsedObject !== null && typeof parsedObject === "object" && parsedObject.a === 1);
assert("parseJson empty string fallback", M.parseJson("", arrayFallback) === arrayFallback);
assert("parseJson null fallback", M.parseJson(null, arrayFallback) === arrayFallback);
assert("parseJson undefined fallback", M.parseJson(undefined, objectFallback) === objectFallback);
assert("parseJson malformed fallback", M.parseJson("{", arrayFallback) === arrayFallback);
assert("parseJson numeric zero fallback", M.parseJson("0", "fb") === "fb");
assert("parseJson false fallback", M.parseJson("false", "fb") === "fb");
assert("parseJson null literal fallback", M.parseJson("null", "fb") === "fb");

// ----- parseJsonArray -----
// The shared state-file array guard (journal.json / user_spots.json /
// wishlist.json): parse, then keep only an array. A wrong-shaped top level
// (object, string) degrades to [] so a later .push/.splice/.length never
// throws. The follow-up QML switch consumes this exact contract.
const parsedJsonArray = M.parseJsonArray('["a","b"]');
assert("parseJsonArray valid array", Array.isArray(parsedJsonArray) && parsedJsonArray.length === 2 && parsedJsonArray[0] === "a" && parsedJsonArray[1] === "b");
const objectGuard = M.parseJsonArray('{"a":1}');
assert("parseJsonArray top-level object -> []", Array.isArray(objectGuard) && objectGuard.length === 0);
const stringGuard = M.parseJsonArray('"hello"');
assert("parseJsonArray JSON string -> []", Array.isArray(stringGuard) && stringGuard.length === 0);
assert("parseJsonArray empty input -> []", M.parseJsonArray("").length === 0);
assert("parseJsonArray malformed -> []", M.parseJsonArray("{").length === 0);

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

// ----- spotImageUrl (via applyDerivedFields._imageUrl) -----
// spotImageUrl is module-private; the widget reads the stamped `_imageUrl`, so
// the allow/reject behaviour is asserted through applyDerivedFields. A missing
// image_url and a null spot share the same `!spot || !spot.image_url` guard.
assert("spotImageUrl with https", M.applyDerivedFields({image_url:"https://x/y.jpg"})._imageUrl === "https://x/y.jpg");
assert("spotImageUrl without image", M.applyDerivedFields({name:"x"})._imageUrl === "");
assert("spotImageUrl rejects file scheme", M.applyDerivedFields({image_url:"file:///etc/passwd"})._imageUrl === "");
assert("spotImageUrl rejects qrc scheme", M.applyDerivedFields({image_url:"qrc:/icons/evil.png"})._imageUrl === "");
assert("spotImageUrl rejects http", M.applyDerivedFields({image_url:"http://x/y.jpg"})._imageUrl === "");
assert("spotImageUrl allows png data", M.applyDerivedFields({image_url:"data:image/png;base64,AAAA"})._imageUrl === "data:image/png;base64,AAAA");
assert("spotImageUrl allows jpeg data", M.applyDerivedFields({image_url:"data:image/jpeg;base64,AAAA"})._imageUrl === "data:image/jpeg;base64,AAAA");
assert("spotImageUrl allows webp data", M.applyDerivedFields({image_url:"data:image/webp;base64,AAAA"})._imageUrl === "data:image/webp;base64,AAAA");
assert("spotImageUrl rejects svg data", M.applyDerivedFields({image_url:"data:image/svg+xml;base64,PHN2Zz4="})._imageUrl === "");
assert("spotImageUrl rejects bare data image", M.applyDerivedFields({image_url:"data:image/gif;base64,AAAA"})._imageUrl === "");

// ----- mapsUrl -----
assert("mapsUrl full address", M.mapsUrl({display_address:["123 Main St","New York, NY 10012"]}) === "https://www.google.com/maps?q=123%20Main%20St%2C%20New%20York%2C%20NY%2010012");
assert("mapsUrl lat/lon fallback", M.mapsUrl({lat:40.7, lon:-74.0}) === "https://www.google.com/maps?q=40.7,-74");
assert("mapsUrl missing lon", M.mapsUrl({lat:40.7}) === "");
// Same hasCoords convention as haversine: (0, 0) is a valid coordinate, so it
// maps rather than degrading to the missing-coordinate "".
assert("mapsUrl zero coords are a valid location (Gulf of Guinea)", M.mapsUrl({lat:0, lon:0}) === "https://www.google.com/maps?q=0,0");
assert("mapsUrl blank string coords treated as missing", M.mapsUrl({lat:"", lon:"-74.0"}) === "");
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

// ----- makeSpot (shared fixture factory) -----
// One spot fixture feeds both buildSpotClipboardText and applyDerivedFields, so a
// field added to one cannot silently drift from the other.
function makeSpot(overrides) {
  return Object.assign({
    name: "Sushi Sato",
    courses: "20",
    price: "500",
    currency: "USD",
    yelp_price_level: "$$$$",
    yelp_rating: 4.5,
    yelp_review_count: 120,
    display_address: ["123 Main St"],
    lat: 40.7,
    lon: -74.0
  }, overrides);
}

// ----- buildSpotClipboardText -----
const fullSpot = makeSpot({
  region_code: "NY",
  country: "US",
  neighborhood: "SoHo",
  display_address: ["123 Main St", "New York, NY 10012"],
  yelp_url: "https://yelp.com/x",
  website: "https://sushi.com",
  phone: "+12125550123"
});
const fullSpotClipboard =
  "Sushi Sato\n" +
  "New York City · NY · US · SoHo\n" +
  "123 Main St, New York, NY 10012\n" +
  "$500 · 20 courses\n" +
  "Price: $$$$\n" +
  "Yelp: 4.5 (120 reviews)\n" +
  "Yelp: https://yelp.com/x\n" +
  "Maps: https://www.google.com/maps?q=123%20Main%20St%2C%20New%20York%2C%20NY%2010012\n" +
  "Website: https://sushi.com\n" +
  "Phone: +12125550123";
const discountSpot = { discount_window: "8pm", discount: "50%", neighborhood: "SoHo" };
const discountSpotClipboard =
  "Happy Sushi\n" +
  "New York City · SoHo\n" +
  "from 8pm · 50% off";
const ayceSpot = { name: "Hanami AYCE Sushi" };
const ayceSpotClipboard =
  "Hanami AYCE Sushi\n" +
  "Austin\n" +
  "AYCE";

assert("buildSpotClipboardText full spot", M.buildSpotClipboardText(fullSpot, "Sushi Sato", "New York City") === fullSpotClipboard);
assert("buildSpotClipboardText discount spot", M.buildSpotClipboardText(discountSpot, "Happy Sushi", "New York City") === discountSpotClipboard);
// clipboardSpecLine's AYCE branch: a name-signalled AYCE spot has no price/courses and
// must still yield a line ("AYCE"), not an empty one.
assert("buildSpotClipboardText ayce spot", M.buildSpotClipboardText(ayceSpot, "Hanami AYCE Sushi", "Austin") === ayceSpotClipboard);
assert("buildSpotClipboardText name only", M.buildSpotClipboardText(null, "Solo", "") === "Solo");

// ----- clipboardYelpLines / clipboardContactLines (module-private; reached via
// buildSpotClipboardText) -----
// The two line-group helpers are no longer exported; their behaviour is
// asserted through buildSpotClipboardText, which appends the Yelp group then
// the contact group after the name/address/spec lines.
assert("buildSpotClipboardText yelp block (price/rating/reviews/url)",
  M.buildSpotClipboardText({ yelp_price_level: "$$$$", yelp_rating: 4.5, yelp_review_count: 120, yelp_url: "https://yelp.com/x" }, "X", "") ===
  "X\nPrice: $$$$\nYelp: 4.5 (120 reviews)\nYelp: https://yelp.com/x");
assert("buildSpotClipboardText yelp rating without review count",
  M.buildSpotClipboardText({ yelp_rating: 4.5 }, "X", "") === "X\nYelp: 4.5");
assert("buildSpotClipboardText no yelp/contact lines",
  M.buildSpotClipboardText({}, "X", "") === "X");
assert("buildSpotClipboardText contact block (maps/website/phone)",
  M.buildSpotClipboardText({ display_address: ["123 Main St"], website: "https://sushi.com", phone: "+12125550123" }, "X", "") ===
  "X\n123 Main St\nMaps: https://www.google.com/maps?q=123%20Main%20St\nWebsite: https://sushi.com\nPhone: +12125550123");
assert("buildSpotClipboardText stamped _mapsUrl preferred over recompute",
  M.buildSpotClipboardText({ _mapsUrl: "https://maps.example/x", display_address: ["123 Real St"] }, "X", "") ===
  "X\n123 Real St\nMaps: https://maps.example/x");

// ----- joinTruthy -----
assert("joinTruthy three parts", M.joinTruthy(["a", "b", "c"]) === "a · b · c");
assert("joinTruthy drops empties", M.joinTruthy(["a", "", "b", null, undefined]) === "a · b");
assert("joinTruthy all empty", M.joinTruthy(["", null]) === "");
assert("joinTruthy empty array", M.joinTruthy([]) === "");
assert("joinTruthy null input", M.joinTruthy(null) === "");

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

// ----- applyDerivedFields -----
(function () {
  const spot = makeSpot({
    price: "550",
    is_closed: true,
    transactions: ["restaurant_reservation"],
    image_url: "https://x/y.jpg"
  });
  const stamped = M.applyDerivedFields(spot, "nyc");
  assert("applyDerivedFields returns the spot", stamped === spot);
  assert("applyDerivedFields _cityKey", spot._cityKey === "nyc");
  assert("applyDerivedFields _spotKind", spot._spotKind === "omakase");
  assert("applyDerivedFields _isClosed", spot._isClosed === true);
  assert("applyDerivedFields _canBook", spot._canBook === true);
  assert("applyDerivedFields _imageUrl", spot._imageUrl === "https://x/y.jpg");
  assert("applyDerivedFields _priceLabel", spot._priceLabel === "$550");
  assert("applyDerivedFields _coursesSegment", spot._coursesSegment === "20 courses");
  assert("applyDerivedFields _yelpRating", spot._yelpRating === 4.5);
  assert("applyDerivedFields _yelpReviewCount", spot._yelpReviewCount === 120);
  assert("applyDerivedFields _yelpPrice", spot._yelpPrice === "$$$$");
  assert("applyDerivedFields _mapsUrl", spot._mapsUrl === "https://www.google.com/maps?q=123%20Main%20St");
})();

(function () {
  const discount = { discount_window: "8pm", discount: "50%" };
  M.applyDerivedFields(discount, "tokyo");
  assert("applyDerivedFields discount _spotKind", discount._spotKind === "discount");
  assert("applyDerivedFields discount _priceLabel", discount._priceLabel === "50%");
  assert("applyDerivedFields discount _coursesSegment", discount._coursesSegment === "from 8pm");
  assert("applyDerivedFields discount _yelpRating zero", discount._yelpRating === 0);
  assert("applyDerivedFields discount _yelpReviewCount zero", discount._yelpReviewCount === 0);
  assert("applyDerivedFields discount _yelpPrice empty", discount._yelpPrice === "");
  assert("applyDerivedFields discount _mapsUrl empty", discount._mapsUrl === "");
})();

(function () {
  const ayce = { name: "Hanami AYCE Sushi" };
  M.applyDerivedFields(ayce, "austin");
  assert("applyDerivedFields ayce _spotKind", ayce._spotKind === "ayce");
  assert("applyDerivedFields ayce _priceLabel empty", ayce._priceLabel === "");
  assert("applyDerivedFields ayce _coursesSegment empty", ayce._coursesSegment === "");
})();

(function () {
  // The courses segment is stamped through formatCoursesSegment, so a
  // courses:"AYCE" spot loses the restated segment end-to-end.
  const restated = { name: "HATSU OMAKASE", courses: "AYCE", price: "95", currency: "USD" };
  M.applyDerivedFields(restated, "nyc");
  assert("applyDerivedFields courses AYCE _spotKind ayce", restated._spotKind === "ayce");
  assert("applyDerivedFields courses AYCE _coursesSegment omitted", restated._coursesSegment === "");
  const distinct = { name: "Sumo AYCE", courses: "18-20", price: "95" };
  M.applyDerivedFields(distinct, "nyc");
  assert("applyDerivedFields ayce distinct courses _coursesSegment kept", distinct._coursesSegment === "18-20 courses");
})();

(function () {
  // Non-object entries must be skipped, not throw (a corrupt/truncated
  // state.json can carry a null element in a city array).
  assert("applyDerivedFields null skipped", M.applyDerivedFields(null, "nyc") === null);
  assert("applyDerivedFields undefined skipped", M.applyDerivedFields(undefined, "nyc") === undefined);
  assert("applyDerivedFields string skipped", M.applyDerivedFields("not a spot", "nyc") === "not a spot");
  assert("applyDerivedFields number skipped", M.applyDerivedFields(42, "nyc") === 42);
  const arrayEntry = [{ name: "x" }];
  assert("applyDerivedFields array skipped", M.applyDerivedFields(arrayEntry, "nyc") === arrayEntry && arrayEntry[0]._cityKey === undefined);
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
  M.applyDerivedFields(spot, "nyc");
  assert("applyDerivedFields valid _cityKey", spot._cityKey === "nyc");
  assert("applyDerivedFields valid _spotKind", spot._spotKind === "omakase");
  assert("applyDerivedFields valid _priceLabel", spot._priceLabel === "$550");
  assert("applyDerivedFields valid _coursesSegment", spot._coursesSegment === "20 courses");
  assert("applyDerivedFields valid _yelpRating", spot._yelpRating === 4.5);
  assert("applyDerivedFields valid _mapsUrl", spot._mapsUrl === "https://www.google.com/maps?q=123%20Main%20St");
})();

// ----- Fix A: wrong-typed fields degrade instead of throwing -----
// A user_spots.json / hand-edited state.json entry can carry a JSON number for
// a string field (price: 123) or a string for an array field
// (transactions: "delivery"). The formatters must not throw — a throw escapes
// the chunked catalog walk and leaves the whole panel empty on every restart.
// Each wrong-typed value degrades to the same output a missing field yields.
assert("priceLabel numeric price", M.priceLabel({ price: 550, currency: "USD" }) === "$550");
assert("priceLabel numeric discount", M.priceLabel({ discount: 50 }) === "50");
// Non-scalar price is dropped by coerceSpotField, so priceLabel now gates it to
// the missing-price "" instead of rendering "[object Object]" — the two read
// paths agree. (Changed from "$550": String([550]) used to render "550".)
assert("priceLabel array price degrades to missing (non-scalar dropped)", M.priceLabel({ price: [550], currency: "USD" }) === "");
assert("priceLabel object price degrades to missing (non-scalar dropped)", M.priceLabel({ price: { v: 550 }, currency: "USD" }) === "");
assert("canBook string transactions", M.canBook({ transactions: "restaurant_reservation" }) === false);
assert("canBook numeric transactions", M.canBook({ transactions: 123 }) === false);
assert("streetAddress numeric address", M.streetAddress({ address: 123 }) === "123");
assert("streetAddress string display_address element", M.streetAddress({ display_address: [123, "New York"] }) === "123");
assert("formatCoursesOrTime numeric courses", M.formatCoursesSegment({ courses: 20 }) === "20 courses");
assert("formatCoursesOrTime numeric discount_window", M.formatCoursesSegment({ discount_window: 8 }) === "from 8");
assert("formatDate non-date string", M.formatDate("not-a-date") === "");

// End-to-end: a numeric name + numeric price + string transactions must stamp
// without throwing (applyDerivedFields runs on every spot during the walk).
(function () {
  const tampered = { name: 123, price: 550, currency: "USD", transactions: "restaurant_reservation" };
  const stamped = M.applyDerivedFields(tampered, "nyc");
  assert("wrong-typed spot stamps without throwing", stamped === tampered);
  assert("numeric price stamps as string price label", tampered._priceLabel === "$550");
  assert("string transactions stamp canBook false", tampered._canBook === false);
  // A string review count and numeric Yelp price both coerce to numbers on the
  // spot during stamping.
  const coerced = { yelp_review_count: "120", yelp_price_level: 5 };
  M.applyDerivedFields(coerced, "nyc");
  assert("numeric yelp_review_count and yelp_price_level coerce to numbers", coerced._yelpReviewCount === 120 && coerced._yelpPrice === "5");
})();

// ----- coerceSpotField (moved from Service.qml, now unit-tested) -----
// The riskiest coercion decision: courses/discount/price stay STRINGS. Numeric
// treatment would drop every non-numeric value ("AYCE", "18-20", "30/50%",
// "15%"), and the real data holds all courses and discounts as strings with
// zero numerics. These assertions lock that decision so a future change that
// treats them as numbers fails loudly.
assert("coerceSpotField courses AYCE stays string", M.coerceSpotField("courses", "AYCE") === "AYCE");
assert("coerceSpotField courses range stays string", M.coerceSpotField("courses", "18-20") === "18-20");
assert("coerceSpotField discount slash-range stays string", M.coerceSpotField("discount", "30/50%") === "30/50%");
assert("coerceSpotField discount percent stays string", M.coerceSpotField("discount", "15%") === "15%");
assert("coerceSpotField price range stays string", M.coerceSpotField("price", "13800-22000") === "13800-22000");
assert("coerceSpotField discount_window range stays string", M.coerceSpotField("discount_window", "7pm/10pm") === "7pm/10pm");
assert("coerceSpotField yelp_price_level symbol stays string", M.coerceSpotField("yelp_price_level", "\uFFE5\uFFE5") === "\uFFE5\uFFE5");
// Numeric and boolean fields keep their runtime type.
assert("coerceSpotField lat number survives", M.coerceSpotField("lat", 40.7128) === 40.7128);
assert("coerceSpotField lon number survives", M.coerceSpotField("lon", -74.006) === -74.006);
assert("coerceSpotField yelp_rating number survives", M.coerceSpotField("yelp_rating", 4.5) === 4.5);
assert("coerceSpotField yelp_review_count number survives", M.coerceSpotField("yelp_review_count", 120) === 120);
assert("coerceSpotField is_closed true survives", M.coerceSpotField("is_closed", true) === true);
assert("coerceSpotField is_closed false survives", M.coerceSpotField("is_closed", false) === false);
// A wrong-typed scalar for a string field coerces to its string form.
assert("coerceSpotField numeric string field coerces", M.coerceSpotField("courses", 20) === "20");
assert("coerceSpotField boolean string field coerces", M.coerceSpotField("name", true) === "true");
// Un-coercible values are dropped (undefined) — sanitizeSpot then omits the field.
assert("coerceSpotField object string field dropped", M.coerceSpotField("price", { value: 550 }) === undefined);
assert("coerceSpotField array string field dropped", M.coerceSpotField("courses", ["AYCE"]) === undefined);
assert("coerceSpotField non-finite number dropped", M.coerceSpotField("lat", "not-a-number") === undefined);
assert("coerceSpotField string is_closed dropped", M.coerceSpotField("is_closed", "true") === undefined);
assert("coerceSpotField transactions non-array dropped", M.coerceSpotField("transactions", "restaurant_reservation") === undefined);

// ----- Results -----
report();
