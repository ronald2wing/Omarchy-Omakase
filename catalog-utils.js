// catalog-utils.js — Omakase catalog pure logic extracted from BarWidget.qml
// Dual-use: Node.js (tests) and QML (import "catalog-utils.js" as CatalogUtils)
//
// Every function here is pure: inputs are passed explicitly (no root.* reads),
// so they are unit-testable under Node and reusable verbatim from QML bindings
// without tracking issues. Side-effecting orchestration stays in BarWidget.qml.

// Canonical key for the per-coordinate distance cache. Producer (the distance
// build step) and every consumer must use this exact format so a lookup hits
// the staged value instead of recomputing a haversine.
function coordKey(lat, lon) { return (lat || 0) + "|" + (lon || 0); }

// Single sort comparator over already-extracted scalar values. `key` fixes the
// intrinsic direction (rating descends, everything else ascends); `reversed`
// flips it. Callers pass extracted values so each key's accessor stays verbatim
// at the call site.
function compareSortValues(first, second, key, reversed) {
  var delta = (key === "rating") ? (second - first) : (first - second);
  return reversed ? -delta : delta;
}

// Decorate-sort-undecorate: resolve each item's sort value once up front
// (O(n)) instead of twice per comparison (O(n log n)), sort on the scalars,
// then strip the decoration. `decorate` maps an item to its sort value;
// `extract` maps the decorated record back to the original item.
function decoratedSort(items, decorate, extract, key, reversed) {
  var decorated = items.map(function(item) {
    return { item: item, value: decorate(item) };
  });
  decorated.sort(function(first, second) {
    return compareSortValues(first.value, second.value, key, reversed);
  });
  return decorated.map(function(record) { return extract(record.item); });
}

// Turn a value→count map into [{ key, name, count }] sorted alphabetically,
// with `nearestValue` moved to the front when it was counted.
function aggregateList(counts, nearestValue) {
  var list = [];
  for (var fieldValue in counts) list.push({ key: fieldValue, name: fieldValue, count: counts[fieldValue] });
  list.sort(function(firstValue, secondValue) { return firstValue.name.localeCompare(secondValue.name); });
  if (nearestValue && counts[nearestValue]) {
    for (var index = 0; index < list.length; index++) {
      if (list[index].key === nearestValue) {
        var homeValue = list.splice(index, 1)[0];
        list.unshift(homeValue);
        break;
      }
    }
  }
  return list;
}

// Map a city key to its display name: "los-angeles" -> "Los Angeles". The
// cityMeta table handles known keys first; this title-cases the slug as the
// fallback for unknown keys.
function displayNameFor(key) {
  return (key || "").replace(/-/g, ' ').replace(/\b\w/g, function (ch) { return ch.toUpperCase(); });
}

// Lightweight search filter — O(n) string matching only, no cache involvement.
// `cityNames` is the precomputed name map (neighborhoodSearchIndex.names) so a
// matched spot's city label resolves in O(1) instead of re-running the display
// lookup per matched spot.
function applySearchFilter(spots, searchText, cityNames) {
  if (!spots || !spots.length) return spots;
  var query = (searchText || "").toLowerCase();
  if (!query) return spots;
  return spots.filter(function (spot) {
    return (spot.name || "").toLowerCase().indexOf(query) >= 0 ||
           (spot.neighborhood || "").toLowerCase().indexOf(query) >= 0 ||
           (spot._cityKey ? (cityNames[spot._cityKey] || "").toLowerCase().indexOf(query) >= 0 : false);
  });
}

if (typeof module !== "undefined") {
  module.exports = {
    coordKey,
    compareSortValues,
    decoratedSort,
    aggregateList,
    displayNameFor,
    applySearchFilter
  };
}
