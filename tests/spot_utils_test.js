// tests/spot_utils_test.js — spot-utils.js tests
const M = require("../spot-utils.js");
let passed = 0, failed = 0;

function assert(label, cond) {
  if (cond) { passed++; } else { console.log("FAIL: " + label); failed++; }
}

// ----- spotKind -----
assert("spotKind omakase", M.spotKind({courses:"20",price:"$550"}) === "omakase");
assert("spotKind discount", M.spotKind({time:"8pm",discount:"50%"}) === "discount");
assert("spotKind empty", M.spotKind({name:"x"}) === "");
assert("spotKind null", M.spotKind(null) === "");
assert("spotKind empty courses", M.spotKind({courses:"",price:"$10"}) === "");
assert("spotKind zero price ok", M.spotKind({courses:"10",price:"$0"}) === "omakase");
assert("spotKind cuisine omakase has no fallback", M.spotKind({cuisine:"omakase"}) === "");
assert("spotKind cuisine kaiseki has no fallback", M.spotKind({cuisine:"kaiseki"}) === "");

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

// ----- kmToMiles / formatMiles -----
assert("kmToMiles 1km", Math.abs(M.kmToMiles(1) - 0.621371) < 1e-9);
assert("kmToMiles 0", M.kmToMiles(0) === 0);
assert("kmToMiles Infinity passthrough", M.kmToMiles(Infinity) === Infinity);
assert("kmToMiles null passthrough", M.kmToMiles(null) === null);
assert("formatMiles under 10 one decimal", M.formatMiles(3.3) === "3.3 mi");
assert("formatMiles sub-mile one decimal", M.formatMiles(0.9) === "0.9 mi");
assert("formatMiles over 10 rounded", M.formatMiles(12.4) === "12 mi");
assert("formatMiles exactly 10", M.formatMiles(10) === "10 mi");
assert("formatMiles Infinity", M.formatMiles(Infinity) === "");
assert("formatMiles null", M.formatMiles(null) === "");

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

// ----- Results -----
console.log("tests " + (passed + failed));
console.log("pass " + passed);
console.log("fail " + failed);
if (failed) process.exit(1);
