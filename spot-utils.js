// spot-utils.js — Omakase data utilities
// Dual-use: Node.js (tests) and QML (import "spot-utils.js" as SpotUtils)

// Shared separator between list segments ("City · State · Country"), and its
// folded/inline form ("· ") baked into a segment's leading text so it never
// renders alone. `var` (not `const`) so QML's import qualifier exposes them
// (const/let bindings are not visible as Qualifier.NAME).
var SEP = " · ";
var SEP_LEAD = "· ";

// Join an array's truthy entries with the shared separator, dropping empty
// strings/null/undefined so a missing segment never leaves a dangling "·".
function joinNonEmpty(parts) {
  return (parts || []).filter(Boolean).join(SEP);
}

// Return the spot's kind: "omakase" when courses+price are present, "discount"
// when time+discount are present, else "". The result is always one of the
// values the UI's type filter (all|omakase|discount) can match.
function spotKind(spot) {
  if (!spot) return "";
  if (spot.courses && spot.price) return "omakase";
  if (spot.time && spot.discount) return "discount";
  return "";
}

// Normalize a spot name for index keys and journal identity: trim + lowercase
// so lookup is case-insensitive (a journal name "Omi Omakase" resolves to the
// catalog "OMI OMAKASE"). Shared by BarWidget's spot index (producer + consumer)
// and Service's journal matching so the key format can never drift apart.
function normalizeName(name) {
  return String(name == null ? "" : name).trim().toLowerCase();
}

// Accent → ASCII folding map for search. Keys are the accented Latin letters
// (and ligatures) that occur in seed data; values are their ASCII equivalents.
// Covers Latin-1 + Latin Extended-A plus the Czech/Slovak caron letters present
// in the data. Anything not in this map passes through unchanged — CJK spot
// names stay as-is (no transliteration). An explicit map is used instead of
// String.prototype.normalize, which is not reliably available in Qt's QJSEngine.
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
  var value = String(text == null ? "" : text);
  var folded = "";
  for (var index = 0; index < value.length; index++) {
    var character = value.charAt(index);
    var replacement = FOLD_MAP[character];
    folded += (replacement !== undefined) ? replacement : character;
  }
  return folded.toLowerCase().replace(/\s+/g, " ").trim();
}

// Haversine distance in kilometres between two lat/lon points.
function haversine(lat1, lon1, lat2, lon2) {
  if (lat1 == null || lon1 == null || lat2 == null || lon2 == null) return Infinity;
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

// Short month names, hoisted so formatDate() does not rebuild the array per call.
const MONTHS = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];

// Cached current year, so the common formatDate() path allocates one Date.
// Refreshed only when an entry's year differs (long-lived process crossing a
// year boundary), which keeps the cache from going stale.
let cachedYear = new Date().getFullYear();

// Short date for compact list rows: "Sep 7" in the current year,
// "Sep 7, 2025" otherwise.
function formatDate(ms) {
  if (!ms) return "";
  const date = new Date(Number(ms));
  let formatted = MONTHS[date.getMonth()] + " " + date.getDate();
  const year = date.getFullYear();
  if (year !== cachedYear) {
    // The entry's year differs from the cached current year. Refresh the cache
    // (the process may have crossed a year boundary) and compare again.
    cachedYear = new Date().getFullYear();
    if (year !== cachedYear) formatted += ", " + year;
  }
  return formatted;
}

