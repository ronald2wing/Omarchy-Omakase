// Pure scoring + data logic for the omakase plugin.
// Loads under both Node (tests) and QML (`import "Model.js" as M`).
// No imports, no shell access — keep all parsing/formatting here.

var DAY = 86400000;
var MEAL_TYPES = ["breakfast", "lunch", "dinner", "snack"];
// "snack" is a valid journal mealType (late-night meals) but not a planned slot.
var PLAN_MEAL_TYPES = ["breakfast", "lunch", "dinner"];
var SOURCES = ["restaurant", "recipe", "manual"];

function makeId(prefix) {
  return prefix + "-" + Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 8);
}

function normalizeCuisine(name) {
  if (!name) return "";
  var n = String(name).toLowerCase();
  var map = [
    ["italian", ["pizza", "pasta", "italian", "trattoria"]],
    ["japanese", ["sushi", "ramen", "japanese", "izakaya", "omakase"]],
    ["mexican", ["taco", "mexican", "burrito"]],
    ["chinese", ["chinese", "dim sum", "noodle"]],
    ["indian", ["indian", "curry", "tandoori"]],
    ["thai", ["thai"]],
    ["american", ["burger", "american", "bbq", "grill"]],
    ["french", ["french", "bistro", "crepe"]],
    ["greek", ["greek", "gyro"]],
    ["korean", ["korean", "bibimbap"]],
    ["vietnamese", ["vietnamese", "pho"]],
    ["mediterranean", ["mediterranean", "falafel", "hummus"]]
  ];
  for (var i = 0; i < map.length; i++) {
    for (var j = 0; j < map[i][1].length; j++) {
      if (n.indexOf(map[i][1][j]) !== -1) return map[i][0];
    }
  }
  return "";
}

// Journal entries store restaurantId/recipeId as the candidate's `id`, while
// raw candidates only expose `id` — match on `id` when both sources agree, so
// same-named places don't cross-contaminate each other's history.
function matchesCandidate(candidate, entry) {
  if (candidate.source === "restaurant" && entry.restaurantId && candidate.id) {
    return entry.restaurantId === candidate.id;
  }
  if (candidate.source === "recipe" && entry.recipeId && candidate.id) {
    return entry.recipeId === candidate.id;
  }
  return !!(entry.name && candidate.name && entry.name.toLowerCase() === candidate.name.toLowerCase());
}

// Youngest age (ms) of the journal entries matching `predicate`, or null when
// none match. Callers guard the journal array; shared by every signal that keys
// off "when did this candidate/cuisine last appear".
function mostRecentAge(predicate, journal, now) {
  var best = null;
  for (var i = 0; i < journal.length; i++) {
    var e = journal[i];
    if (!predicate(e)) continue;
    var age = now - (e.timestamp || 0);
    if (age < 0) continue;
    if (best === null || age < best) best = age;
  }
  return best;
}

function recencyPenalty(candidate, journal, now) {
  if (!Array.isArray(journal)) return { score: 0, reason: "" };
  var age = mostRecentAge(function(e) { return matchesCandidate(candidate, e); }, journal, now);
  if (age === null) return { score: 0, reason: "" };
  var days = age / DAY;
  if (days < 1) return { score: -40, reason: "eaten today" };
  if (days < 2) return { score: -30, reason: "eaten yesterday" };
  if (days < 4) return { score: -15, reason: "eaten recently" };
  if (days < 7) return { score: -5, reason: "eaten this week" };
  return { score: 0, reason: "" };
}

function declinePenalty(candidate, journal, now) {
  if (!Array.isArray(journal)) return { score: 0, reason: "" };
  var age = mostRecentAge(function(e) { return e.declined === true && matchesCandidate(candidate, e); }, journal, now);
  if (age === null) return { score: 0, reason: "" };
  var days = age / DAY;
  if (days < 1) return { score: -60, reason: "declined today" };
  if (days < 2) return { score: -50, reason: "declined yesterday" };
  if (days < 7) return { score: -30, reason: "declined this week" };
  if (days < 14) return { score: -10, reason: "declined recently" };
  return { score: 0, reason: "" };
}

function cuisineVariety(cuisine, journal, now) {
  if (!cuisine) return { score: 0, reason: "" };
  if (!Array.isArray(journal)) return { score: 0, reason: "" };
  var age = mostRecentAge(function(e) { return !!e.cuisine && e.cuisine.toLowerCase() === cuisine.toLowerCase(); }, journal, now);
  if (age === null) return { score: 10, reason: "new cuisine" };
  var days = age / DAY;
  if (days < 2) return { score: -10, reason: "same cuisine recently" };
  if (days < 5) return { score: 0, reason: "" };
  return { score: 5, reason: "cuisine variety" };
}

