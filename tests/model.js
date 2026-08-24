const assert = require("node:assert");
const { test } = require("node:test");
const M = require("../Model.js");

const DAY = 86400000;
const now = Date.now();

test("recencyPenalty penalizes eaten-yesterday heavily", () => {
  const c = { id: "r1", source: "restaurant", name: "Pizza Place", cuisine: "italian" };
  const journal = [{ id: "j1", timestamp: now - DAY, mealType: "dinner", name: "Pizza Place", source: "restaurant", restaurantId: "r1" }];
  const r = M.recencyPenalty(c, journal, now);
  assert.strictEqual(r.score, -30);
});

test("recencyPenalty no penalty when never eaten", () => {
  const c = { id: "r1", source: "restaurant", name: "Pizza Place", cuisine: "italian" };
  const r = M.recencyPenalty(c, [], now);
  assert.strictEqual(r.score, 0);
});

test("recencyPenalty matches by id even when names differ", () => {
  const c = { id: "r1", source: "restaurant", name: "New Name", cuisine: "italian" };
  const journal = [{ id: "j1", timestamp: now - DAY, mealType: "dinner", name: "Old Name", source: "restaurant", restaurantId: "r1" }];
  assert.strictEqual(M.recencyPenalty(c, journal, now).score, -30);
});

test("cuisineVariety rewards new cuisine", () => {
  const r = M.cuisineVariety("japanese", [], now);
  assert.strictEqual(r.score, 10);
});

test("cuisineVariety penalizes same cuisine eaten recently", () => {
  const journal = [{ id: "j1", timestamp: now - DAY, mealType: "dinner", name: "Sushi", source: "recipe", cuisine: "japanese" }];
  const r = M.cuisineVariety("japanese", journal, now);
  assert.strictEqual(r.score, -10);
});

test("timeOfDayFit rewards matching meal type", () => {
  assert.strictEqual(M.timeOfDayFit("breakfast", "breakfast").score, 10);
  assert.strictEqual(M.timeOfDayFit("breakfast", "dinner").score, 0);
  assert.strictEqual(M.timeOfDayFit(undefined, "dinner").score, 0);
});

test("distanceScore nearer ranks higher", () => {
  assert.ok(M.distanceScore(1, 10).score > M.distanceScore(9, 10).score);
  assert.strictEqual(M.distanceScore(50, 10).score, 0);
});

test("ratingBoost rewards highly-rated repeats", () => {
  const c = { id: "r1", source: "restaurant", name: "Pizza Place", cuisine: "italian" };
  const journal = [{ id: "j1", timestamp: now - 10 * DAY, mealType: "dinner", name: "Pizza Place", source: "restaurant", restaurantId: "r1", rating: 5 }];
  const r = M.ratingBoost(c, journal);
  assert.ok(r.score > 0);
});

test("scoreCandidates ranks and returns reasons", () => {
  const candidates = [
    { id: "r1", source: "restaurant", name: "Pizza Place", cuisine: "italian", distanceKm: 1 },
    { id: "r2", source: "restaurant", name: "Sushi Bar", cuisine: "japanese", distanceKm: 9 }
  ];
  const journal = [{ id: "j1", timestamp: now - DAY, mealType: "dinner", name: "Pizza Place", source: "restaurant", restaurantId: "r1" }];
  const scored = M.scoreCandidates(candidates, journal, { mealType: "dinner", now, radiusKm: 10 });
  assert.strictEqual(scored.length, 2);
  assert.ok(scored[0].score > scored[1].score);
  assert.ok(Array.isArray(scored[0].reasons));
});

