// spot-utils.js — Omakase data utilities
// Dual-use: Node.js (tests) and QML (import "spot-utils.js" as SpotUtils)

// Shared separator between list segments ("City · State · Country"). `var`
// (not `const`) so QML's import qualifier exposes it (const/let bindings are
// not visible as Qualifier.NAME).
var SEP = " · ";
// The folded/inline form of SEP ("· ") baked into a segment's leading text so
// it never renders alone. Single owner alongside SEP — catalog-utils.js reads
// it lazily via SpotUtils.SEP_LEAD.
var SEP_LEAD = "· ";
// The " km" suffix shared by distance/radius formatters (formatDistance here,
// radiusLabel in catalog-utils.js). Single owner so the two can never drift.
var KM_SUFFIX = " km";

// Join an array's truthy entries with the shared separator, dropping empty
// strings/null/undefined so a missing segment never leaves a dangling "·".
function joinTruthy(parts) {
  return (parts || []).filter(Boolean).join(SEP);
}

// Coerce a value to its string form: null/undefined → "", everything else
// through String(). The shared null-safe stringify guard that used to be
// written inline as `String(x == null ? "" : x)` across the formatters and the
// journal's saved-entry normalizer. A non-string, non-null value (a number,
// boolean, or object) stringifies exactly as String(value) would — only
// null/undefined collapse to "".
function asString(value) {
  return String(value == null ? "" : value);
}

// True when a value is a finite number: it coerces to a number that is neither
// NaN nor ±Infinity. This is the predicate form of the
// `Number.isFinite(Number(x))` idiom shared by the coordinate gate, the
// distance formatter, and the sort comparators — distinct from finiteOrZero
// (catalog-utils' coerced-number helper), which returns a value, not a boolean.
function isFiniteNumber(value) {
  return Number.isFinite(Number(value));
}

// ---- AYCE (all-you-can-eat) detection ----
// AYCE is signalled by any of: `courses` == "AYCE", a name carrying "ayce" /
// "all you can eat", or a website host carrying "ayce" / "allyoucaneat" /
// "buffet". "tabehoudai" / "食べ放題" (Japanese for AYCE) are matched in any
// field for future data. "viking" / "unlimited" are deliberately NOT tokens —
// "unlimited sake" is a pairing add-on, not AYCE. `buffet` in a website host is
// an AYCE signal by default, overridden only by human verification of the
// individual restaurant — do not drop it as too weak without that verification.

// Normalize an AYCE haystack: lowercase, then strip ASCII punctuation and
// whitespace so "all you can eat", "all-you-can-eat", and "allyoucaneat"
// collapse to the same token. The keep-set is a-z, 0-9, and every non-ASCII
// character from U+00C0 up — accented Latin, Greek/Cyrillic, and CJK
// ("食べ放題") all pass through, so the AYCE kanji token survives. (The
// U+0080–U+00BF Latin-1 punctuation band and ASCII punctuation are stripped.)
// Unlike Service.qml's cityAliasToken (which strips all non-ASCII), the two must
// not be merged.
function normalizeAyceText(value) {
  return asString(value).toLowerCase().replace(/[^a-z0-9\u00c0-\uffff]/g, "");
}