function timeOfDayFit(candidateMealType, targetMealType) {
  if (!candidateMealType) return { score: 0, reason: "" };
  if (candidateMealType === targetMealType) return { score: 10, reason: "good for " + targetMealType };
  return { score: 0, reason: "" };
}

function distanceScore(distanceKm, radiusKm) {
  if (typeof distanceKm !== "number" || isNaN(distanceKm)) return { score: 0, reason: "" };
  var r = (typeof radiusKm === "number" && radiusKm > 0) ? radiusKm : 10;
  var normalized = Math.max(0, 1 - (distanceKm / r));
  var score = Math.round(normalized * 10);
  return { score: score, reason: score > 0 ? "nearby" : "" };
}

function ratingBoost(candidate, journal) {
  if (!Array.isArray(journal)) return { score: 0, reason: "" };
  var sum = 0, count = 0;
  for (var i = 0; i < journal.length; i++) {
    var e = journal[i];
    if (!matchesCandidate(candidate, e)) continue;
    if (typeof e.rating === "number" && e.rating >= 1 && e.rating <= 5) {
      sum += e.rating;
      count++;
    }
  }
  if (count === 0) return { score: 0, reason: "" };
  var avg = sum / count;
  var score = Math.round((avg - 3) * 5);
  return { score: score, reason: score > 0 ? "rated " + avg.toFixed(1) : "" };
}

var NOTE_POSITIVE = ["love", "loved", "delicious", "amazing", "favorite", "favourite", "great", "tasty", "perfect", "excellent", "best", "awesome", "yummy", "recommend", "wonderful", "fantastic", "incredible", "craving", "crave", "must try", "will order again"];
var NOTE_NEGATIVE = ["salty", "too salty", "dry", "bland", "bad", "greasy", "oily", "soggy", "terrible", "awful", "worst", "disappointing", "overcooked", "undercooked", "cold", "stale", "tasteless", "gross", "flavorless", "meh", "not good", "too sweet", "too spicy", "watery"];

// Classify a note's sentiment from keywords: +1 positive, -1 negative, 0 neutral.
function classifyNoteSentiment(notes) {
  if (typeof notes !== "string" || notes.trim() === "") return 0;
  var n = notes.toLowerCase();
  var pos = 0, neg = 0, i;
  for (i = 0; i < NOTE_POSITIVE.length; i++) { if (n.indexOf(NOTE_POSITIVE[i]) !== -1) pos++; }
  for (i = 0; i < NOTE_NEGATIVE.length; i++) { if (n.indexOf(NOTE_NEGATIVE[i]) !== -1) neg++; }
  if (pos > neg) return 1;
  if (neg > pos) return -1;
  return 0;
}

// Fold free-text journal notes into a candidate's score, matching on identity so a
// "too salty" note down-ranks that specific dish/restaurant next time.
function noteScore(candidate, journal) {
  if (!Array.isArray(journal)) return { score: 0, reason: "" };
  var net = 0, found = 0;
  for (var i = 0; i < journal.length; i++) {
    var e = journal[i];
    if (!matchesCandidate(candidate, e)) continue;
    var s = classifyNoteSentiment(e.notes);
    if (s === 0) continue;
    net += s;
    found++;
  }
  if (found === 0) return { score: 0, reason: "" };
  var score = Math.max(-10, Math.min(10, net * 5));
  if (score > 0) return { score: score, reason: "you noted it as good" };
  if (score < 0) return { score: score, reason: "you noted it as bad" };
  return { score: 0, reason: "" };
}

function cuisineAffinity(cuisine, mealType, journal) {
  if (!cuisine || !mealType || !Array.isArray(journal)) return { score: 0, reason: "" };
  var sum = 0, count = 0;
  for (var i = 0; i < journal.length; i++) {
    var e = journal[i];
    if (!e.cuisine) continue;
    if (e.cuisine.toLowerCase() !== cuisine.toLowerCase()) continue;
    if (!e.mealType) continue;
    if (e.mealType !== mealType) continue;
    if (typeof e.rating === "number" && e.rating >= 1 && e.rating <= 5) {
      sum += e.rating;
      count++;
    }
  }
  if (count === 0) return { score: 0, reason: "" };
  var avg = sum / count;
  var score = Math.round((avg - 3) * 5);
  return { score: score, reason: score > 0 ? "you like " + cuisine + " for " + mealType : "" };
}