test("generatePlan produces day plan with 3 meals, no repeats", () => {
  const candidates = [
    { id: "r1", source: "restaurant", name: "Pizza Place", cuisine: "italian", distanceKm: 1 },
    { id: "r2", source: "restaurant", name: "Sushi Bar", cuisine: "japanese", distanceKm: 2 },
    { id: "r3", source: "recipe", name: "Pancakes", cuisine: "american", mealType: "breakfast" },
    { id: "r4", source: "recipe", name: "Burger", cuisine: "american", mealType: "lunch" }
  ];
  const plan = M.generatePlan(candidates, [], { period: "day", now });
  assert.strictEqual(plan.length, 1);
  assert.strictEqual(plan[0].meals.length, 3);
  const ids = plan[0].meals.map((m) => m.id);
  assert.strictEqual(new Set(ids).size, ids.length);
});

test("validateMeal accepts valid entry", () => {
  const r = M.validateMeal({ name: "Pizza", mealType: "dinner", source: "manual" });
  assert.strictEqual(r.ok, true);
});

test("validateMeal rejects bad rating", () => {
  const r = M.validateMeal({ name: "Pizza", mealType: "dinner", source: "manual", rating: 9 });
  assert.strictEqual(r.ok, false);
});

test("normalizeCuisine maps keywords", () => {
  assert.strictEqual(M.normalizeCuisine("Sushi Omakase"), "japanese");
  assert.strictEqual(M.normalizeCuisine("Trattoria Roma"), "italian");
  assert.strictEqual(M.normalizeCuisine("Unknown Place"), "");
});

test("makeId returns unique prefixed ids", () => {
  assert.notStrictEqual(M.makeId("m"), M.makeId("m"));
  assert.ok(M.makeId("m").startsWith("m"));
});

test("declinePenalty penalizes recently declined heavily", () => {
  const c = { id: "r1", source: "restaurant", name: "Pizza Place", cuisine: "italian" };
  const journal = [{ id: "j1", timestamp: now - DAY, mealType: "dinner", name: "Pizza Place", source: "restaurant", restaurantId: "r1", declined: true }];
  const r = M.declinePenalty(c, journal, now);
  assert.strictEqual(r.score, -50);
});

test("declinePenalty no penalty when never declined", () => {
  const c = { id: "r1", source: "restaurant", name: "Pizza Place", cuisine: "italian" };
  assert.strictEqual(M.declinePenalty(c, [], now).score, 0);
  assert.strictEqual(M.declinePenalty(c, [{ id: "j1", timestamp: now - DAY, mealType: "dinner", name: "Pizza Place", source: "restaurant", restaurantId: "r1" }], now).score, 0);
});

test("declinePenalty ignores non-declined entries", () => {
  const c = { id: "r1", source: "restaurant", name: "Pizza Place", cuisine: "italian" };
  const journal = [{ id: "j1", timestamp: now - DAY, mealType: "dinner", name: "Pizza Place", source: "restaurant", restaurantId: "r1", declined: false }];
  assert.strictEqual(M.declinePenalty(c, journal, now).score, 0);
});

test("scoreCandidates ranks a declined candidate below the rest", () => {
  const candidates = [
    { id: "r1", source: "restaurant", name: "Pizza Place", cuisine: "italian", distanceKm: 1 },
    { id: "r2", source: "restaurant", name: "Sushi Bar", cuisine: "japanese", distanceKm: 2 }
  ];
  const journal = [{ id: "j1", timestamp: now - DAY, mealType: "dinner", name: "Pizza Place", source: "restaurant", restaurantId: "r1", declined: true }];
  const scored = M.scoreCandidates(candidates, journal, { mealType: "dinner", now, radiusKm: 10 });
  assert.strictEqual(scored.length, 2);
  assert.strictEqual(scored[0].id, "r2");
  assert.ok(scored[1].reasons.some((r) => r.indexOf("declined") !== -1));
});

test("blurb builds recipe line from area + category", () => {
  assert.strictEqual(M.blurb({ source: "recipe", cuisine: "Italian", category: "Dessert" }), "Italian · Dessert");
});