// Extract the leading numeric run from a price string for sorting.
// e.g. "$550" → 550, "€240-360" → 240, "95-175" → 95, "1.2.3" → 1.2.
// Returns Infinity when no numeric run is present (sorts to end).
function priceNumber(rawPrice) {
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
function priceSortValue(spot) {
  if (!spot) return Infinity;
  const numeric = priceNumber(spot.price);
  if (Number.isFinite(numeric)) return numeric;
  if (spot.discount) return -1;
  if (spot.yelp_price) return String(spot.yelp_price).length * YELP_PRICE_BUCKET_SCALE;
  return Infinity;
}

// ISO currency code → display symbol. Values that read as the code itself keep
// a trailing space (e.g. "AED ") so they don't collide with the bare code.
const CURRENCY_SYMBOLS = Object.freeze({ USD:"$", JPY:"\u00a5", EUR:"\u20ac", GBP:"\u00a3",
  KRW:"\u20a9", AUD:"A$", CAD:"C$", HKD:"HK$", SGD:"S$", TWD:"NT$", BRL:"R$",
  THB:"\u0e3f", AED:"AED ", CNY:"\u00a5", NZD:"NZ$", ARS:"AR$", DKK:"kr",
  PHP:"\u20b1", CZK:"K\u010d", SEK:"kr", CHF:"CHF " });

function currencySymbol(code) {
  return CURRENCY_SYMBOLS[code] || "";
}

// Separator between a price range's bounds: "68-150" -> "$68 – 150".
const PRICE_RANGE_SEPARATOR = " – ";

// Format a spot's price for display: "500" + currency → "$500".
// For ranges: "68-150" → "$68-150". Discount spots return the discount %.
function formatPrice(spot) {
  if (!spot) return "";
  if (spot.price) {
    const symbol = currencySymbol(spot.currency) || spot.currency || "";
    return symbol + spot.price.replace(/-/g, PRICE_RANGE_SEPARATOR);
  }
  return spot.discount || "";
}

// Format a spot's course/time info: "20 courses" for omakase spots, or the
// discount-window time (e.g. "8pm") for discount spots.
function formatCourses(spot) {
  if (!spot) return "";
  return spot.courses ? spot.courses + " courses" : (spot.time || "");
}

// Below this magnitude, a unit-bearing value shows one decimal ("3.2 km");
// at and above it, a whole number ("12 km").
const ONE_DECIMAL_THRESHOLD = 10;

// Format a unit-bearing magnitude: under 10 shows one decimal ("3.2 km"),
// 10 and over shows a whole number ("12 km"). Non-finite input (no home
// location) renders empty.
function formatUnit(value, suffix) {
  if (value == null || !isFinite(value)) return "";
  return (value < ONE_DECIMAL_THRESHOLD ? value.toFixed(1) : Math.round(value)) + suffix;
}

function formatDistance(km) {
  return formatUnit(km, " km");
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

// True when the spot takes restaurant reservations (Yelp `transactions`).
function canBook(spot) {
  return !!(spot && spot.transactions && spot.transactions.includes("restaurant_reservation"));
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
const DATA_IMAGE_PREFIXES = ["data:image/png;base64,", "data:image/jpeg;base64,", "data:image/webp;base64,"];

function spotImageUrl(spot) {
  if (!spot || !spot.image_url) return "";
  const url = String(spot.image_url).toLowerCase();
  const allowed = url.startsWith("https://") || DATA_IMAGE_PREFIXES.some((prefix) => url.startsWith(prefix));
  return allowed ? spot.image_url : "";
}

const MAPS_BASE = "https://www.google.com/maps?q=";

// Google Maps query URL for a spot: the full street address (URL-encoded,
// friendlier in Maps) when present, else bare lat/lon, else "". Coordinates
// are coerced to finite numbers before interpolation, so a non-numeric or
// hostile lat/lon (e.g. "40.7&label=phish" from a tampered state.json or
// user_spots.json) can't inject query text and degrades to the same "" a
// missing coordinate yields.
function mapsUrl(spot) {
  if (!spot) return "";
  const address = Array.isArray(spot.display_address) ? spot.display_address : [];
  if (address.length) return MAPS_BASE + encodeURIComponent(address.join(", "));
  if (!spot.lat || !spot.lon) return "";
  const lat = Number(spot.lat);
  const lon = Number(spot.lon);
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) return "";
  return MAPS_BASE + lat + "," + lon;
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

// Single street-address line for a spot: `address` when present, else the
// first element of the `display_address` array, else "".
function streetAddress(spot) {
  if (!spot) return "";
  if (spot.address) return spot.address;
  const displayAddress = Array.isArray(spot.display_address) ? spot.display_address : [];
  return displayAddress[0] || "";
}

// Location line for the clipboard ("City · State · Country · Neighborhood"),
// or "" when the spot has neither a city label nor a neighborhood.
function locationLine(spot, displayCityName) {
  if (!displayCityName && !(spot && spot.neighborhood)) return "";
  return joinNonEmpty([
    displayCityName,
    spot && spot.state,
    spot && spot.country,
    spot && spot.neighborhood
  ]);
}

// Price/course spec line for the clipboard: "8pm · 50% off" for discount spots,
// else "price · courses" (each part omitted when absent), or "" for an empty spot.
function specLine(spot) {
  if (!spot) return "";
  if (spotKind(spot) === "discount" && spot.time && spot.discount) {
    return spot.time + SEP + spot.discount + " off";
  }
  return joinNonEmpty([formatPrice(spot), formatCourses(spot)]);
}

// Stamp one spot's derived display fields once at load so SpotCard reads a
// plain field instead of re-running ~10 formatters on every delegate bind.
// Each value is a pure function of the spot's immutable fields, so it never
// changes after load. `cityKey` is the spot's city, stamped as `_cityKey`; the
// `_*` names are the stable contract SpotCard.qml reads.
function stampDerivedFields(spot, cityKey) {
  // A non-object entry (null from a corrupt/truncated state.json, or a stray
  // primitive/array) carries no derived fields — return it unchanged so the
  // chunked catalog walk never throws on a null element.
  if (!spot || typeof spot !== "object" || Array.isArray(spot)) return spot;
  spot._cityKey = cityKey;
  spot._spotKind = spotKind(spot);
  spot._isClosed = isClosed(spot);
  spot._canBook = canBook(spot);
  spot._imageUrl = spotImageUrl(spot);
  spot._priceLabel = formatPrice(spot);
  spot._courses = formatCourses(spot);
  spot._yelpRating = Number(spot.yelp_rating) || 0;
  spot._yelpReviewCount = spot.yelp_review_count || 0;
  spot._yelpPrice = spot.yelp_price || "";
  spot._mapsUrl = mapsUrl(spot);
  return spot;
}

// Compose the multi-line clipboard text for a spot: name, location line,
// street address, price/courses (or discount window), Yelp price/rating/URL,
// and Maps/Website/Phone lines. `displayCityName` is the resolved city label
// ("" when the spot has no city key); the caller appends the "via Omakase"
// attribution suffix.
function formatSpotClipboard(spot, name, displayCityName) {
  const lines = [name];
  const location = locationLine(spot, displayCityName);
  if (location) lines.push(location);
  if (spot) {
    const address = Array.isArray(spot.display_address) ? spot.display_address : [];
    if (address.length) lines.push(address.join(", "));
    const spec = specLine(spot);
    if (spec) lines.push(spec);
    if (spot.yelp_price) lines.push("Price: " + spot.yelp_price);
    const yelpRating = Number(spot.yelp_rating);
    if (spot.yelp_rating && !Number.isNaN(yelpRating)) {
      let ratingLine = "Yelp: " + yelpRating.toFixed(1);
      if (spot.yelp_review_count) ratingLine += " (" + spot.yelp_review_count + " reviews)";
      lines.push(ratingLine);
    }
    if (spot.yelp_url) lines.push("Yelp: " + spot.yelp_url);
    const mapUrl = mapsUrl(spot);
    if (mapUrl) lines.push("Maps: " + mapUrl);
    if (spot.website) lines.push("Website: " + spot.website);
    if (spot.phone) lines.push("Phone: " + spot.phone);
  }
  return lines.join("\n");
}

if (typeof module !== "undefined") {
  module.exports = {
    SEP,
    SEP_LEAD,
    joinNonEmpty,
    spotKind,
    normalizeName,
    foldSearchText,
    haversine,
    formatDate,
    priceNumber,
    priceSortValue,
    currencySymbol,
    formatPrice,
    formatCourses,
    formatDistance,
    parseJson,
    canBook,
    isClosed,
    spotImageUrl,
    safeExternalUrl,
    mapsUrl,
    streetAddress,
    stampDerivedFields,
    formatSpotClipboard
  };
}