var CUISINE_DRINKS = {
  italian: "Negroni",
  japanese: "sake",
  mexican: "Margarita",
  french: "French 75",
  indian: "Mango Lassi",
  greek: "Ouzo Lemonade",
  american: "Old Fashioned",
  thai: "Thai Basil Smash",
  chinese: "Green Tea",
  korean: "Soju",
  vietnamese: "Vietnamese Coffee",
  mediterranean: "Aperol Spritz"
};

function cuisineDrink(cuisine) {
  if (!cuisine) return "Aperol Spritz";
  var key = String(cuisine).toLowerCase();
  return CUISINE_DRINKS[key] || "Aperol Spritz";
}

function drinkFor(cuisine, drinksCatalog) {
  var name = cuisineDrink(cuisine);
  var thumb = "";
  if (Array.isArray(drinksCatalog)) {
    for (var i = 0; i < drinksCatalog.length; i++) {
      var d = drinksCatalog[i];
      if (d && d.name && d.name.toLowerCase() === name.toLowerCase()) {
        thumb = d.thumb || "";
        break;
      }
    }
  }
  return { name: name, thumb: thumb };
}

function blurb(candidate) {
  if (!candidate) return "";
  var parts = [];
  if (candidate.cuisine) parts.push(String(candidate.cuisine));
  if (candidate.source === "recipe" && candidate.category) parts.push(String(candidate.category));
  if (candidate.source === "restaurant" && candidate.address) parts.push(String(candidate.address));
  return parts.join(" · ");
}

function formatTimestamp(ts) {
  if (typeof ts !== "number" || isNaN(ts)) return "";
  var d = new Date(ts);
  function pad(n) { return n < 10 ? "0" + n : String(n); }
  return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) + " " + pad(d.getHours()) + ":" + pad(d.getMinutes());
}

function scoreCandidates(candidates, journal, options) {
  if (!Array.isArray(candidates)) return [];
  var now = options && options.now ? options.now : Date.now();
  var mealType = options && options.mealType ? options.mealType : "dinner";
  var radiusKm = options && options.radiusKm ? options.radiusKm : 10;
  var varietyWeight = (options && typeof options.varietyWeight === "number") ? options.varietyWeight : 0.5;
  var drinks = options && Array.isArray(options.drinks) ? options.drinks : [];
  return candidates.map(function(c) {
    var score = 0;
    var reasons = [];
    var r = recencyPenalty(c, journal, now);
    score += r.score; if (r.reason) reasons.push(r.reason);
    var dp = declinePenalty(c, journal, now);
    score += dp.score; if (dp.reason) reasons.push(dp.reason);
    var v = cuisineVariety(c.cuisine, journal, now);
    score += Math.round(v.score * varietyWeight); if (v.reason) reasons.push(v.reason);
    var f = timeOfDayFit(c.mealType, mealType);
    score += f.score; if (f.reason) reasons.push(f.reason);
    if (c.source === "restaurant" && typeof c.distanceKm === "number") {
      var d = distanceScore(c.distanceKm, radiusKm);
      score += d.score; if (d.reason) reasons.push(d.reason);
    }
    var b = ratingBoost(c, journal);
    score += b.score; if (b.reason) reasons.push(b.reason);
    var ca = cuisineAffinity(c.cuisine, mealType, journal);
    score += ca.score; if (ca.reason) reasons.push(ca.reason);
    var ns = noteScore(c, journal);
    score += ns.score; if (ns.reason) reasons.push(ns.reason);
    var drink = c.source === "restaurant" ? drinkFor(c.cuisine, drinks) : { name: "", thumb: "" };
    return { id: c.id, source: c.source, name: c.name, cuisine: c.cuisine, score: score, reasons: reasons, blurb: blurb(c), address: c.address || "", website: c.website || "", drink: drink.name, drinkThumb: drink.thumb };
  }).sort(function(a, b) { return b.score - a.score; });
}

function isoDate(base, offsetDays) {
  var d = new Date(base + offsetDays * DAY);
  return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
}