test("blurb builds restaurant line from cuisine + address", () => {
  assert.strictEqual(M.blurb({ source: "restaurant", cuisine: "italian", address: "123 Main St" }), "italian · 123 Main St");
});

test("blurb returns empty string when no short fields", () => {
  assert.strictEqual(M.blurb({ source: "recipe", name: "Mystery" }), "");
  assert.strictEqual(M.blurb({ source: "restaurant", name: "Mystery" }), "");
  assert.strictEqual(M.blurb(null), "");
});

test("generatePlan emits a blurb on each planned meal", () => {
  const candidates = [
    { id: "r1", source: "recipe", name: "Pancakes", cuisine: "American", category: "Breakfast", mealType: "breakfast" },
    { id: "r2", source: "restaurant", name: "Sushi Bar", cuisine: "japanese", address: "1 Fish St", distanceKm: 2 }
  ];
  const plan = M.generatePlan(candidates, [], { period: "day", now });
  for (const meal of plan[0].meals) {
    assert.ok("blurb" in meal);
  }
});

test("validateMeal accepts declined boolean", () => {
  assert.strictEqual(M.validateMeal({ name: "Pizza", mealType: "dinner", source: "manual", declined: true }).ok, true);
  assert.strictEqual(M.validateMeal({ name: "Pizza", mealType: "dinner", source: "manual", declined: false }).ok, true);
});

test("validateMeal rejects non-boolean declined", () => {
  assert.strictEqual(M.validateMeal({ name: "Pizza", mealType: "dinner", source: "manual", declined: "yes" }).ok, false);
});

test("scoreCandidates preserves website into scored object", () => {
  const candidates = [
    { id: "r1", source: "restaurant", name: "Pizza Place", cuisine: "italian", distanceKm: 1, website: "www.pizza.example" },
    { id: "r2", source: "recipe", name: "Pancakes", cuisine: "american" }
  ];
  const scored = M.scoreCandidates(candidates, [], { mealType: "dinner", now, radiusKm: 10 });
  assert.strictEqual(scored[0].website, "www.pizza.example");
  assert.strictEqual(scored[1].website, "");
});

test("generatePlan includes website in meal item", () => {
  const candidates = [
    { id: "r1", source: "restaurant", name: "Pizza Place", cuisine: "italian", distanceKm: 1, website: "https://pizza.example" }
  ];
  const plan = M.generatePlan(candidates, [], { period: "day", now });
  const rest = plan[0].meals.find((m) => m.source === "restaurant");
  assert.ok(rest);
  assert.strictEqual(rest.website, "https://pizza.example");
});

test("formatTimestamp returns local date and time", () => {
  const ts = new Date(2026, 0, 15, 9, 5).getTime();
  const s = M.formatTimestamp(ts);
  assert.match(s, /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$/);
  assert.ok(s.indexOf("2026-01-15") === 0);
});

test("formatTimestamp returns empty string for invalid input", () => {
  assert.strictEqual(M.formatTimestamp(undefined), "");
  assert.strictEqual(M.formatTimestamp(NaN), "");
});

test("cuisineAffinity rewards highly-rated cuisine for matching mealType", () => {
  const journal = [
    { id: "j1", timestamp: now - 10 * DAY, mealType: "dinner", name: "Sushi", source: "recipe", cuisine: "japanese", rating: 5 },
    { id: "j2", timestamp: now - 9 * DAY, mealType: "dinner", name: "Ramen", source: "recipe", cuisine: "japanese", rating: 4 }
  ];
  const r = M.cuisineAffinity("japanese", "dinner", journal);
  assert.ok(r.score > 0);
});

test("cuisineAffinity zero when no ratings for cuisine", () => {
  assert.strictEqual(M.cuisineAffinity("italian", "dinner", []).score, 0);
});

