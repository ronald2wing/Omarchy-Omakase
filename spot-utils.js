// spot-utils.js — Omakase data utilities
// Dual-use: Node.js (tests) and QML (import "spot-utils.js" as SpotUtils)

// Return the spot's kind: "omakase" when courses+price are present, "discount"
// when time+discount are present, else "". The result is always one of the
// values the UI's type filter (all|omakase|discount) can match.
function spotKind(spot) {
  if (!spot) return "";
  if (spot.courses && spot.price) return "omakase";
  if (spot.time && spot.discount) return "discount";
  return "";
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

// ISO currency code → display symbol. Values that read as the code itself keep
// a trailing space (e.g. "AED ") so they don't collide with the bare code.
const CURRENCY_SYMBOLS = Object.freeze({ USD:"$", JPY:"\u00a5", EUR:"\u20ac", GBP:"\u00a3",
  KRW:"\u20a9", AUD:"A$", CAD:"C$", HKD:"HK$", SGD:"S$", TWD:"NT$", BRL:"R$",
  THB:"\u0e3f", AED:"AED ", CNY:"\u00a5", NZD:"NZ$", ARS:"AR$", DKK:"kr",
  PHP:"\u20b1", CZK:"K\u010d", SEK:"kr", CHF:"CHF " });

function currencySymbol(code) {
  return CURRENCY_SYMBOLS[code] || "";
}

// Format a spot's price for display: "500" + currency → "$500".
// For ranges: "68-150" → "$68-150". Discount spots return the discount %.
function formatPrice(spot) {
  if (!spot) return "";
  if (spot.price) {
    const symbol = currencySymbol(spot.currency) || spot.currency || "";
    return symbol + spot.price.replace(/-/g, " – ");
  }
  return spot.discount || "";
}

// Format a spot's course/time info: "20 courses" for omakase spots, or the
// discount-window time (e.g. "8pm") for discount spots.
function formatCourses(spot) {
  if (!spot) return "";
  return spot.courses ? spot.courses + " courses" : (spot.time || "");
}

// Format a unit-bearing magnitude: under 10 shows one decimal ("3.2 km"),
// 10 and over shows a whole number ("12 km"). Non-finite input (no home
// location) renders empty.
function formatUnit(value, suffix) {
  if (value == null || !isFinite(value)) return "";
  return (value < 10 ? value.toFixed(1) : Math.round(value)) + suffix;
}

function formatDistance(km) {
  return formatUnit(km, " km");
}

// Kilometres → miles (1 km = 0.621371 mi). Non-finite input passes through
// unchanged so callers can test with isFinite before formatting.
function kmToMiles(km) {
  if (km == null || !isFinite(km)) return km;
  return km * 0.621371;
}

function formatMiles(miles) {
  return formatUnit(miles, " mi");
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
// friendlier in Maps) when present, else bare lat/lon, else "".
function mapsUrl(spot) {
  if (!spot) return "";
  const address = Array.isArray(spot.display_address) ? spot.display_address : [];
  if (address.length) return MAPS_BASE + encodeURIComponent(address.join(", "));
  return (spot.lat && spot.lon) ? MAPS_BASE + spot.lat + "," + spot.lon : "";
}

// Location line for the clipboard ("City · State · Country · Neighborhood"),
// or "" when the spot has neither a city label nor a neighborhood.
function locationLine(spot, displayCityName) {
  if (!displayCityName && !(spot && spot.neighborhood)) return "";
  return [
    displayCityName,
    spot && spot.state,
    spot && spot.country,
    spot && spot.neighborhood
  ].filter(Boolean).join(" · ");
}

// Price/course spec line for the clipboard: "8pm · 50% off" for discount spots,
// else "price · courses" (each part omitted when absent), or "" for an empty spot.
function specLine(spot) {
  if (!spot) return "";
  if (spotKind(spot) === "discount" && spot.time && spot.discount) {
    return spot.time + " · " + spot.discount + " off";
  }
  return [formatPrice(spot), formatCourses(spot)].filter(Boolean).join(" · ");
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
    spotKind,
    haversine,
    formatDate,
    priceNumber,
    currencySymbol,
    formatPrice,
    formatCourses,
    formatDistance,
    kmToMiles,
    formatMiles,
    parseJson,
    canBook,
    isClosed,
    spotImageUrl,
    mapsUrl,
    formatSpotClipboard
  };
}