// The lowercased hostname of a website URL, with scheme/path/query/fragment/
// port stripped, so the check matches "sumoayce.com" rather than a path token.
function websiteHostname(url) {
  if (!url) return "";
  var value = String(url).trim().toLowerCase().replace(/^[a-z][a-z0-9+.\-]*:\/\//, "");
  var end = value.search(/[\/?#]/);
  if (end >= 0) value = value.slice(0, end);
  return value.replace(/:\d+$/, "");
}

// True when any token appears as a substring of the normalized haystack — a raw
// indexOf >= 0 scan, NOT a word-boundary/token match, so "ayce" matches inside
// "payce" and a host token matches inside a longer host.
function containsAnySubstring(haystack, tokens) {
  return tokens.some(function (token) { return haystack.indexOf(token) >= 0; });
}

// AYCE tokens per field (the census-built rule). "tabehoudai"/"食べ放題" appear
// in every field for future data; "buffet" only in the website host.
const AYCE_COURSES_TOKENS = ["ayce", "tabehoudai", "食べ放題"];
const AYCE_NAME_TOKENS = ["ayce", "allyoucaneat", "tabehoudai", "食べ放題"];
const AYCE_HOST_TOKENS = ["ayce", "allyoucaneat", "buffet", "tabehoudai", "食べ放題"];

// True when a spot's `courses` value carries an AYCE token — the shared first
// branch of the AYCE rule. isAyceSpot (detection) and formatCoursesSegment
// (suppression) both test it, so suppression can never drift from detection.
function hasAyceCourses(spot) {
  return containsAnySubstring(normalizeAyceText(spot ? spot.courses : null), AYCE_COURSES_TOKENS);
}

// Whether a spot is AYCE. Pure — reads only spot.* (no I/O).
function isAyceSpot(spot) {
  if (!spot) return false;
  if (hasAyceCourses(spot)) return true;
  if (containsAnySubstring(normalizeAyceText(spot.name), AYCE_NAME_TOKENS)) return true;
  return containsAnySubstring(normalizeAyceText(websiteHostname(spot.website)), AYCE_HOST_TOKENS);
}

// Return the spot's kind: "ayce" (all-you-can-eat) when the AYCE rule matches,
// else "discount" when discount_window+discount are present, else "omakase" when
// courses+price are present, else "". AYCE is tested first because the four
// courses:"AYCE" spots also carry a price and would otherwise classify as
// omakase. Discount outranks omakase because a happy-hour window is the
// actionable, time-bound deal when a spot carries both signals; discount and
// courses never co-occur in the current seed, so the order only pins policy for
// future data. The result is always one of the values the UI's type filter
// (all|ayce|discount|omakase) can match.
function spotKind(spot) {
  if (!spot) return "";
  if (isAyceSpot(spot)) return "ayce";
  if (spot.discount_window && spot.discount) return "discount";
  if (spot.courses && spot.price) return "omakase";
  return "";
}

// Normalize a spot name for index keys and journal identity: trim + lowercase
// so lookup is case-insensitive (a journal name "Omi Omakase" resolves to the
// catalog "OMI OMAKASE"). Shared by BarWidget's spot index (producer + consumer)
// and Service's journal matching so the key format can never drift apart.
function normalizeName(name) {
  return asString(name).trim().toLowerCase();
}

// Accent → ASCII folding map for search. Keys are the accented Latin letters
// (and ligatures) that occur in seed data; values are their ASCII equivalents.
// Covers Latin-1 + Latin Extended-A plus the Czech/Slovak caron letters, the
// German sharp s (ß/ẞ), and the æ/œ ligatures. Anything not in this map passes
// through unchanged — CJK spot names stay as-is (no transliteration). An
// explicit map is used instead of String.prototype.normalize, which is not
// reliably available in Qt's QJSEngine.
const FOLD_MAP = {
  "á":"a","à":"a","â":"a","ä":"a","ã":"a","å":"a","ā":"a",
  "Á":"a","À":"a","Â":"a","Ä":"a","Ã":"a","Å":"a","Ā":"a",
  "ç":"c","Ç":"c",
  "é":"e","è":"e","ê":"e","ë":"e","ē":"e","ě":"e",
  "É":"e","È":"e","Ê":"e","Ë":"e","Ē":"e","Ě":"e",
  "í":"i","ì":"i","î":"i","ï":"i","ī":"i",
  "Í":"i","Ì":"i","Î":"i","Ï":"i","Ī":"i",
  "ñ":"n","Ñ":"n",
  "ó":"o","ò":"o","ô":"o","ö":"o","õ":"o","ø":"o","ō":"o",
  "Ó":"o","Ò":"o","Ô":"o","Ö":"o","Õ":"o","Ø":"o","Ō":"o",
  "ř":"r","Ř":"r",
  "š":"s","Š":"s",
  "ú":"u","ù":"u","û":"u","ü":"u","ū":"u",
  "Ú":"u","Ù":"u","Û":"u","Ü":"u","Ū":"u",
  "ý":"y","ÿ":"y","Ý":"y","Ÿ":"y",
  "ß":"ss","ẞ":"ss",
  "æ":"ae","Æ":"ae",
  "œ":"oe","Œ":"oe"
};

// Fold text for search matching: lowercases, folds accented Latin characters to
// ASCII (via FOLD_MAP), collapses whitespace runs to a single space, and trims.
// The result is the canonical form both the precomputed spot index and the query
// pass through, so "sake" matches "Saké" and "sao paulo" matches "São Paulo".
// Non-ASCII characters outside FOLD_MAP (CJK) pass through unchanged.
function foldSearchText(text) {
  var value = asString(text);
  // Fold each UTF-16 code unit (charAt and split("") both index code units, so
  // astral characters behave identically either way), then collapse whitespace.
  var folded = value.split("").map(function (character) {
    var replacement = FOLD_MAP[character];
    return replacement !== undefined ? replacement : character;
  }).join("");
  return folded.toLowerCase().replace(/\s+/g, " ").trim();
}

// True when a lat/lon pair is a usable coordinate: both values are non-empty
// and coerce to finite numbers. (0, 0) is a real location (Gulf of Guinea), so
// "finite = valid" is the single convention haversine and mapsUrl share — a
// missing/blank value ("" / null / undefined) is not a coordinate, but zero is.
function hasCoords(lat, lon) {
  return (lat !== null && lat !== undefined && lat !== "" &&
          lon !== null && lon !== undefined && lon !== "" &&
          isFiniteNumber(lat) && isFiniteNumber(lon));
}

// Haversine distance in kilometres between two lat/lon points.
function haversine(lat1, lon1, lat2, lon2) {
  if (!hasCoords(lat1, lon1) || !hasCoords(lat2, lon2)) return Infinity;
  const earthRadiusKm = 6371;
  const deltaLatRad = (lat2 - lat1) * Math.PI / 180;
  const deltaLonRad = (lon2 - lon1) * Math.PI / 180;
  // `squaredHalfChord` is the haversine formula's `a`: the squared length of
  // half the great-circle chord between the two points (unit sphere).
  const squaredHalfChord = Math.sin(deltaLatRad / 2) * Math.sin(deltaLatRad / 2) +
          Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
          Math.sin(deltaLonRad / 2) * Math.sin(deltaLonRad / 2);
  const angularDistance = 2 * Math.atan2(Math.sqrt(squaredHalfChord), Math.sqrt(1 - squaredHalfChord));
  return earthRadiusKm * angularDistance;
}

// Short month names, declared at module scope so formatDate() does not rebuild
// the array per call.
const SHORT_MONTHS = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];

// Short date for compact list rows: "Sep 7" in the current year,
// "Sep 7, 2025" otherwise. The current year is read fresh per call (no cache),
// so a long-lived process that crosses a year boundary always suffixes a
// prior-year entry rather than holding a stale year forever.
function formatDate(ms) {
  if (!ms) return "";
  const date = new Date(Number(ms));
  // A non-date value (a tampered journal timestamp) yields an Invalid Date,
  // whose getMonth()/getFullYear() return NaN and would render "undefined NaN".
  // Return "" — the same as a missing timestamp.
  if (Number.isNaN(date.getTime())) return "";
  let formatted = SHORT_MONTHS[date.getMonth()] + " " + date.getDate();
  const year = date.getFullYear();
  if (year !== new Date().getFullYear()) formatted += ", " + year;
  return formatted;
}

// Extract the leading numeric run from a price string for sorting.
// e.g. "$550" → 550, "€240-360" → 240, "95-175" → 95, "1.2.3" → 1.2.
// Returns Infinity when no numeric run is present (sorts to end).
function leadingPriceNumber(rawPrice) {
  if (rawPrice == null || rawPrice === "") return Infinity;
  const match = String(rawPrice).match(/-?\d+(?:\.\d+)?/);
  if (!match) return Infinity;
  const value = parseFloat(match[0]);
  return Number.isNaN(value) ? Infinity : value;
}

// Units per "$" in a Yelp price level ("$$$" -> 30). Used as the price sort
// bucket when the curated price string has no numeric run and there is no
// discount, so "$$", "$$$", "$$$$" sort as 20/30/40.
const YELP_PRICE_BUCKET_SCALE = 10;

// Sort key for the price sort. A discount spot with no numeric price sorts
// cheapest (-1); a spot with neither a price nor a Yelp price level sorts last
// (Infinity, unpriced); otherwise the numeric price, falling back to the Yelp
// price bucket ("$$$" -> 30) when the curated price string has no numeric run.
function priceSortKey(spot) {
  if (!spot) return Infinity;
  const numeric = leadingPriceNumber(spot.price);
  if (Number.isFinite(numeric)) return numeric;
  if (spot.discount) return -1;
  if (spot.yelp_price_level) return String(spot.yelp_price_level).length * YELP_PRICE_BUCKET_SCALE;
  return Infinity;
}

// ISO currency code → display symbol. Values that read as the code itself keep
// a trailing space (e.g. "AED ") so they don't collide with the bare code.
// Null-prototype (like catalog-utils.js KIND_LABELS) so a stored `currency` of
// "constructor" / "hasOwnProperty" / "__proto__" can never resolve to an
// Object.prototype member and leak its stringified source into the price label
// ("function Object() { [native code] }50"). Object.assign copies the literals
// onto an Object.create(null) receiver, which is then frozen — real currency
// codes resolve byte-identically to the old plain-object literal.
const CURRENCY_SYMBOLS = Object.freeze(Object.assign(Object.create(null), {
  USD:"$", JPY:"\u00a5", EUR:"\u20ac", GBP:"\u00a3",
  KRW:"\u20a9", AUD:"A$", CAD:"C$", HKD:"HK$", SGD:"S$", TWD:"NT$", BRL:"R$",
  THB:"\u0e3f", AED:"AED ", CNY:"\u00a5", NZD:"NZ$", ARS:"AR$", DKK:"kr",
  PHP:"\u20b1", CZK:"K\u010d", SEK:"kr", CHF:"CHF "
}));

// Separator between a price range's bounds: "68-150" -> "$68 – 150".
const PRICE_RANGE_SEPARATOR = " – ";

// Format a spot's price for display: "500" + currency → "$500".
// For ranges: "68-150" → "$68 – 150". Discount spots return the discount %.
function priceLabel(spot) {
  if (!spot) return "";
  // String() a non-string price (a JSON number smuggled in through a tampered
  // state.json) rather than throwing on .replace, which would escape the
  // chunked catalog walk and leave the whole panel empty. A non-scalar price
  // (object/array) is dropped by Service's coerceSpotField, so gate it to the
  // missing-price "" here too — otherwise String(spot.price) renders
  // "[object Object]" and the two read paths disagree on the same hostile file.
  var price = (typeof spot.price === "object" && spot.price !== null) ? "" : spot.price;
  if (price) {
    const symbol = CURRENCY_SYMBOLS[spot.currency] || String(spot.currency || "");
    return symbol + String(price).replace(/-/g, PRICE_RANGE_SEPARATOR);
  }
  return String(spot.discount || "");
}

// Format a spot's course/discount-time info: "20 courses" for omakase spots, or
// the discount time for discount spots.
function formatCoursesOrTime(spot) {
  if (!spot) return "";
  return spot.courses ? String(spot.courses) + " courses" : formatDiscountTime(spot.discount_window);
}

// Format a discount_window value for the spec line. A bare time ("6pm") is
// ambiguous — the discount could start, end, or apply at that hour — so it is
// labelled "from 6pm". A value that already expresses a range is left untouched:
// a dash, en-dash, slash, or the word "to" marks the two bounds (the seed holds
// "5-7pm"- and "7pm/10pm"-shaped values), so prefixing it would mangle the
// window into "from 5-7pm". Empty/absent values stay "".
function formatDiscountTime(value) {
  var time = asString(value).trim();
  if (!time) return "";
  if (/[-–/]|\bto\b/i.test(time)) return time;
  return "from " + time;
}

// The courses segment as the card line renders it: formatCoursesOrTime(), except for
// an AYCE spot whose `courses` value is itself the AYCE token — there the
// segment merely restates the "AYCE" kind label ("AYCE · $95 · AYCE courses"),
// so it is omitted. Suppression keys on hasAyceCourses — the same predicate
// that opens the AYCE rule (isAyceSpot) — so it can never drift from
// detection. Every other spot keeps its segment unchanged.
function formatCoursesSegment(spot) {
  if (!spot) return "";
  if (hasAyceCourses(spot)) return "";
  return formatCoursesOrTime(spot);
}

// Below this magnitude, a unit-bearing value shows one decimal ("3.2 km");
// at and above it, a whole number ("12 km").
const DISTANCE_ONE_DECIMAL_BELOW_KM = 10;

// Format a distance in kilometres: under 10 shows one decimal ("3.2 km"),
// 10 and over shows a whole number ("12 km"). Non-finite input (no home
// location) renders empty.
function formatDistance(km) {
  if (km == null || !isFiniteNumber(km)) return "";
  return (km < DISTANCE_ONE_DECIMAL_BELOW_KM ? km.toFixed(1) : Math.round(km)) + KM_SUFFIX;
}

// Parse a JSON string, returning `fallback` for empty/non-string input,
// malformed JSON, or any falsy parse result. Because the result is
// `JSON.parse(raw) || fallback`, valid JSON that parses to a falsy value —
// `0`, `false`, `null`, or `""` — also yields the fallback rather than the
// parsed value. Callers that must distinguish these from failure should call
// JSON.parse directly.
function parseJson(raw, fallback) {
  if (!raw || typeof raw !== "string") return fallback;
  try {
    return JSON.parse(raw) || fallback;
  } catch (_) {
    // Malformed JSON is expected input (seed data and user-edited files).
    return fallback;
  }
}

// Parse a state file that must hold a JSON array (journal.json, user_spots.json,
// wishlist.json). These files are user/tool-writable, so a top-level JSON object
// (or any non-array) must degrade to [] rather than leave a non-array in place —
// a non-array would make the next .push/.splice/.length throw. Returns the
// parsed array, or [] for any wrong-shaped content. Shared by Service.qml and
// BarWidget.qml, which each keep their own assignment (e.g. root.journal = ...).
function parseJsonArray(raw) {
  const parsed = parseJson(raw, []);
  return Array.isArray(parsed) ? parsed : [];
}

// Correct runtime type of each persisted spot field, consumed by coerceSpotField
// so a user_spots.json / hand-edited state.json entry can't carry a wrong-typed
// value (e.g. price: 123) into the bar widget, whose formatters assume
// strings/arrays/numbers. String fields coerce to their string form;
// transactions/display_address to arrays of strings; lat/lon/yelp_rating/
// yelp_review_count to finite numbers; is_closed to a boolean. courses/
// discount/price stay strings — the seed data writes them as strings ("18",
// "50%", "68-150") and the formatters render them verbatim, so coercing them
// to numbers would drop non-numeric values ("AYCE", "10-15", "50%").
// `var` (not `const`) so QML's import qualifier can read SpotUtils.spotFieldTypes.
// Service.qml derives its persistedSpotFields whitelist from Object.keys() of
// this map, so the insertion order below is the field order written to state.json.
var spotFieldTypes = {
  "name": "string", "lat": "number", "lon": "number",
  "neighborhood": "string", "website": "string", "phone": "string",
  "price": "string", "courses": "string", "currency": "string",
  "discount_window": "string", "discount": "string", "yelp_url": "string",
  "region_code": "string", "image_url": "string", "is_closed": "bool",
  "yelp_rating": "number", "yelp_review_count": "number",
  "yelp_price_level": "string", "country": "string",
  "transactions": "string_array", "address": "string",
  "display_address": "string_array"
};

// Upper bound on any persisted string field, enforced by coerceSpotField.
// foldSearchText() splits a string into one array element per code unit and
// normalizeAyceText() runs a full-string regex — both inside the chunked
// catalog walk — so an unbounded name/neighborhood/image_url from a crafted
// state.json or user_spots.json would allocate one element per character
// (millions for a multi-megabyte value) there. Real seed strings top out at
// ~68 characters and journal notes are capped at 2000 by Service.maxNotesLen,
// so 4096 is comfortably above every legitimate value while still bounding the
// pathological case.
const MAX_STRING_FIELD_LEN = 4096;

// Coerce one persisted field to its correct runtime type, or return undefined
// when the value can't be coerced (the caller then drops the field — the same
// drop-invalid philosophy as the whitelist). String fields accept strings
// (truncated to MAX_STRING_FIELD_LEN) and numbers/booleans via String();
// objects/arrays are dropped. Numbers must parse to a finite value. is_closed
// must be a real boolean. Array fields must already be arrays; each element is
// stringified, capped, and non-scalar elements are dropped from the result.
function coerceSpotField(field, value) {
  var type = spotFieldTypes[field];
  if (type === "string") {
    if (typeof value === "string") return value.slice(0, MAX_STRING_FIELD_LEN);
    if (typeof value === "number" || typeof value === "boolean") return String(value);
    return undefined;
  }
  if (type === "number") {
    var number = Number(value);
    return Number.isFinite(number) ? number : undefined;
  }
  if (type === "bool") {
    return (value === true || value === false) ? value : undefined;
  }
  if (type === "string_array") {
    if (!Array.isArray(value)) return undefined;
    var array = [];
    for (var index = 0; index < value.length; index++) {
      var element = value[index];
      if (typeof element === "string") array.push(element.slice(0, MAX_STRING_FIELD_LEN));
      else if (typeof element === "number" || typeof element === "boolean") array.push(String(element));
    }
    return array;
  }
  return undefined;
}

// True when the spot takes restaurant reservations (Yelp `transactions`).
function canBook(spot) {
  return !!(spot && Array.isArray(spot.transactions) && spot.transactions.includes("restaurant_reservation"));
}

// True only when Yelp explicitly marks the spot permanently closed.
function isClosed(spot) {
  return !!(spot && spot.is_closed === true);
}

// Yelp header image URL, or "" when absent or carrying an unsafe scheme.
// Only https:// and a small raster data:image allow-list (png/jpeg/webp,
// base64 only) are permitted. http:// (cleartext) and SVG data URLs (which
// can carry scripts) are rejected, so a file:///qrc:/ value smuggled in
// through seed data or user_spots.json cannot make Qt's Image load a local
// resource.
const ALLOWED_DATA_IMAGE_PREFIXES = ["data:image/png;base64,", "data:image/jpeg;base64,", "data:image/webp;base64,"];

// Upper bound on an inline base64 `data:` image URI, enforced by spotImageUrl
// before the value is handed to Qt's Image. The seed ships only https:// image
// URLs, so no real value is near this; a hand-authored data: URI in
// user_spots.json is a small logo/header thumbnail (tens of KB), while a
// "multi-megabyte" base64 blob is exactly the payload this rejects. 512 KiB is
// comfortably above any real inline image.
const MAX_DATA_URI_LEN = 512 * 1024;

function spotImageUrl(spot) {
  if (!spot || !spot.image_url) return "";
  const raw = String(spot.image_url);
  const url = raw.toLowerCase();
  if (url.startsWith("https://")) return spot.image_url;
  if (!ALLOWED_DATA_IMAGE_PREFIXES.some((prefix) => url.startsWith(prefix))) return "";
  if (raw.length > MAX_DATA_URI_LEN) return "";
  return spot.image_url;
}

const MAPS_QUERY_BASE = "https://www.google.com/maps?q=";

// Non-empty address lines for a spot: `display_address`'s entries coerced to
// strings, trimmed, and filtered to non-empty. A non-array value (a string or
// null smuggled in through a hand-edited state.json) yields []; each element is
// stringified before .trim() so a wrong-typed element (a number) never throws
// inside the chunked catalog walk, and a null/undefined element drops to ""
// rather than stringifying to "null"/"undefined".
function displayAddressLines(spot) {
  if (!spot || !Array.isArray(spot.display_address)) return [];
  return spot.display_address
    .map(function (line) { return asString(line).trim(); })
    .filter(Boolean);
}

// Google Maps query URL for a spot: the full street address (URL-encoded,
// friendlier in Maps) when present, else bare lat/lon, else "". Coordinates
// are coerced to finite numbers before interpolation, so a non-numeric or
// hostile lat/lon (e.g. "40.7&label=phish" from a tampered state.json or
// user_spots.json) can't inject query text and degrades to the same "" a
// missing coordinate yields.
function mapsUrl(spot) {
  if (!spot) return "";
  const lines = displayAddressLines(spot);
  if (lines.length) return MAPS_QUERY_BASE + encodeURIComponent(lines.join(", "));
  if (!hasCoords(spot.lat, spot.lon)) return "";
  const lat = Number(spot.lat);
  const lon = Number(spot.lon);
  return MAPS_QUERY_BASE + lat + "," + lon;
}

// Sanitize an external link for opening: only https://, mailto:, and a
// validated tel: number are allowed. The scheme is parsed (not prefix-matched)
// so case is normalized once, and the same normalized string is what gets
// returned. Cleartext http://, file://, javascript:, and scheme-less input are
// rejected (""). This guard keeps a seed/user-supplied URL from smuggling an
// arbitrary scheme into Qt.openUrlExternally.
function safeExternalUrl(url) {
  if (!url) return "";
  const target = String(url).trim();
  const match = target.match(/^([a-z][a-z0-9+.\-]*):(.*)$/i);
  if (!match) return ""; // no scheme — reject
  const scheme = match[1].toLowerCase();
  if (scheme === "https") return "https:" + match[2];
  if (scheme === "mailto") {
    const address = match[2].trim();
    return address ? "mailto:" + address : "";
  }
  if (scheme === "tel") {
    // A phone number may only carry a leading "+", digits, and phone
    // punctuation. Anything else could smuggle a payload, so reject it.
    const number = match[2].trim();
    if (/^\+?[0-9()\-\s]+$/.test(number)) return "tel:" + number;
  }
  return "";
}

// Single street-address line for a spot: the curated `address` field when
// present, else the first line of `display_address`. The fallback is extracted
// through displayAddressLines — the same normalizer mapsUrl and the clipboard
// share — so the first line is coerced/trimmed identically everywhere.
function streetAddress(spot) {
  if (!spot) return "";
  if (spot.address) return String(spot.address);
  return displayAddressLines(spot)[0] || "";
}

// Location line for the clipboard ("City · State · Country · Neighborhood"),
// or "" when the spot has neither a city label nor a neighborhood.
function clipboardLocationLine(spot, cityLabel) {
  if (!cityLabel && !(spot && spot.neighborhood)) return "";
  return joinTruthy([
    cityLabel,
    spot && spot.region_code,
    spot && spot.country,
    spot && spot.neighborhood
  ]);
}

// Price/course spec line for the clipboard: "from 8pm · 50% off" for discount
// spots (the time through formatDiscountTime — the same treatment the card's
// spec line applies), "AYCE" (with the price when present) for AYCE spots — the
// name-signalled AYCE spots have no price/courses and must still produce a line
// — else "price · courses" (each part omitted when absent), or "" for an empty
// spot.
function clipboardSpecLine(spot) {
  if (!spot) return "";
  var kind = spotKind(spot);
  if (kind === "discount" && spot.discount_window && spot.discount) {
    return formatDiscountTime(spot.discount_window) + SEP + spot.discount + " off";
  }
  if (kind === "ayce") {
    return joinTruthy([priceLabel(spot), "AYCE"]);
  }
  return joinTruthy([priceLabel(spot), formatCoursesOrTime(spot)]);
}

// Stamp one spot's derived display fields once at load so SpotCard reads a
// plain field instead of re-running ~10 formatters on every delegate bind.
// Each value is a pure function of the spot's immutable fields, so it never
// changes after load. `cityKey` is the spot's city, stamped as `_cityKey`; the
// `_*` names are the stable contract SpotCard.qml reads.
function applyDerivedFields(spot, cityKey) {
  // A non-object entry (null from a corrupt/truncated state.json, or a stray
  // primitive/array) carries no derived fields — return it unchanged so the
  // chunked catalog walk never throws on a null element.
  if (!spot || typeof spot !== "object" || Array.isArray(spot)) return spot;
  spot._cityKey = cityKey;
  spot._spotKind = spotKind(spot);
  spot._isClosed = isClosed(spot);
  spot._canBook = canBook(spot);
  spot._imageUrl = spotImageUrl(spot);
  spot._priceLabel = priceLabel(spot);
  spot._coursesSegment = formatCoursesSegment(spot);
  // The Yelp stamps re-coerce AND default, so they are not redundant with
  // coerceSpotField. coerceSpotField guarantees the raw *type* at the Service
  // write boundary (yelp_rating/yelp_review_count are finite numbers, yelp_price_level
  // a string), but it DROPS an absent or wrong-typed field rather than supplying
  // a value — the `|| 0` / `|| ""` here are what normalize "no Yelp rating" to
  // 0 and "no price level" to "", a contract the widget's readers (ScoreBlock,
  // SpotCardIdentity, effectiveRating) depend on. The test suite also feeds
  // applyDerivedFields raw fixtures that never passed through coerceSpotField
  // (a string review count, a numeric price level), so the re-coercion is
  // exercised directly. Keep the three stamps.
  spot._yelpRating = Number(spot.yelp_rating) || 0;
  spot._yelpReviewCount = Number(spot.yelp_review_count) || 0;
  spot._yelpPrice = String(spot.yelp_price_level || "");
  spot._mapsUrl = mapsUrl(spot);
  return spot;
}

// Yelp line group for the clipboard: the price level, the Yelp rating (with its
// review count), and the Yelp URL — each omitted when its field is absent.
function clipboardYelpLines(spot) {
  const lines = [];
  if (spot.yelp_price_level) lines.push("Price: " + spot.yelp_price_level);
  const yelpRating = Number(spot.yelp_rating);
  if (spot.yelp_rating && !Number.isNaN(yelpRating)) {
    let ratingLine = "Yelp: " + yelpRating.toFixed(1);
    if (spot.yelp_review_count) ratingLine += " (" + spot.yelp_review_count + " reviews)";
    lines.push(ratingLine);
  }
  if (spot.yelp_url) lines.push("Yelp: " + spot.yelp_url);
  return lines;
}

// Contact line group for the clipboard: the Maps, Website, and Phone lines —
// each omitted when its field is absent. `_mapsUrl` is already stamped on
// catalog spots; only unstamped spots (tests) need the fallback recompute.
function clipboardContactLines(spot) {
  const lines = [];
  const mapUrl = (spot._mapsUrl && typeof spot._mapsUrl === "string") ? spot._mapsUrl : mapsUrl(spot);
  if (mapUrl) lines.push("Maps: " + mapUrl);
  if (spot.website) lines.push("Website: " + spot.website);
  if (spot.phone) lines.push("Phone: " + spot.phone);
  return lines;
}

// Compose the multi-line clipboard text for a spot: name, location line,
// street address, price/courses (or discount window), Yelp price/rating/URL,
// and Maps/Website/Phone lines. `cityLabel` is the resolved city label
// ("" when the spot has no city key); the caller appends the "via Omakase"
// attribution suffix.
function buildSpotClipboardText(spot, name, cityLabel) {
  var lines = [name];
  const location = clipboardLocationLine(spot, cityLabel);
  if (location) lines.push(location);
  if (spot) {
    const addressLines = displayAddressLines(spot);
    if (addressLines.length) lines.push(addressLines.join(", "));
    const spec = clipboardSpecLine(spot);
    if (spec) lines.push(spec);
    lines = lines.concat(clipboardYelpLines(spot), clipboardContactLines(spot));
  }
  return lines.join("\n");
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    SEP,
    SEP_LEAD,
    KM_SUFFIX,
    joinTruthy,
    asString,
    spotKind,
    normalizeName,
    foldSearchText,
    // Exported so catalog-utils.js buildNeighborhoodRecords shares the same
    // (0,0)-accepting coordinate gate as haversine/mapsUrl through the Node
    // require path (in QML the bare SpotUtils qualifier already exposes it).
    hasCoords,
    isFiniteNumber,
    haversine,
    formatDate,
    priceSortKey,
    priceLabel,
    formatCoursesSegment,
    formatDistance,
    parseJson,
    parseJsonArray,
    spotFieldTypes,
    coerceSpotField,
    canBook,
    isClosed,
    safeExternalUrl,
    mapsUrl,
    streetAddress,
    applyDerivedFields,
    buildSpotClipboardText
  };
}