test("cuisineAffinity negative for poorly-rated cuisine", () => {
  const journal = [
    { id: "j1", timestamp: now - 10 * DAY, mealType: "dinner", name: "Burger", source: "restaurant", cuisine: "american", rating: 1 }
  ];
  const r = M.cuisineAffinity("american", "dinner", journal);
  assert.ok(r.score < 0);
});

test("cuisineAffinity ignores entries with no mealType", () => {
  const journal = [
    { id: "j1", timestamp: now - 10 * DAY, name: "Sushi", source: "recipe", cuisine: "japanese", rating: 5 }
  ];
  const r = M.cuisineAffinity("japanese", "dinner", journal);
  assert.strictEqual(r.score, 0);
});

test("cuisineAffinity does not cross-contaminate mealTypes", () => {
  const journal = [
    { id: "j1", timestamp: now - 10 * DAY, mealType: "breakfast", name: "Pancakes", source: "recipe", cuisine: "american", rating: 5 },
    { id: "j2", timestamp: now - 9 * DAY, mealType: "dinner", name: "Burger", source: "restaurant", cuisine: "american", rating: 1 }
  ];
  const breakfast = M.cuisineAffinity("american", "breakfast", journal);
  const dinner = M.cuisineAffinity("american", "dinner", journal);
  assert.ok(breakfast.score > 0);
  assert.ok(dinner.score < 0);
});

test("scoreCandidates applies mealType-keyed cuisineAffinity", () => {
  const candidates = [
    { id: "r1", source: "recipe", name: "Pancakes", cuisine: "american", mealType: "breakfast" },
    { id: "r2", source: "recipe", name: "Burger", cuisine: "american" }
  ];
  const journal = [
    { id: "j1", timestamp: now - 10 * DAY, mealType: "breakfast", name: "Pancakes", source: "recipe", cuisine: "american", rating: 5 },
    { id: "j2", timestamp: now - 9 * DAY, mealType: "dinner", name: "Burger", source: "restaurant", cuisine: "american", rating: 1 }
  ];
  const scored = M.scoreCandidates(candidates, journal, { mealType: "breakfast", now, radiusKm: 10 });
  assert.strictEqual(scored[0].id, "r1");
});

test("validateMeal accepts notes string", () => {
  assert.strictEqual(M.validateMeal({ name: "Pizza", mealType: "dinner", source: "manual", notes: "too salty" }).ok, true);
  assert.strictEqual(M.validateMeal({ name: "Pizza", mealType: "dinner", source: "manual", notes: "" }).ok, true);
});

test("validateMeal rejects non-string notes", () => {
  assert.strictEqual(M.validateMeal({ name: "Pizza", mealType: "dinner", source: "manual", notes: 42 }).ok, false);
});

test("cuisineDrink maps cuisines to drinks", () => {
  assert.strictEqual(M.cuisineDrink("italian"), "Negroni");
  assert.strictEqual(M.cuisineDrink("japanese"), "sake");
  assert.strictEqual(M.cuisineDrink("unknown"), "Aperol Spritz");
  assert.strictEqual(M.cuisineDrink(""), "Aperol Spritz");
});

test("drinkFor enriches with thumbnail from catalog", () => {
  const catalog = [{ id: "drink-1", name: "Negroni", thumb: "http://x/negroni.jpg" }];
  const r = M.drinkFor("italian", catalog);
  assert.strictEqual(r.name, "Negroni");
  assert.strictEqual(r.thumb, "http://x/negroni.jpg");
});

test("drinkFor returns empty thumb when catalog lacks drink", () => {
  const r = M.drinkFor("italian", []);
  assert.strictEqual(r.name, "Negroni");
  assert.strictEqual(r.thumb, "");
});