function generatePlan(candidates, journal, options) {
  var period = options && options.period ? options.period : "day";
  var plan = [];
  var used = {};
  var days = period === "week" ? 7 : 1;
  var base = options && options.startDate ? options.startDate : Date.now();
  var now = options && options.now ? options.now : Date.now();
  for (var d = 0; d < days; d++) {
    var day = { date: isoDate(base, d), meals: [] };
    for (var m = 0; m < PLAN_MEAL_TYPES.length; m++) {
      var mt = PLAN_MEAL_TYPES[m];
      var scored = scoreCandidates(candidates, journal, { mealType: mt, now: now, radiusKm: options && options.radiusKm, drinks: options && options.drinks });
      var pick = null;
      for (var i = 0; i < scored.length; i++) {
        var key = scored[i].source + ":" + scored[i].id;
        if (used[key]) continue;
        pick = scored[i];
        used[key] = true;
        break;
      }
      // The scored candidate already carries every plan field; only the planned
      // slot (mealType) is new, so wrap it rather than re-copying fields.
      if (pick) day.meals.push(Object.assign({ mealType: mt }, pick));
    }
    plan.push(day);
  }
  return plan;
}

// Re-score the meals already on a plan against the current journal. Used by
// undo(): re-inserting a meal removes its rate/decline entry, so its score and
// reasons must be recomputed rather than left at the pre-action values. Meals
// with no matching candidate (e.g. manual entries) are returned unchanged.
function reScorePlan(meals, candidates, journal, options) {
  if (!Array.isArray(meals)) return [];
  if (!Array.isArray(candidates)) candidates = [];
  var opts = options || {};
  return meals.map(function(item) {
    var match = null;
    for (var i = 0; i < candidates.length; i++) {
      var c = candidates[i];
      if (c.source === item.source && c.id === item.id) { match = c; break; }
    }
    if (!match) return item;
    var scored = scoreCandidates([match], journal, {
      mealType: item.mealType,
      now: opts.now,
      radiusKm: opts.radiusKm,
      drinks: opts.drinks
    });
    if (scored.length === 0) return item;
    return Object.assign({}, item, { score: scored[0].score, reasons: scored[0].reasons });
  });
}

// Merge a parsed config over a base, preserving the base's nested `home`
// fields when the parsed `home` is only partially specified. Mirrors the
// top-level merge (missing keys keep their base value) so a user config that
// omits `city` or `lat`/`lon` doesn't drop the defaults.
function mergeConfig(base, parsed) {
  var out = Object.assign({}, base, parsed);
  if (parsed && parsed.home && typeof parsed.home === "object") {
    out.home = Object.assign({}, base.home, parsed.home);
  }
  return out;
}

function validateMeal(entry) {
  if (!entry || typeof entry !== "object") return { ok: false, error: "not an object" };
  if (typeof entry.name !== "string" || entry.name.trim() === "") return { ok: false, error: "name required" };
  if (MEAL_TYPES.indexOf(entry.mealType) === -1) return { ok: false, error: "invalid mealType" };
  if (SOURCES.indexOf(entry.source) === -1) return { ok: false, error: "invalid source" };
  if (entry.rating !== undefined && entry.rating !== null) {
    if (typeof entry.rating !== "number" || entry.rating < 1 || entry.rating > 5) return { ok: false, error: "rating must be 1-5" };
  }
  if (entry.declined !== undefined && entry.declined !== null) {
    if (typeof entry.declined !== "boolean") return { ok: false, error: "declined must be boolean" };
  }
  if (entry.notes !== undefined && entry.notes !== null) {
    if (typeof entry.notes !== "string") return { ok: false, error: "notes must be string" };
  }
  return { ok: true, error: "" };
}

if (typeof module !== "undefined") {
  module.exports = {
    makeId: makeId,
    normalizeCuisine: normalizeCuisine,
    recencyPenalty: recencyPenalty,
    declinePenalty: declinePenalty,
    cuisineVariety: cuisineVariety,
    timeOfDayFit: timeOfDayFit,
    distanceScore: distanceScore,
    formatTimestamp: formatTimestamp,
    ratingBoost: ratingBoost,
    noteScore: noteScore,
    classifyNoteSentiment: classifyNoteSentiment,
    cuisineAffinity: cuisineAffinity,
    cuisineDrink: cuisineDrink,
    drinkFor: drinkFor,
    blurb: blurb,
    scoreCandidates: scoreCandidates,
    generatePlan: generatePlan,
    reScorePlan: reScorePlan,
    mergeConfig: mergeConfig,
    validateMeal: validateMeal
  };
}