test("scoreCandidates attaches drink only to restaurant source", () => {
  const candidates = [
    { id: "r1", source: "restaurant", name: "Pizza Place", cuisine: "italian", distanceKm: 1 },
    { id: "r2", source: "recipe", name: "Pancakes", cuisine: "american" }
  ];
  const scored = M.scoreCandidates(candidates, [], { mealType: "dinner", now, radiusKm: 10, drinks: [{ id: "d1", name: "Negroni", thumb: "http://x/n.jpg" }] });
  const rest = scored.find((c) => c.source === "restaurant");
  const rec = scored.find((c) => c.source === "recipe");
  assert.strictEqual(rest.drink, "Negroni");
  assert.strictEqual(rest.drinkThumb, "http://x/n.jpg");
  assert.strictEqual(rec.drink, "");
});

test("generatePlan emits drink on restaurant plan item", () => {
  const candidates = [
    { id: "r1", source: "restaurant", name: "Pizza Place", cuisine: "italian", distanceKm: 1 }
  ];
  const plan = M.generatePlan(candidates, [], { period: "day", now, drinks: [{ id: "d1", name: "Negroni", thumb: "http://x/n.jpg" }] });
  const rest = plan[0].meals.find((m) => m.source === "restaurant");
  assert.ok(rest);
  assert.strictEqual(rest.drink, "Negroni");
});

test("classifyNoteSentiment classifies positive/negative/neutral notes", () => {
  assert.strictEqual(M.classifyNoteSentiment("absolutely delicious, will order again"), 1);
  assert.strictEqual(M.classifyNoteSentiment("too salty and greasy"), -1);
  assert.strictEqual(M.classifyNoteSentiment(""), 0);
  assert.strictEqual(M.classifyNoteSentiment("it was okay"), 0);
});

test("noteScore boosts candidate with positive note and no match returns zero", () => {
  const c = { id: "r1", source: "restaurant", name: "Pizza Place", cuisine: "italian" };
  const journal = [
    { id: "j1", timestamp: now - DAY, mealType: "dinner", name: "Pizza Place", source: "restaurant", restaurantId: "r1", rating: 3, notes: "amazing, best pizza" }
  ];
  const r = M.noteScore(c, journal);
  assert.ok(r.score > 0);
  assert.strictEqual(M.noteScore(c, []).score, 0);
});

test("noteScore down-ranks candidate with negative note", () => {
  const c = { id: "r1", source: "restaurant", name: "Pizza Place", cuisine: "italian" };
  const journal = [
    { id: "j1", timestamp: now - DAY, mealType: "dinner", name: "Pizza Place", source: "restaurant", restaurantId: "r1", rating: 3, notes: "too salty, dry" }
  ];
  assert.ok(M.noteScore(c, journal).score < 0);
});

test("noteScore keys by identity, not cross-contaminating same-named items", () => {
  const c = { id: "r1", source: "restaurant", name: "Pizza Place", cuisine: "italian" };
  const journal = [
    { id: "j1", timestamp: now - DAY, mealType: "dinner", name: "Pizza Place", source: "restaurant", restaurantId: "r2", notes: "delicious" }
  ];
  assert.strictEqual(M.noteScore(c, journal).score, 0);
});

test("mergeConfig preserves base home fields when parsed home is partial", () => {
  const base = { home: { lat: 0, lon: 0, city: "" }, radiusKm: 10, refreshIntervalSec: 3600 };
  const merged = M.mergeConfig(base, { home: { lat: 51.5, lon: -0.1 }, radiusKm: 5 });
  assert.strictEqual(merged.home.lat, 51.5);
  assert.strictEqual(merged.home.lon, -0.1);
  assert.strictEqual(merged.home.city, "");
  assert.strictEqual(merged.radiusKm, 5);
  assert.strictEqual(merged.refreshIntervalSec, 3600);
});

test("mergeConfig replaces top-level values and leaves home when absent", () => {
  const base = { home: { lat: 0, lon: 0, city: "" }, radiusKm: 10 };
  const merged = M.mergeConfig(base, { radiusKm: 20 });
  assert.strictEqual(merged.radiusKm, 20);
  assert.deepStrictEqual(merged.home, { lat: 0, lon: 0, city: "" });
});

test("mergeConfig does not mutate the base object", () => {
  const base = { home: { lat: 0, lon: 0, city: "" }, radiusKm: 10 };
  M.mergeConfig(base, { home: { lat: 1 }, radiusKm: 2 });
  assert.deepStrictEqual(base, { home: { lat: 0, lon: 0, city: "" }, radiusKm: 10 });
});

test("scoreCandidates threads address into the scored object", () => {
  const candidates = [
    { id: "r1", source: "restaurant", name: "Pizza Place", cuisine: "italian", distanceKm: 1, address: "123 Main St" },
    { id: "r2", source: "recipe", name: "Pancakes", cuisine: "american" }
  ];
  const scored = M.scoreCandidates(candidates, [], { mealType: "dinner", now, radiusKm: 10 });
  const rest = scored.find((c) => c.source === "restaurant");
  const rec = scored.find((c) => c.source === "recipe");
  assert.strictEqual(rest.address, "123 Main St");
  assert.strictEqual(rec.address, "");
});

test("generatePlan carries address onto restaurant plan item and empties it for recipe", () => {
  const candidates = [
    { id: "r1", source: "restaurant", name: "Pizza Place", cuisine: "italian", distanceKm: 1, address: "123 Main St" },
    { id: "r2", source: "recipe", name: "Pancakes", cuisine: "american", mealType: "breakfast" }
  ];
  const plan = M.generatePlan(candidates, [], { period: "day", now });
  const rest = plan[0].meals.find((m) => m.source === "restaurant");
  const rec = plan[0].meals.find((m) => m.source === "recipe");
  assert.strictEqual(rest.address, "123 Main St");
  assert.strictEqual(rec.address, "");
});

test("reScorePlan recomputes score and reasons for a matched meal", () => {
  const candidate = { id: "r1", source: "restaurant", name: "Pizza Place", cuisine: "italian", distanceKm: 1 };
  const journal = [{ id: "j1", timestamp: now - DAY, mealType: "dinner", name: "Pizza Place", source: "restaurant", restaurantId: "r1" }];
  const fresh = M.scoreCandidates([candidate], journal, { mealType: "dinner", now, radiusKm: 10 })[0];
  const meal = { id: "r1", source: "restaurant", mealType: "dinner", score: 9999, reasons: ["stale"] };
  const ranked = M.reScorePlan([meal], [candidate], journal, { now, radiusKm: 10 })[0];
  assert.strictEqual(ranked.score, fresh.score);
  assert.deepStrictEqual(ranked.reasons, fresh.reasons);
});

test("reScorePlan leaves unmatched meals untouched", () => {
  const meal = { id: "manual-1", source: "manual", mealType: "lunch", score: 7, reasons: ["manual"] };
  const ranked = M.reScorePlan([meal], [], [], { now, radiusKm: 10 })[0];
  assert.strictEqual(ranked, meal);
  assert.strictEqual(ranked.score, 7);
});

test("reScorePlan re-scores a restored meal after its decline entry is removed", () => {
  const candidate = { id: "r1", source: "restaurant", name: "Pizza Place", cuisine: "italian", distanceKm: 1 };
  const declined = [{ id: "j1", timestamp: now, mealType: "dinner", name: "Pizza Place", source: "restaurant", restaurantId: "r1", declined: true }];
  const scoredWithDecline = M.scoreCandidates([candidate], declined, { mealType: "dinner", now, radiusKm: 10 })[0];
  const meal = { id: "r1", source: "restaurant", mealType: "dinner", score: scoredWithDecline.score, reasons: scoredWithDecline.reasons };
  const ranked = M.reScorePlan([meal], [candidate], [], { now, radiusKm: 10 })[0];
  assert.ok(ranked.score > scoredWithDecline.score);
  assert.strictEqual(ranked.reasons.some((r) => r.indexOf("declined") !== -1), false);
});
