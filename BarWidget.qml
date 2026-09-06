import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "spot-utils.js" as SpotUtils
import "catalog-utils.js" as CatalogUtils
import "components"

Panel {
  id: root
  moduleName: "omakase"
  manageIpc: false

  // ---- Panel state ----
  property var catalog: ({ cities: [], spotsByCity: {}, homeLat: 0, homeLon: 0 })
  property var journal: []
  property string cityKey: ""
  property string searchText: ""
  // Debounced copy of searchText that the card-list search chain reads. Typing
  // updates searchText instantly (the field never lags), but the expensive
  // full-catalog rank runs only when searchQuery lands, searchDebounceMs after
  // the last keystroke. Clearing the field flushes immediately
  // (onSearchTextChanged). The Timer handler assigns searchQuery imperatively,
  // never from inside a binding, so it stays clear of the declarative cache model.
  property string searchQuery: ""
  // Dismissal flag for the search-suggestions dropdown (city/neighborhood/state
  // matches). A plain bool, NOT readonly — a readonly binding freezes at
  // creation. Set true by Escape, the dropdown's query row, or a card click;
  // reset to false on every searchText change so typing re-opens the
  // suggestions. Written only from handlers, never inside a binding.
  property bool searchSuggestionsDismissed: false
  readonly property int searchDebounceMs: 150
  property string kindFilter: "all"
  property string sortBy: "distance"
  property bool sortReversed: false
  property string journalQuery: ""
  property string wishlistQuery: ""
  property string tab: "explore"
  property bool unratedOnly: false
  property string neighborhood: ""
  property string stateFilter: ""  // Yelp state filter (e.g. "GA"); "" = all
  property string countryFilter: ""  // country filter (e.g. "US"); "" = all
  property int radius: 0  // 0 = off; the km steps live in CatalogUtils.RADIUS_STEPS
  // Which filter dropdown is open ("" = none). One string replaces the four
  // per-filter booleans so the FilterSheet rows share a single toggle helper.
  property string openDropdown: ""
  // Whether the floating Filters sheet is open. The sheet holds the location
  // scopes; the primary row stays visible.
  property bool openSheet: false
  // True when any filter owned by the sheet is set. Drives the Filters button's
  // active state. The Nearby radius lives in the primary row now, so it is not a
  // sheet filter.
  readonly property bool hasSheetFilters: root.cityKey !== "" || root.stateFilter !== "" || root.countryFilter !== "" || root.neighborhood !== ""
  // True when any location/radius filter is set, wherever its control lives.
  // Drives the active-filters summary line's visibility (the `Within N km` token
  // must still surface when only the radius is set).
  readonly property bool hasActiveFilters: root.hasSheetFilters || root.radius > 0
  // Collapsing the sheet also drops any open option list, so reopening it never
  // shows a stale dropdown.
  onOpenSheetChanged: if (!root.openSheet) root.openDropdown = ""
  property var saved: []
  // name -> true set rebuilt whenever `saved` changes, so isSaved() is O(1)
  // instead of an O(saved) indexOf scan per card. Null-prototype so a saved
  // name like "constructor" can't collide with Object.prototype.
  property var savedSet: Object.create(null)
  property bool spotlight: false
  property var spotlightEntry: null
  property var expandedSpotName: null  // spot name that is expanded, or null
  // Two-level expand: the card row opens a compact editor (stars + Edit pill);
  // `editorOpen` reveals the full form (action pills, notes, Save/Update/Remove).
  property bool editorOpen: false
  property int editStars: 0
  property string editNotes: ""
  // Lazy loading: only render `visibleCount` cards at a time.
  // Batch size is 88 by design: a Japanese lucky number (八十八 / 末広がり).
  readonly property int pageSize: 88
  property int visibleCount: pageSize
  // Guards the incremental prefetch: set while a fill is stepping through
  // event-loop turns so a storm of contentY events can't start a second fill.
  property bool prefetching: false
  // Neighborhood chip strip cap: cities whose "neighborhoods" are really
  // address fragments (Nagoya chōme) produce hundreds of chips that wall off
  // the panel, so the strip hides and falls back to the dropdown.
  readonly property int maxNeighborhoodChips: 12
  // Show the neighborhood chip strip only when a city is selected and its
  // neighborhood list is small enough to render as chips.
  readonly property bool showNeighborhoodChips: root.cityKey !== "" && root.neighborhoodOptions.length > 0 && root.neighborhoodOptions.length <= root.maxNeighborhoodChips
  // Whether the selected city has neighborhoods worth filtering by. Gates the
  // Neighborhood pill (FilterBar) and dropdown (FilterPanel): a city with no
  // neighborhoods (or none selected) never surfaces a dead neighborhood filter.
  readonly property bool hasNeighborhoods: root.cityKey !== "" && root.neighborhoodOptions.length > 0
  // Back-to-top FAB appears as soon as the list is really scrolled; a small
  // dead zone absorbs sub-pixel jitter without hiding the arrow on a real scroll.
  readonly property real backToTopThreshold: Style.space(16)
  // Cap on the (non-spotlight) panel height; the Flickable scrolls past it.
  readonly property real maxPanelHeight: Style.space(640)
  // Pinned header above the scroller: top padding + the pinned column's own
  // height + gap to the content below. The tab chips + Surprise Me pill always
  // live here; on Explore the search field and the FilterBar primary row join
  // them, so search/filter stay reachable while the list scrolls. The column's
  // own top padding is 0 (this header owns it).
  //
  // The height is read from the pinned column's implicitHeight rather than a
  // fixed constant: the FilterBar's active-filter summary line is variable
  // height, and the search field + FilterBar are hidden on Wishlist/Journal.
  // pinnedColumn's children never depend on this property, so there is no
  // binding cycle.
  readonly property real pinnedHeaderHeight: root.spotlight ? 0 : (Style.space(16) + pinnedColumn.implicitHeight + Style.space(10))
  // Bounded height for the Explore ListView: the panel cap minus the card's
  // real vertical chrome (popup padding + border, from KeyboardPanel) and the
  // pinned header. The search field + FilterBar are pinned (not in the ListView
  // header), so they are subtracted here; only the CityHeader + neighborhood
  // chips remain in the ListView header and consume viewport space. The list
  // extends to the panel bottom; the back-to-top FAB floats over it.
  readonly property real exploreListHeight: Math.max(Style.space(200), root.maxPanelHeight - panel.verticalContentInset - root.pinnedHeaderHeight)
  // Height of the ACTIVE tab's content, excluding the column's own padding.
  // The content Column's implicitHeight sums ALL three tabs (a Column lays out
  // and measures hidden children too), so it always sized the panel to the
  // tallest tab — Explore's fixed list height — leaving Wishlist/Journal with
  // dead space. Reading the active tab instead lets the panel hug its content.
  // Explore keeps its fixed list height (the ListView scrolls internally);
  // Wishlist/Journal report their real content height (their inner ListView is
  // height: contentHeight), capped by maxPanelHeight below.
  readonly property real activeTabHeight: {
    if (root.tab === "wishlist") return wishlistTab.implicitHeight
    if (root.tab === "journal") return journalTab.implicitHeight
    return root.exploreListHeight
  }
  // How long the Copy pill's "Copied!" feedback shows before reverting.
  readonly property int copyFeedbackMs: 1500

  // ---- Theme-derived colors ----
  readonly property color foregroundColor: root.bar ? root.bar.foreground : "#fff"
  readonly property color accentColor: (root.bar && root.bar.activeColor) ? root.bar.activeColor : "#44aaff"
  readonly property color accentTextColor: "#fff"
  readonly property color secondaryColor: Qt.darker(root.foregroundColor, 1.6)
  readonly property color cardBackground: root.foregroundAlpha(0.06)
  readonly property color cardHoverBackground: root.foregroundAlpha(0.12)
  readonly property color inputBackground: root.foregroundAlpha(0.08)
  readonly property color accentTint: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.12)
  readonly property color dangerColor: Qt.rgba(1, 0.3, 0.3, 1)
  readonly property color dangerBorder: Qt.rgba(1, 0.3, 0.3, 0.6)
  readonly property color dangerFaint: Qt.rgba(1, 0.3, 0.3, 0.08)
  // Opaque popup surface (tooltips, dropdowns, the filter sheet): `cardBackground`
  // is the foreground at 0.06 alpha, so a translucent tint would let content
  // behind show through. `Color.popups.background` carries the theme's
  // `popups.background-alpha`, which a theme may set below 1.0; rebuilding from
  // the RGB components forces alpha 1.0.
  readonly property color popupBackground: Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, 1.0)

  // Foreground-derived tint at a given alpha — single source for the many
  // semi-transparent card/border/dropdown colors.
  function foregroundAlpha(a) { return Qt.rgba(root.foregroundColor.r, root.foregroundColor.g, root.foregroundColor.b, a) }

  readonly property string repoUrl: "https://github.com/ronald2wing/Omarchy-Omakase"

  readonly property real collapsedCardHeight: Style.space(76)
  // Scroll bucket for image gating (see flick.imageWindowStart). One bucket is
  // a couple of card heights, so the image window advances in coarse steps and
  // the per-card image binding does not re-run on every scroll frame. Kept
  // below `SpotCard.imagePreloadMargin` (300px) so a card is always loaded
  // before it reaches the viewport even at the end of a bucket.
  readonly property real imageBucketHeight: Style.space(200)
  // Expanded-card height fallback used before the Loader has measured its item
  // (the RatingEditor); the Loader's item implicitHeight replaces it once known.
  readonly property real expandedFallbackHeight: Style.space(260)

  // Convenience — home location or 0 if unset.
  readonly property real homeLat: root.catalog.homeLat || 0
  readonly property real homeLon: root.catalog.homeLon || 0

  // ---- Derived counts ----
  readonly property int journalCount: root.ratedEntries.length

  // Total spot count across all cities, memoized per catalog version so the
  // placeholder does not rescan every city's array on each catalog change.
  readonly property int totalSpotCount: {
    root.catalogVersion;
    var spotCount = 0;
    var spotsByCity = (root.catalog && root.catalog.spotsByCity) ? root.catalog.spotsByCity : {};
    for (var key in spotsByCity) spotCount += spotsByCity[key].length;
    return spotCount;
  }

  readonly property string searchPlaceholder: {
    return "Search " + CatalogUtils.spotCountLabel(root.totalSpotCount) + "…";
  }

  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }

  implicitWidth: barStrip.implicitWidth
  implicitHeight: barStrip.implicitHeight

  Row {
    id: barStrip
    spacing: Style.space(2)

    BarIconButton {
      id: barButton
      bar: root.bar
      iconComponent: Component {
        Image {
          anchors.centerIn: parent
          source: Qt.resolvedUrl("icons/sushi.svg")
          width: 18; height: 18
          sourceSize.width: 18; sourceSize.height: 18
          fillMode: Image.PreserveAspectFit
        }
      }
      tooltipText: "Omakase — worldwide sushi directory"
      onPressed: function(b) {
        if (b === Qt.LeftButton) root.toggle();
      }
    }
  }

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omakase/state.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadCatalog(text())
    onLoadFailed: root.loadCatalog("")
    onFileChanged: reload()
  }

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omakase/journal.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadJournal(text())
    onLoadFailed: root.loadJournal("")
    onFileChanged: reload()
  }

  FileView {
    id: savedFile
    // Vocabulary split: `saved`/`save`/`isSaved`/`toggleSaved`/`savedSet` is the
    // heart *action* and its on/off state, while `wishlist`/`Wishlist`/
    // `wishlist.json` is the *collection* the user browses. The split is
    // intentional and matches the UI copy — do not "unify" it (and do not rename
    // the on-disk file).
    path: Quickshell.env("HOME") + "/.local/state/omakase/wishlist.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadSaved(text())
    onLoadFailed: root.loadSaved("")
    onFileChanged: reload()
  }

  // ---- Data loading ----
  // Shared chunked-walk scaffold (components/ChunkedWalk.qml): the catalog
  // stamp, spot index, and distance build below each express one bounded walk
  // as a step callback + done callback; the scaffold owns the token supersede
  // check, the chunk budget, the Qt.callLater rescheduling, and the atomic
  // publish-at-completion.
  ChunkedWalk { id: chunkWalk }

  // Restartable search debounce timer. Each non-empty searchText change
  // restarts it; onTriggered copies searchText -> searchQuery so the declarative
  // searchedSpots chain (which lists searchQuery as a tracked dep) re-runs once
  // per pause, not once per keystroke. Clearing the field stops it and flushes
  // an empty searchQuery immediately.
  Timer {
    id: searchDebounceTimer
    interval: root.searchDebounceMs
    repeat: false
    onTriggered: root.searchQuery = root.searchText
  }

  // Stamp each spot with its city key ONCE at load so the filter pass never
  // mutates the shared catalog objects (which spotsByName and other readers
  // hold by reference). _cityKey is a stable field thereafter. Stamping ~5k spots with ~10 SpotUtils formatters froze the UI
  // for several frames on startup and every home move, so the loop runs through
  // runChunked in catalogChunkSize-spot slices; root.catalog is reassigned only
  // once stamping completes, so readers never observe a partially stamped
  // catalog, and a superseded load is discarded by token (a newer state.json
  // load landed).
  readonly property int catalogChunkSize: 400
  property int catalogToken: 0

  function loadCatalog(raw) {
    root.catalogToken++;
    var catalog = SpotUtils.parseJson(raw, {});
    var spotsByCity = catalog.spotsByCity || {};
    // Iterate the spotsByCity keys (not catalog.cities) to preserve the exact
    // set and order of the catalog.
    var ctx = { city: 0, spot: 0, cityKeys: Object.keys(spotsByCity), spotsByCity: spotsByCity, catalog: catalog };
    chunkWalk.runSpotWalk({
      getToken: function () { return root.catalogToken; },
      chunkSize: root.catalogChunkSize,
      ctx: ctx,
      cities: function (ctx) { return ctx.cityKeys; },
      onSpot: function (ctx, spot, cityKey) {
        // Stamp the spot's derived display fields once at load (shared helper
        // in spot-utils, unit-tested) so SpotCard reads a field instead of
        // re-running ~10 formatters per delegate bind.
        SpotUtils.stampDerivedFields(spot, cityKey);
      },
      done: function (ctx) {
        root.catalog = ctx.catalog;
      }
    }, root.catalogToken);
  }
  function loadJournal(raw) { root.journal = SpotUtils.parseJson(raw, []); }
  function loadSaved(raw) { root.saved = SpotUtils.parseJson(raw, []); }

  // ---- Data access ----

  // All spots for a city (seed + user spots). Rated spots stay visible.
  // Returns the catalog's own array — callers only read/filter it (filter/map
  // return new arrays), so no defensive copy is needed.
  function spotsForCity(city) {
    return (root.catalog.spotsByCity && root.catalog.spotsByCity[city]) ? root.catalog.spotsByCity[city] : [];
  }

  // Flat list of every catalog spot (cities then spots, catalog order), shared
  // by computeFilteredSpots (multi-city view) and the location aggregates. A
  // function call (not a binding) so `catalog` stays an untracked
  // dependency of its callers — they gate on distanceVersion, not catalogVersion,
  // so they never re-run against the empty distance map installed at the start
  // of a catalog/home move.
  function flattenSpots() {
    var spots = [];
    var cities = root.catalog.cities || [];
    for (var cityIndex = 0; cityIndex < cities.length; cityIndex++) {
      var citySpots = spotsForCity(cities[cityIndex]);
      for (var spotIndex = 0; spotIndex < citySpots.length; spotIndex++) {
        spots.push(citySpots[spotIndex]);
      }
    }
    return spots;
  }

  // Average rating for a spot from the precomputed ratingsBySpot map, or null.
  function averageRatingFor(spotName) {
    var entry = root.ratingsBySpot[spotName];
    if (!entry || !entry.count) return null;
    return Math.round(entry.total / entry.count * 10) / 10;
  }

  // Most recent journal entry for a spot. O(1) lookup into journalByName,
  // rebuilt whenever the journal changes.
  function latestJournalFor(name) {
    return root.journalByName[name] || null;
  }

  // Rated journal entries. Declarative so the binding engine owns the
  // recompute: no getter writes a property during a binding evaluation.
  property var ratedEntries: {
    root.journal;
    return (root.journal || []).filter(function(entry) { return !!entry.rating; });
  }

  // Precomputed per-name rating aggregates. averageRatingFor() reads this map instead
  // of scanning the journal on every delegate render. Rebuilt whenever journal
  // changes to avoid the readonly-freeze QML gotcha (function-call bindings don't
  // re-evaluate).
  // All three are keyed by spot name, so they are null-prototype: a spot named
  // "constructor"/"toString"/"__proto__" must not resolve to an inherited
  // Object.prototype member (which would poison the aggregate or the index).
  property var ratingsBySpot: Object.create(null)
  property var journalByName: Object.create(null)
  // name -> [ { spot, cityKey } ] across all cities, in catalog order (cities
  // then spots). Rebuilt on every catalog change so locateSpot() resolves a name
  // in O(1) instead of scanning every city's spots.
  property var spotsByName: Object.create(null)
  // Chunked rebuild state for spotsByName. Building the map synchronously froze
  // the UI for several frames on startup and every home move (the catalog is a
  // ~1.9 MB parse producing ~5k spots), so the build runs through runChunked in
  // spotIndexChunkSize-spot slices. The map is swapped in atomically only when
  // complete, so spotsByName is never observed partially built; a superseded
  // build is discarded when its token no longer matches (a newer catalog change
  // landed).
  readonly property int spotIndexChunkSize: 400
  property int spotIndexToken: 0

  function refreshRatings() {
    var ratingsMap = Object.create(null);
    var journalMap = Object.create(null);
    // Iterate `journal` directly, NOT `ratedEntries`: `ratedEntries` is a
    // declarative binding over `journal`, and this function runs synchronously
    // from `onJournalChanged` — before the engine re-evaluates `ratedEntries`.
    // Reading it here returns the stale (pre-write) array, leaving ratingsBySpot
    // empty and breaking the Unrated filter (averageRatingFor always null).
    var journal = root.journal || [];
    for (var i = 0; i < journal.length; i++) {
      var entry = journal[i];
      if (!entry.rating) continue;
      var key = entry.name;
      if (!ratingsMap[key]) ratingsMap[key] = { total: 0, count: 0 };
      ratingsMap[key].total += entry.rating;
      ratingsMap[key].count++;
      // Entries are oldest-first, so the last write wins: the map keeps the most
      // recent rated entry per name.
      journalMap[key] = entry;
    }
    root.ratingsBySpot = ratingsMap;
    root.journalByName = journalMap;
  }

  function rebuildCatalogIndex() {
    root.spotIndexToken++;
    // The catalog is snapshotted once per build (not re-read per slice); a newer
    // catalog change bumps the token and supersedes any in-flight build before
    // it can publish from this stale snapshot. One walk builds both the
    // name→entries index and the catalog search index, so the catalog is
    // scanned once instead of twice.
    var ctx = {
      city: 0,
      spot: 0,
      cities: root.catalog.cities || [],
      spotsByCity: root.catalog.spotsByCity || {},
      map: Object.create(null),
      ordered: [],
      names: Object.create(null),
      foldedNames: Object.create(null),
      foldedKeys: Object.create(null),
      counts: Object.create(null),
      byCity: Object.create(null),
      nbCounts: Object.create(null),
      nbOrder: [],
      nbRep: Object.create(null)
    };
    chunkWalk.runSpotWalk({
      getToken: function () { return root.spotIndexToken; },
      chunkSize: root.spotIndexChunkSize,
      ctx: ctx,
      cities: function (ctx) { return ctx.cities; },
      onCityDone: function (ctx, cityKey) { root.recordCityNeighborhoods(ctx, cityKey); },
      onSpot: function (ctx, spot, cityKey) {
        // Precompute the folded search blob once per spot so the per-keystroke
        // rank path (rankSpots -> matchClass) does zero allocation. The blob
        // folds name + neighborhood only — the card-list rank does not match the
        // city label (city scoping lives in the search dropdown). Correctness
        // never depends on _folded: rankSpots falls back to folding the raw spot
        // when the field is absent.
        spot._folded = CatalogUtils.foldSpot(spot);
        var name = spot.name;
        if (name !== undefined && name !== null) {
          // Key by normalized name (trim + lowercase) so locateSpot resolves a
          // journal/wishlist name like "Omi Omakase" to catalog "OMI OMAKASE".
          var key = SpotUtils.normalizeName(name);
          if (!ctx.map[key]) ctx.map[key] = [];
          ctx.map[key].push({ spot: spot, cityKey: cityKey });
        }
        var neighborhood = (spot.neighborhood || "").trim();
        if (neighborhood) {
          if (ctx.nbCounts[neighborhood] === undefined) ctx.nbOrder.push(neighborhood);
          ctx.nbCounts[neighborhood] = (ctx.nbCounts[neighborhood] || 0) + 1;
          // First spot with coordinates becomes the neighborhood's representative
          // for its own distance (mirrors cityDistanceKm's first-spot fallback).
          if (ctx.nbRep[neighborhood] === undefined && spot.lat && spot.lon) {
            ctx.nbRep[neighborhood] = { lat: spot.lat, lon: spot.lon };
          }
        }
      },
      done: function (ctx) {
        // Both maps are reassigned whole, so declarative readers observe the
        // fresh index on their own: sortedJournal/filteredWishlist track
        // spotsByName, and the search dropdown tracks searchIndex
        // (its searchMatches() reads are otherwise untracked through the
        // function call).
        root.spotsByName = ctx.map;
        root.searchIndex = { cities: ctx.ordered, names: ctx.names, counts: ctx.counts, byCity: ctx.byCity, foldedNames: ctx.foldedNames, foldedKeys: ctx.foldedKeys };
      }
    }, root.spotIndexToken);
  }

  function refreshSavedSet() {
    var set = Object.create(null);
    for (var i = 0; i < root.saved.length; i++) set[root.saved[i]] = true;
    root.savedSet = set;
  }

  Component.onCompleted: { root.refreshRatings(); root.buildCityLabelMap(); root.refreshSavedSet() }

  // Resolve a spot by name. A non-empty city match wins first; otherwise the
  // first city (in catalog order) holding the name is returned — an O(1) read
  // from spotsByName.
  // Returns { spot, cityKey } or null when no city contains the spot.
  function locateSpot(name, city) {
    var key = SpotUtils.normalizeName(name);
    if (!key) return null;
    var entries = root.spotsByName[key];
    if (!entries || !entries.length) return null;
    var cityKey = city || "";
    if (cityKey) {
      for (var index = 0; index < entries.length; index++) {
        if (entries[index].cityKey === cityKey) return entries[index];
      }
    }
    return entries[0];
  }

  function isSaved(spotName) {
    return !!root.savedSet[spotName];
  }

  // ---- Formatting ----

  // Map a city key to its display string: "nyc" -> "New York City". Both the
  // eager map build and the per-lookup fallback route through
  // CatalogUtils.cityLabelFor (the CITY_META name for known keys, else a
  // title-cased slug). The city label is the pure city name — country and state
  // are rendered separately in the meta row.
  //
  // `cityLabelMap` is the memoization cache for the catalog/journal city keys,
  // rebuilt eagerly from onCatalogChanged/onJournalChanged (never written from
  // inside cityLabel, which is called from card bindings). Unknown keys fall
  // back to a pure computation so a binding read never mutates state.
  property var cityLabelMap: Object.create(null)
  function buildCityLabelMap() {
    var map = Object.create(null);
    var cities = root.catalog.cities || [];
    for (var cityIndex = 0; cityIndex < cities.length; cityIndex++) {
      if (map[cities[cityIndex]] === undefined) map[cities[cityIndex]] = CatalogUtils.cityLabelFor(cities[cityIndex]);
    }
    var journal = root.journal || [];
    for (var entryIndex = 0; entryIndex < journal.length; entryIndex++) {
      var city = journal[entryIndex].city;
      if (city && map[city] === undefined) map[city] = CatalogUtils.cityLabelFor(city);
    }
    root.cityLabelMap = map;
  }
  function cityLabel(key) {
    var cached = root.cityLabelMap[key];
    if (cached !== undefined) return cached;
    return CatalogUtils.cityLabelFor(key);
  }

  // Human-readable summary of the active filters (city, type, unratedOnly, sort,
  // radius, neighborhood, search). Shared by the spotlight header and the
  // Surprise Me FAB tooltip so both describe the same current-filter state.
  // Declarative so the binding engine owns the recompute; the dependency list is
  // explicit because reads inside the compute function are not tracked.
  // cityLabelMap is listed because cityLabel() reads it directly, and its
  // reassignment (catalog/journal change) is not tracked through the function call.
  property string filterDescription: {
    root.cityKey;
    root.kindFilter;
    root.unratedOnly;
    root.sortBy;
    root.radius;
    root.neighborhood;
    root.cityLabelMap;
    return CatalogUtils.filterDescription(
      root.cityKey ? root.cityLabel(root.cityKey) : "",
      root.kindFilter,
      root.unratedOnly,
      root.sortBy,
      root.radius,
      root.neighborhood
    );
  }

  // Raw distance (km) from home to a city center. Uses the CITY_META center
  // (via CatalogUtils.cityMetaFor) when available, else falls back to the first
  // spot's coords (Yelp cities aren't in CITY_META). Returns Infinity when no
  // home or no coords.
  function cityDistanceKm(cityKey) {
    if (!root.homeLat || !root.homeLon) return Infinity;
    var entry = CatalogUtils.cityMetaFor(cityKey);
    if (entry && entry.lat && entry.lon) return SpotUtils.haversine(root.homeLat, root.homeLon, entry.lat, entry.lon);
    var spots = root.catalog.spotsByCity && root.catalog.spotsByCity[cityKey] ? root.catalog.spotsByCity[cityKey] : [];
    for (var index = 0; index < spots.length; index++) {
      if (spots[index].lat && spots[index].lon) {
        return SpotUtils.haversine(root.homeLat, root.homeLon, spots[index].lat, spots[index].lon);
      }
    }
    return Infinity;
  }

  // Formatted distance label for a city key ("" when unknown/geo-less).
  // Extracted so the pure cityFilterItems builder consumes a pre-formatted
  // string instead of importing spot-utils itself.
  function cityDistanceLabel(key) {
    var distanceKm = root.cityDistanceKm(key);
    return isFinite(distanceKm) ? SpotUtils.formatDistance(distanceKm) : "";
  }

  // Per-coordinate haversine cache keyed on catalogVersion. Distances depend
  // only on home + a spot's lat/lon, so they are computed once per catalog/home
  // change and reused across filter toggles instead of recomputed on every
  // filteredSpots rebuild. Keyed by coordinates (not object identity) since
  // the distance is a pure function of them: a key collision can only cause a
  // redundant computation, never a wrong value.
  //
  // The build is chunked (distanceChunkSize spots per event-loop turn, yielding
  // via Qt.callLater) because ~5k synchronous haversines froze the UI on
  // startup and every home move. The staged map is published atomically to
  // distanceByCoords only when complete, and distanceVersion is bumped in the
  // same turn; declarative readers track distanceVersion (not distanceByCoords)
  // so they never observe a partial map. A superseded build is discarded when
  // its token no longer matches (a newer catalog/home change landed).
  property var distanceByCoords: Object.create(null)
  property int distanceVersion: 0
  readonly property int distanceChunkSize: 400
  property int distanceToken: 0

  // Start a fresh build. distanceByCoords is cleared first so a home move can
  // never leave the previous home's distances readable: function-call readers
  // (spotDistanceLabel, isWithinRadius, the location-aggregates distance accessor,
  // the distance sort) fall back to a fresh haversine on a miss, so an empty
  // map during the build is correct, just uncached. Declarative readers do not
  // track distanceByCoords, so the clear does not re-run them.
  function refreshDistanceCache() {
    root.distanceToken++;
    root.distanceByCoords = Object.create(null);
    // The catalog and staged map are snapshotted once per build; a newer
    // catalog/home change bumps the token and supersedes any in-flight build
    // before it can publish a map for a stale home.
    var ctx = {
      city: 0,
      spot: 0,
      cities: root.catalog.cities || [],
      spotsByCity: root.catalog.spotsByCity || {},
      staged: Object.create(null)
    };
    chunkWalk.runSpotWalk({
      getToken: function () { return root.distanceToken; },
      chunkSize: root.distanceChunkSize,
      ctx: ctx,
      cities: function (ctx) { return ctx.cities; },
      onSpot: function (ctx, spot, cityKey) {
        var lat = spot.lat || 0;
        var lon = spot.lon || 0;
        var key = CatalogUtils.coordKey(lat, lon);
        if (ctx.staged[key] === undefined) ctx.staged[key] = SpotUtils.haversine(root.homeLat, root.homeLon, lat, lon);
      },
      done: function (ctx) {
        root.distanceByCoords = ctx.staged;
        root.distanceVersion++;
      }
    }, root.distanceToken);
  }

  // Shared per-coordinate distance lookup: a cache hit when present, else a
  // fresh haversine, else `undefined` when home or the spot's coordinates are
  // missing. Each caller applies its own sentinel for the missing case
  // ("" / false / Infinity / undefined), so the `undefined` is deliberately left
  // as-is rather than normalized to 0 or Infinity here.
  function rawDistanceKm(spot) {
    if (!spot || !spot.lat || !spot.lon || !root.homeLat || !root.homeLon) return undefined;
    var cached = root.distanceByCoords[CatalogUtils.coordKey(spot.lat, spot.lon)];
    if (cached !== undefined) return cached;
    return SpotUtils.haversine(root.homeLat, root.homeLon, spot.lat, spot.lon);
  }

  // Distance from home to a neighborhood's representative spot (the first spot
  // with coordinates in that neighborhood, recorded by the index walk), Infinity
  // when the neighborhood has no located spot or home is unknown. Mirrors
  // cityDistanceKm's first-spot fallback; reuses rawDistanceKm so the
  // per-coordinate cache serves the lookup.
  function neighborhoodDistanceKm(nb) {
    if (!nb || !nb.lat || !nb.lon) return Infinity;
    var km = rawDistanceKm({ lat: nb.lat, lon: nb.lon });
    return km === undefined ? Infinity : km;
  }

  // Distance from home to a spot, formatted for display; empty when unknown.
  function spotDistanceLabel(spot) {
    var km = rawDistanceKm(spot);
    return km === undefined ? "" : SpotUtils.formatDistance(km);
  }

  // True when `root.radius` is active (>0) and the spot falls within it.
  function isWithinRadius(spot) {
    var km = rawDistanceKm(spot);
    return km === undefined ? false : km <= root.radius;
  }

  // Whether a spot's neighborhood matches the active neighborhood filter.
  // `neighborhoodFolded` is the already-lowercased filter value, hoisted out of
  // the per-spot pass by the caller (it is constant for the whole pass).
  function matchesNeighborhood(spot, neighborhoodFolded) {
    if (!neighborhoodFolded) return true;
    return spot && (spot.neighborhood || "").toLowerCase() === neighborhoodFolded;
  }

  // ---- Filtering ----

  // Shared global filter predicates (kind, city, radius, neighborhood,
  // unratedOnly) for a single spot. `spot` may be null (a name no longer in the
  // catalog); `cityKey` is the spot's city key ("" when unknown); `opts` toggles
  // per-caller predicates:
  //   city         — filter by root.cityKey against cityKey
  //   unratedOnly  — hide spots that already have a rated journal entry
  //   name         — the name checked against the rating map (defaults to spot.name)
  //   neighborhoodFolded — pre-lowercased root.neighborhood (hoisted per pass)
  function passesFilters(spot, cityKey, opts) {
    opts = opts || {};
    if (root.kindFilter !== "all" && (!spot || spot._spotKind !== root.kindFilter)) return false;
    if (opts.city && root.cityKey && cityKey !== root.cityKey) return false;
    if (root.radius > 0 && !root.isWithinRadius(spot)) return false;
    if (!root.matchesNeighborhood(spot, opts.neighborhoodFolded)) return false;
    if (opts.unratedOnly && root.unratedOnly && root.averageRatingFor(opts.name || (spot ? spot.name : "")) !== null) return false;
    return true;
  }

  // City/neighborhood matches for the search dropdown. Returns
  // { type: "city", key, name, count } or { type: "neighborhood", key, name, cityKey, cityName, count }.
  // The per-city neighborhood tally is independent of the query, so it is
  // precomputed once per catalog version (searchIndex) and this
  // function only filters the cached city names + neighborhood records + the
  // cached states — no per-keystroke rescan of all spots.
  function searchMatches(query) {
    var term = SpotUtils.foldSearchText(query);
    if (!term) return [];
    // Ultra-short queries get no loose matching: below 2 characters the match
    // is prefix-only (the entry starts with the term), so a single character
    // opens the dropdown without drowning it in substring noise. At 2+
    // characters the match is the substring scan used before.
    var prefixOnly = term.length < 2;
    var results = [];
    var index = root.searchIndex;
    for (var cityIndex = 0; cityIndex < index.cities.length; cityIndex++) {
      var cityKey = index.cities[cityIndex];
      var cityName = index.names[cityKey];
      if (searchHitMatches(index.foldedNames[cityKey], term, prefixOnly) || searchHitMatches(index.foldedKeys[cityKey], term, prefixOnly)) {
        results.push({ type: "city", key: cityKey, name: cityName, count: index.counts[cityKey], distance: root.cityDistanceKm(cityKey) });
      }
      var records = index.byCity[cityKey];
      for (var nbIdx = 0; nbIdx < records.length; nbIdx++) {
        var nb = records[nbIdx];
        if (searchHitMatches(nb.foldedName, term, prefixOnly)) {
          results.push({ type: "neighborhood", key: nb.key, name: nb.name, cityKey: nb.cityKey, cityName: nb.cityName, count: nb.count, distance: root.neighborhoodDistanceKm(nb) });
        }
      }
    }
    // State match (Yelp "state" field, e.g. "NY"): one result per state,
    // aggregated across all cities so "NY" appears once, not per city. A state
    // matches its 2-letter code OR its full name (via CatalogUtils.stateNameFor),
    // folded like the rest of the search path, so a name-bearing query ("new")
    // reaches New Jersey / New York / New Mexico / New Hampshire — the raw code
    // alone could never match. The row is labelled with the readable full name;
    // its `key` stays the code for selectState/stateFilter. Its `distance` is the
    // nearest spot in that state (locationAggregates.stateDistances), so a state
    // carries its own proximity like a city/neighborhood hit and orders by it —
    // undefined when every spot in the state lacks coordinates. The folded
    // code/name are precomputed once per catalog change in the `states` binding.
    for (var stateIndex = 0; stateIndex < root.states.length; stateIndex++) {
      var stateHit = root.states[stateIndex];
      if (searchHitMatches(stateHit.foldedCode, term, prefixOnly) ||
          searchHitMatches(stateHit.foldedName, term, prefixOnly)) {
        results.push({ type: "state", key: stateHit.key, name: CatalogUtils.stateNameFor(stateHit.key), cityKey: "", cityName: "", count: stateHit.count, distance: root.locationAggregates.stateDistances[stateHit.key] });
      }
    }
    // Order the hits uniformly by proximity: finite distance ascending, geo-less
    // last, type as the tie-break, then name/key. The sort lives in
    // CatalogUtils.sortSearchHits (unit-tested); each hit carries its own
    // `distance` (computed above) so the sort reads it directly.
    return CatalogUtils.sortSearchHits(results);
  }

  // Match a folded candidate against the folded term: prefix-only below 2
  // characters, substring at 2+. Both sides are already folded, so the
  // comparison is accent-insensitive like the card-list rank path.
  function searchHitMatches(candidate, term, prefixOnly) {
    var hit = candidate.indexOf(term);
    return prefixOnly ? hit === 0 : hit >= 0;
  }

  // Precomputed search index: city names + spot counts (O(1) lookups) and, per
  // city, the neighborhood tally in first-seen order. Built by the same chunked
  // spot-index walk as spotsByName (rebuildCatalogIndex) so the ~5k-spot scan runs
  // in bounded slices instead of one synchronous pass in the catalogVersion
  // cascade. `byCity` keeps one record per (city, neighborhood) pair — a plain
  // neighborhood→record map would collapse the neighborhoods shared across
  // cities (e.g. "CBD"). Published atomically with spotsByName; the empty
  // structure below keeps readers safe before the first build completes.
  property var searchIndex: ({ cities: [], names: Object.create(null), counts: Object.create(null), byCity: Object.create(null), foldedNames: Object.create(null), foldedKeys: Object.create(null) })

  // Record one city's neighborhoods into the in-flight index ctx and
  // reset the per-city accumulators. Called from the chunked walk when a city's
  // spots are exhausted (including empty cities, which yield an empty record
  // list). Resolves names through CatalogUtils.cityLabelFor (the same seam as
  // cityLabel) rather than cityLabel itself, so it never depends on
  // cityLabelMap, which is rebuilt after this walk starts.
  function recordCityNeighborhoods(ctx, cityKey) {
    ctx.ordered.push(cityKey);
    var label = CatalogUtils.cityLabelFor(cityKey);
    ctx.names[cityKey] = label;
    // Precompute the folded match strings once per catalog version so the
    // per-keystroke search dropdown folds only the query (see searchMatches).
    ctx.foldedNames[cityKey] = SpotUtils.foldSearchText(label);
    ctx.foldedKeys[cityKey] = SpotUtils.foldSearchText(cityKey);
    var spots = ctx.spotsByCity[cityKey] || [];
    ctx.counts[cityKey] = spots.length;
    var records = [];
    for (var nbIdx = 0; nbIdx < ctx.nbOrder.length; nbIdx++) {
      var neighborhood = ctx.nbOrder[nbIdx];
      var rep = ctx.nbRep[neighborhood];
      records.push({
        key: neighborhood,
        name: neighborhood,
        foldedName: SpotUtils.foldSearchText(neighborhood),
        cityKey: cityKey,
        cityName: ctx.names[cityKey],
        count: ctx.nbCounts[neighborhood],
        lat: rep ? rep.lat : undefined,
        lon: rep ? rep.lon : undefined
      });
    }
    ctx.byCity[cityKey] = records;
    ctx.nbCounts = Object.create(null);
    ctx.nbOrder = [];
    ctx.nbRep = Object.create(null);
  }

  // Sorted rated journal entries (query + sort applied). Declarative so no
  // binding ever writes it. The dependency list is explicit because reads
  // inside the compute function are not tracked.
  property var sortedJournal: {
    root.journal;
    root.sortBy;
    root.sortReversed;
    root.journalQuery;
    root.kindFilter;
    root.cityKey;
    root.radius;
    root.neighborhood;
    root.spotsByName;
    root.ratingsBySpot;
    root.cityLabelMap;
    root.homeLat;
    root.homeLon;
    return root.computeSortedJournal();
  }
  function computeSortedJournal() {
    var entries = root.ratedEntries.slice();
    var query = root.journalQuery || "";
    if (query.trim()) {
      entries = entries.filter(function(entry) {
        return CatalogUtils.foldedContains(entry.name, query) ||
               CatalogUtils.foldedContains(root.cityLabel(entry.city), query) ||
               CatalogUtils.foldedContains(entry.notes, query) ||
               CatalogUtils.foldedContains(entry.city, query);
      });
    }
    // Global filters carried over from Explore (type/city/radius/neighborhood).
    // passesFilters matches the located spot, but the city predicate keys off
    // the journal entry's own `city` (not the located spot's catalog key).
    // neighborhoodFolded is hoisted so the filter value is lowercased once.
    var neighborhoodFolded = root.neighborhood ? root.neighborhood.toLowerCase() : "";
    entries = entries.filter(function(entry) {
      var located = root.locateSpot(entry.name, entry.city);
      return root.passesFilters(located ? located.spot : null, entry.city, { city: true, neighborhoodFolded: neighborhoodFolded });
    });
    // Single spec lookup + decoratedSort (CatalogUtils.sortBySpec): the
    // journalSortSpecs extractors resolve each entry's spot via locateSpot
    // where needed, and the rating key reads entry.rating directly.
    entries = CatalogUtils.sortBySpec(entries, root.sortBy, root.sortReversed, root.journalSortSpecs);
    // Resolve each entry's spot once so the delegate reads a plain property
    // (modelData.spot) instead of a non-reactive function-call binding. The
    // spot index (spotsByName) is built asynchronously; sortedJournal lists
    // it as an explicit dep, so this map re-runs once the index completes and
    // the resolved spots are always current.
    return entries.map(function(entry) {
      var located = root.locateSpot(entry.name, entry.city);
      return { name: entry.name, city: entry.city, spot: located ? located.spot : null, entry: entry };
    });
  }

  function showsCityLabels() { return !root.cityKey || root.radius > 0; }

  // Sort specs, keyed by sortBy, consumed by CatalogUtils.sortBySpec.
  // Each entry is { extract(item) -> primary value, tieBreakers?: [extractor] };
  // the extractors close over `root` (locateSpot, averageRatingFor, the
  // distance cache) and are pure reads, so sortBySpec evaluates them once per
  // item — never twice per comparison.

  // Journal entries: `extract` maps an entry to its sort value. The price and
  // distance keys resolve the entry's spot via locateSpot inside the extractor;
  // the rating key reads entry.rating directly. Journal entries carry no
  // tie-breakers.
  property var journalSortSpecs: ({
    rating: {
      extract: function (entry) { return entry.rating || 0; }
    },
    price: {
      extract: function (entry) {
        var located = root.locateSpot(entry.name, entry.city);
        return SpotUtils.priceSortValue(located ? located.spot : null);
      }
    },
    distance: {
      extract: function (entry) {
        var located = root.locateSpot(entry.name, entry.city);
        var spot = located ? located.spot : null;
        var km = rawDistanceKm(spot);
        return km === undefined ? Infinity : km;
      }
    }
  })

  // Spot arrays: extract each spot's sort key once, sort, then strip. Tie-breaks:
  //   rating   — the user's rating when present, else the stamped Yelp rating
  //              (_yelpRating); tie-break by Yelp review count (_yelpReviewCount).
  //   price    — priceSortValue yields -1 (discount, cheapest), a finite price,
  //              the Yelp price bucket, or Infinity (unpriced, always last);
  //              tie-break rating → review count → name, all direction-
  //              independent so flipping Price ↑/↓ never flips them.
  //   distance — nearest first, no tie-break.
  // The rating/price primaries read the stamped `_*` fields so the sort agrees
  // with SpotCard; the distance extractor reads the per-coordinate cache and
  // falls back to a fresh haversine while the chunked cache is still building.
  property var spotSortSpecs: ({
    rating: {
      extract: function (spot) { return root.averageRatingFor(spot.name) || spot._yelpRating; },
      tieBreakers: [
        function (spot) { return spot._yelpReviewCount; }
      ]
    },
    price: {
      extract: function (spot) { return SpotUtils.priceSortValue(spot); },
      tieBreakers: [
        function (spot) { return root.averageRatingFor(spot.name) || spot._yelpRating; },
        function (spot) { return spot._yelpReviewCount; },
        // Pre-lowercased at decorate time so compareSortValuesWithTie compares
        // plain strings (no per-comparison toLowerCase/localeCompare).
        function (spot) { return spot.name ? spot.name.toLowerCase() : ""; }
      ]
    },
    distance: {
      extract: function (spot) {
        // rawDistanceKm falls back to a fresh haversine mid-build; geo-less
        // spots get the Infinity sentinel so they always sort last.
        var km = rawDistanceKm(spot);
        return km === undefined ? Infinity : km;
      }
    }
  })

  // Filter + sort the spots for the selected city (or all cities). The base
  // filter/sort result is a declarative property keyed on the filter state; the
  // search term is applied as a cheap O(n) post-filter in a second declarative
  // property, so typing re-runs only the search pass, not the sort. Both are
  // declarative so no binding ever writes them; the searched result is a pure read.
  // The dependency list is explicit because reads inside the compute functions
  // are not tracked by the binding engine.
  //
  // distanceVersion — not catalogVersion — is the catalog trigger: the chunked
  // distance build bumps it only after the map is complete, so this property
  // never re-runs against the empty map refreshDistanceCache() installs at the
  // start of a catalog/home change. catalogVersion still bumps for the other
  // catalog-derived caches; adding it here would reintroduce the partial read.
  property var filteredSpots: {
    root.distanceVersion;
    root.sortBy;
    root.sortReversed;
    root.kindFilter;
    root.unratedOnly;
    root.cityKey;
    root.radius;
    root.neighborhood;
    root.stateFilter;
    root.countryFilter;
    root.ratingsBySpot;
    root.journalByName;
    return root.computeFilteredSpots();
  }
  function computeFilteredSpots() {
    var spots = root.showsCityLabels() ? root.flattenSpots() : spotsForCity(root.cityKey);
    // Lowercase the neighborhood filter once per pass, not once per spot.
    var neighborhoodFolded = root.neighborhood ? root.neighborhood.toLowerCase() : "";
    // Shared global predicates (type/radius/neighborhood/unratedOnly). City is
    // already enforced by the collection above; state/country stay local below.
    spots = spots.filter(function (spot) { return root.passesFilters(spot, spot._cityKey || "", { unratedOnly: true, neighborhoodFolded: neighborhoodFolded }); });
    if (root.stateFilter) {
      // The state code alone is ambiguous: a foreign region code can collide
      // with a US state code (Milan's "CO"/"VA" are Lombardy provinces). The
      // country gate (CatalogUtils.isUsState) keeps those foreign spots out of
      // a selected US state, matching the aggregate pass in computeLocationAggregates.
      spots = spots.filter(function (spot) {
        return (spot.state || "").toUpperCase() === root.stateFilter.toUpperCase() && CatalogUtils.isUsState(spot);
      });
    }
    if (root.countryFilter) {
      spots = spots.filter(function (spot) {
        return (spot.country || "").toUpperCase() === root.countryFilter.toUpperCase();
      });
    }
    // Single spec lookup + decoratedSort (CatalogUtils.sortBySpec): the
    // spotSortSpecs extractors read the stamped `_*` fields (and the distance
    // cache) so the sort agrees with SpotCard. priceSortValue keeps
    // discount-cheapest and unpriced-always-last.
    spots = CatalogUtils.sortBySpec(spots, root.sortBy, root.sortReversed, root.spotSortSpecs);
    return spots;
  }

  // Search rank over the base result. Declarative so the rank re-runs only when
  // the base data or the debounced query changes. The query is searchQuery (not
  // searchText) so the full-catalog pass trails typing by searchDebounceMs.
  // rankSpots groups matches by class descending — NAME_EXACT (2) > MATCH (1) —
  // and preserves the incoming order (the user's active sort) within a class, so
  // proximity decides among equal-quality (partial) matches. It is a two-rung
  // class ladder, not a score: an exact name match floats to the top, and every
  // other name/neighborhood match shares one tier. The city label is deliberately
  // not matched here — proximity must dominate the tail, and city scoping belongs
  // to the search dropdown.
  property var searchedSpots: {
    root.filteredSpots;
    root.searchQuery;
    return root.computeSearchedSpots();
  }
  function computeSearchedSpots() {
    var spots = root.filteredSpots;
    if (!root.searchQuery) return spots;
    return CatalogUtils.rankSpots(spots, root.searchQuery);
  }

  // Only the first `visibleCount` cards render — keeps delegate instantiation
  // cheap for the ~5k spot dataset. "Show more" extends the window. Declarative
  // so the slice is reused across unrelated re-evaluations: it re-runs only when
  // the searched result or the window size actually changes.
  property var pagedSpots: {
    root.searchedSpots;
    root.visibleCount;
    var all = root.searchedSpots;
    return all.length <= root.visibleCount ? all : all.slice(0, root.visibleCount);
  }

  // Explore list model snapshot. The ListView `model:` must NOT bind to a
  // reactive `property var` whose compute path can bump a tracked dependency
  // during evaluation (the chunked distance build bumps distanceVersion, which
  // filteredSpots tracks), because that makes the model binding self-
  // re-enter. Instead `pagedSpots` is snapshotted into this plain array by a
  // handler — an imperative assignment, never inside a binding — and the
  // ListView binds `model: root.exploreModel`. The handler fires only when
  // pagedSpots is reassigned (filter/search/window change), so the model is
  // stable across unrelated re-evaluations.
  property var exploreModel: []
  onPagedSpotsChanged: root.exploreModel = root.pagedSpots

  // Journal/Wishlist list-model snapshots, mirroring exploreModel. Each
  // ListView binds `model:` to this plain array; the handler snapshots the
  // declarative result whenever it is reassigned, so the model binding never
  // re-enters a reactive compute path.
  property var journalModel: []
  onSortedJournalChanged: root.journalModel = root.sortedJournal
  property var wishlistModel: []
  onFilteredWishlistChanged: root.wishlistModel = root.filteredWishlist

  // Saved spots resolved to { name, spot, cityKey } after the shared Explore
  // filters + wishlist query. Declarative so the binding engine owns the
  // recompute.
  // The dependency list is explicit because reads inside the compute function
  // are not tracked. spotsByName is reassigned whole when the catalog changes,
  // so it is a tracked dep on its own. distanceVersion is the distance-map
  // trigger (see filteredSpots);
  // homeLat/homeLon are not listed because they change with the catalog and
  // would re-run this against the empty map before the build completes.
  property var filteredWishlist: {
    root.saved;
    root.wishlistQuery;
    root.kindFilter;
    root.cityKey;
    root.radius;
    root.neighborhood;
    root.unratedOnly;
    root.spotsByName;
    root.ratingsBySpot;
    root.distanceVersion;
    root.cityLabelMap;
    return root.computeFilteredWishlist();
  }
  function computeFilteredWishlist() {
    var names = root.saved.slice();
    // Global filters carried over from Explore (shared with filteredSpots).
    // neighborhoodFolded is hoisted so the filter value is lowercased once.
    var neighborhoodFolded = root.neighborhood ? root.neighborhood.toLowerCase() : "";
    names = names.filter(function(name) {
      var located = root.locateSpot(name, "");
      return root.passesFilters(located ? located.spot : null, located ? located.cityKey : "", { city: true, unratedOnly: true, name: name, neighborhoodFolded: neighborhoodFolded });
    });
    var query = root.wishlistQuery || "";
    if (query.trim()) {
      names = names.filter(function(name) {
        if (CatalogUtils.foldedContains(name, query)) return true;
        var located = root.locateSpot(name, "");
        var spot = located ? located.spot : null;
        if (!spot) return false;
        if (CatalogUtils.foldedContains(spot.neighborhood, query)) return true;
        var cityKey = located.cityKey;
        if (cityKey && CatalogUtils.foldedContains(root.cityLabel(cityKey), query)) return true;
        return false;
      });
    }
    // Resolve each saved name to { name, spot, cityKey } so the delegate reads
    // plain properties (modelData.spot) instead of a non-reactive function-call
    // binding against the async-built spotsByName index.
    return names.map(function(name) {
      var located = root.locateSpot(name, "");
      return { name: name, spot: located ? located.spot : null, cityKey: located ? located.cityKey : "" };
    });
  }

  // ---- Navigation ----

  // Count of open (non-closed) spots in the current filter/search result — the
  // surprise pool's size without materializing the pool itself. Declarative
  // (lists `searchedSpots` as its tracked dep) so the SurpriseButton's enabled
  // state and the spotlight's "Try another" visibility track it with no manual
  // invalidation. Closed spots are excluded via `_isClosed` — the same derived
  // field SpotCard's "Closed" badge reads — and here only: the normal
  // list/filter semantics are unchanged. The pool array is built on demand in
  // surpriseMe(), never on a keystroke.
  readonly property int surpriseCount: {
    root.searchedSpots;
    var spots = root.searchedSpots;
    var count = 0;
    for (var i = 0; i < spots.length; i++) {
      var spot = spots[i];
      if (spot && !spot._isClosed) count++;
    }
    return count;
  }

  // True when the surprise pool holds at least one candidate. Drives the
  // SurpriseButton's enabled state so an empty result never presents a dead
  // button.
  readonly property bool surpriseAvailable: root.surpriseCount > 0

  // Pick a random spot from the current filter results and open the spotlight
  // view on it with the rating editor expanded (rating the pick is the point of
  // the flow). Returns true when a candidate exists. While the spotlight is
  // already open (the "Another" path) the current spot's name is passed as
  // `excludeName`, so a shuffle never returns the spot already on screen when
  // an alternative exists. The pick itself is the pure `CatalogUtils.pickRandom`
  // (injectable rng for tests, empty pool -> null). The pool is materialized
  // here (a click handler, not a binding) so typing never allocates it.
  function surpriseMe() {
    var excludeName = (root.spotlight && root.spotlightEntry) ? root.spotlightEntry.name : "";
    var spots = root.searchedSpots;
    var pool = [];
    for (var i = 0; i < spots.length; i++) {
      var spot = spots[i];
      if (spot && !spot._isClosed) pool.push(spot);
    }
    var pick = CatalogUtils.pickRandom(pool, Math.random, excludeName);
    if (!pick) return false;
    root.spotlightEntry = pick;
    root.expandedSpotName = pick.name;
    root.editorOpen = true; // rating the surprised spot is the point of the flow
    root.spotlight = true;
    var journalEntry = root.latestJournalFor(pick.name);
    root.editStars = journalEntry ? journalEntry.rating : 0;
    root.editNotes = journalEntry ? journalEntry.notes : "";
    return true;
  }

  // Collapse any expanded row and reset its rating state.
  function collapseRow() {
    root.expandedSpotName = null;
    root.editorOpen = false;
    root.editStars = 0;
    root.editNotes = "";
  }

  // Reveal the full editor for the currently expanded row.
  function openEditor() {
    root.editorOpen = true;
  }

  // Switch the active tab and collapse any expanded row. The pinned header's
  // TabChips and SpotlightView's TabChips (via `openTab`) route through here so
  // the tab-switch side effects live in one place. `openTab` additionally closes
  // the spotlight view before switching (the Spotlight chips return to a tab).
  function switchTab(tab) {
    root.tab = tab;
    root.collapseRow();
  }
  function openTab(tab) {
    root.spotlight = false;
    root.switchTab(tab);
  }

  // Toggle a row's expanded state; tapping the expanded row collapses it.
  function toggleRow(spotName, stars, notes) {
    if (root.expandedSpotName === spotName) {
      root.collapseRow();
    } else {
      root.expandedSpotName = spotName;
      root.editorOpen = false;
      root.editStars = stars || 0;
      root.editNotes = notes || "";
    }
  }

  function toggleSaved(spotName) {
    var index = root.saved.indexOf(spotName);
    if (index >= 0) {
      root.saved.splice(index, 1);
    } else {
      root.saved.push(spotName);
    }
    // Reassign a fresh array so bindings on `saved` (Repeater model, heart
    // glyphs) re-evaluate after the in-place mutation.
    root.saved = root.saved.slice();
    root.refreshSavedSet();
    savedFile.setText(JSON.stringify(root.saved));
  }

  // Fire an omakase IPC command (rate/unrate). All rating actions go through
  // the Service, which owns the journal — the bar widget never writes it.
  function runIpcCommand(method, args) {
    Quickshell.execDetached(["omarchy-shell", "omakase", method].concat(args));
  }

  // Toggle a filter dropdown by name: opening one closes any other (a single
  // string can only hold one open dropdown at a time). Toggling the already-
  // open dropdown closes it.
  function toggleDropdown(name) {
    root.openDropdown = (root.openDropdown === name ? "" : name);
  }

  // Location filter selectors. Each owns its side effects: picking one scope
  // clears the other location scopes (they are mutually exclusive) and the
  // radius, so the picked scope is authoritative. Consistent across every path
  // (dropdown pick, search-dropdown click, card meta-row click, CityHeader back).
  //
  // `scope` is "city" | "state" | "country" | "neighborhood" | "" (clear all).
  // The picked scope is set to `value`; every other scope is cleared. Only the
  // city scope sets cityKey here — a neighborhood pick passes the neighborhood
  // *name* as `value`, not a city key, so its cityKey is set by
  // selectNeighborhood (below) instead.
  function applyLocationScope(scope, value) {
    root.cityKey = (scope === "city") ? value : "";
    root.stateFilter = (scope === "state") ? value : "";
    root.countryFilter = (scope === "country") ? value : "";
    root.neighborhood = (scope === "neighborhood") ? value : "";
    root.radius = 0;
    root.openDropdown = "";
  }

  // Clear the named location scopes (city/state/country/neighborhood) without
  // touching the radius. The Nearby pill owns the radius itself, so it must not
  // route through applyLocationScope (which zeroes radius).
  function clearLocationScopes() {
    root.cityKey = "";
    root.stateFilter = "";
    root.countryFilter = "";
    root.neighborhood = "";
    root.openDropdown = "";
  }

  // A neighborhood pick sets both the neighborhood filter and its city key:
  // applyLocationScope sets the neighborhood name, then the city key is applied
  // here (the two scopes live together — a neighborhood always belongs to its
  // city).
  function selectNeighborhood(neighborhood, cityKey) {
    root.applyLocationScope("neighborhood", neighborhood);
    root.cityKey = cityKey;
  }

  function selectCity(cityKey) {
    root.applyLocationScope("city", cityKey);
  }

  function selectState(stateKey) {
    root.applyLocationScope("state", stateKey);
  }

  function selectCountry(countryKey) {
    root.applyLocationScope("country", countryKey);
  }

  // Clear every Explore filter back to its default and close any open dropdown
  // or sheet.
  function resetFilters() {
    root.kindFilter = "all";
    root.sortBy = "distance";
    root.sortReversed = false;
    root.unratedOnly = false;
    root.openSheet = false;
    root.applyLocationScope("", "");
  }

  // ---- Utility ----

  // Unique neighborhood names for the current city, sorted. The "All
  // neighborhoods" clear affordance lives in the dropdown's clearLabel row and
  // the chip strip's leading "All" chip, not in this list. Declarative so no
  // binding ever writes it; it is a pure read. Depends on the catalog too (a
  // city's neighborhoods come from its spots), hence catalogVersion.
  property var neighborhoodOptions: {
    root.cityKey;
    root.catalogVersion;
    var spots = root.cityKey ? root.spotsForCity(root.cityKey) : [];
    return CatalogUtils.computeNeighborhoodOptions(spots);
  }

  // Single-pass state + country aggregation, shared by states and countries so
  // the catalog is scanned once instead of twice. Only US states are surfaced
  // as "state" filters — a spot counts as a state only when its `state` is a
  // 2-letter US code AND its `country` is "US" (computeLocationAggregates gates
  // via CatalogUtils.isUsState), so a foreign region code that collides with a
  // US state code (e.g. Amsterdam's "NH" = Noord-Holland) never appears as a
  // state, and non-US region codes (e.g. "VIC"/"11") never cluttered the picker
  // in the first place. Declarative so no binding ever writes it; it is a pure
  // read. distanceVersion is the catalog trigger (see filteredSpots) so the
  // nearest-value ordering never reads the empty map installed at the start of
  // a catalog/home change. flattenSpots() and the distance accessor are function
  // calls, so their `catalog`/`distanceByCoords`/`homeLat` reads stay untracked
  // and distanceVersion remains the only trigger that fires.
  property var locationAggregates: {
    root.distanceVersion;
    return CatalogUtils.computeLocationAggregates(root.flattenSpots(), function (spot) {
      return rawDistanceKm(spot);
    });
  }

  // States present in the catalog (from Yelp "state" field), each aggregated
  // across all cities with its spot count, sorted alphabetically with the
  // nearest state first. Result is [{ key, count, foldedCode, foldedName }].
  // foldedCode/foldedName are precomputed here (once per catalog/home change)
  // so searchMatches folds only the query per keystroke.
  property var states: {
    root.locationAggregates;
    var aggregates = root.locationAggregates;
    var list = CatalogUtils.aggregateList(aggregates.stateCounts, aggregates.nearestState);
    for (var stateIndex = 0; stateIndex < list.length; stateIndex++) {
      var code = list[stateIndex].key;
      list[stateIndex].foldedCode = SpotUtils.foldSearchText(code);
      list[stateIndex].foldedName = SpotUtils.foldSearchText(CatalogUtils.stateNameFor(code));
    }
    return list;
  }

  // Countries present in the catalog (Yelp "country" field), aggregated across
  // all cities with spot counts, sorted alphabetically with the nearest country
  // first. [{ key, count }].
  property var countries: {
    root.locationAggregates;
    var aggregates = root.locationAggregates;
    return CatalogUtils.aggregateList(aggregates.countryCounts, aggregates.nearestCountry);
  }

  // Cities ordered by distance from home (nearest first); geo-less cities last.
  // Declarative so the 65 cityDistanceKm() haversines run once per catalog/home
  // change instead of on every cityFilterItems evaluation. Depends on
  // catalogVersion (city list + fallback coords) and home (distance).
  property var sortedCities: {
    root.catalogVersion;
    root.homeLat;
    root.homeLon;
    var cities = root.catalog.cities || [];
    return CatalogUtils.computeSortedCities(cities, root.cityDistanceKm);
  }

  // FilterDropdown item lists — { key, label } pairs consumed by the generic
  // dropdown. The builders live in catalog-utils.js (pure, unit-tested); these
  // declarative properties pass the resolved inputs so the four FilterPanel
  // instances share one build per catalog/filter change instead of rebuilding
  // the arrays on every evaluation. Each lists its source data as an explicit
  // dep because reads inside the builder callbacks are not tracked.
  property var cityFilterItems: {
    root.sortedCities;
    root.catalogVersion;
    return CatalogUtils.buildCityFilterItems(root.sortedCities, root.cityDistanceLabel, root.catalog.spotsByCity || {});
  }

  property var stateFilterItems: {
    root.states;
    return CatalogUtils.buildStateFilterItems(root.states);
  }

  property var countryFilterItems: {
    root.countries;
    return CatalogUtils.buildCountryFilterItems(root.countries);
  }

  property var neighborhoodFilterItems: {
    root.neighborhoodOptions;
    return CatalogUtils.buildNeighborhoodFilterItems(root.neighborhoodOptions);
  }

  // Open a URL only after SpotUtils.safeExternalUrl validates its scheme. The
  // allow-list guard (https/mailto/tel) lives in spot-utils so it is
  // unit-testable; here it just guards the external open.
  function openUrl(url) {
    var target = SpotUtils.safeExternalUrl(url);
    if (target) Qt.openUrlExternally(target);
  }

  property int catalogVersion: 0
  // Post-search spot count for the scroll handler. Reads the declarative
  // searched result directly, so it re-evaluates only when that result changes.
  readonly property int filteredCount: root.searchedSpots.length
  // Reset the paging window on every filter change. The declarative caches
  // re-evaluate on their own tracked inputs; no manual invalidation is needed.
  function resetListWindow() { visibleCount = pageSize }
  // Prefetch: add a full page at once, then re-check the lookahead on the next
  // event-loop turn. `prefetching` is cleared once the lookahead is
  // satisfied or the list is exhausted, letting the next scroll event start a
  // fresh fill.
  function fillPrefetch() {
    visibleCount += pageSize;
    var pagePx = pageSize * collapsedCardHeight;
    var remaining = exploreTab ? exploreTab.contentHeight - (exploreTab.contentY + exploreTab.height) : 0;
    if (remaining < pagePx && visibleCount < filteredCount) {
      Qt.callLater(function() { root.fillPrefetch(); });
    } else {
      prefetching = false;
    }
  }
  onCityKeyChanged: resetListWindow()
  onNeighborhoodChanged: resetListWindow()
  onKindFilterChanged: resetListWindow()
  onRadiusChanged: resetListWindow()
  onSortByChanged: resetListWindow()
  onSortReversedChanged: resetListWindow()
  onSearchTextChanged: {
    resetListWindow()
    // Any query change (including clearing the field) re-opens the
    // suggestions; the dropdown's visibility re-reads the flag on its own.
    root.searchSuggestionsDismissed = false
    if (root.searchText === "") {
      // Clearing the field is instant: stop the timer and flush an empty
      // searchQuery so the full list reappears without waiting out the
      // debounce window.
      searchDebounceTimer.stop()
      root.searchQuery = ""
    } else {
      searchDebounceTimer.restart()
    }
  }
  onUnratedOnlyChanged: resetListWindow()
  onStateFilterChanged: resetListWindow()
  onCountryFilterChanged: resetListWindow()
  // Journal data feeds ratedEntries/sortedJournal (declarative) and the
  // eagerly-maintained rating maps; rebuild those maps and the display-city map.
  onJournalChanged: { refreshRatings(); buildCityLabelMap() }
  onSavedChanged: refreshSavedSet()
  // Neighborhood list derives from catalog data, not just cityKey.
  onCatalogChanged: {
    // `catalog` is a lazily-evaluated `property var` binding, so its first read
    // (flattenSpots inside the filteredSpots binding) evaluates it and fires this
    // handler while filteredSpots is mid-evaluation. Running the rebuild then
    // would write filteredSpots's tracked deps — distanceVersion (via
    // refreshDistanceCache) and ratingsBySpot/journalByName (via
    // buildCityLabelMap -> journal -> onJournalChanged -> refreshRatings) — and
    // re-enter the binding. The placeholder catalog is empty, so there is
    // nothing to rebuild: skip it until real data lands.
    if (!root.catalog.cities || root.catalog.cities.length === 0) return;
    rebuildCatalogIndex();
    refreshDistanceCache();
    buildCityLabelMap();
    catalogVersion++;
  }
  // homeLat/homeLon are derived solely from `catalog`, so onCatalogChanged
  // already bumps catalogVersion for a home move. The declarative caches list
  // homeLat/homeLon as explicit deps, so they still re-evaluate; bumping here
  // too would recompute every cache a second and third time per load.

  KeyboardPanel {
    id: panel
    anchorItem: barButton
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(450))
    contentHeight: root.spotlight ? (spotlightCol.implicitHeight + panel.verticalContentInset) : Math.min(root.pinnedHeaderHeight + root.activeTabHeight + panel.verticalContentInset, root.maxPanelHeight)
    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // While any search field owns keyboard focus, forward ALL keys to it so
      // typing (including Space/arrows) and Escape reach the field instead of
      // the panel's cursor/close shortcuts. `hasFocus`/`searchFieldHasFocus`
      // are live activeFocus reads, aggregated across the Explore, Wishlist,
      // Journal, and Spotlight search fields.
      blocked: exploreSearch.hasFocus || wishlistTab.searchFieldHasFocus || journalTab.searchFieldHasFocus || spotlightCol.searchFieldHasFocus
      onCloseRequested: root.close()

      // Pinned header: tab chips + Surprise Me, above the scroller so they stay
      // visible while the list scrolls. Hidden in spotlight (the spotlight view
      // owns its own chips).
      Item {
        id: pinnedHeader
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.spotlight ? 0 : root.pinnedHeaderHeight
        visible: !root.spotlight
        // Lift the pinned header above the Flickable so the search dropdown and
        // the floating FilterSheet paint over the cards instead of under them.
        // The back-to-top FAB (z: 10) stays above this.
        z: 2

        Column {
          id: pinnedColumn
          anchors.top: parent.top
          anchors.topMargin: Style.space(16)
          anchors.left: parent.left
          anchors.leftMargin: Style.space(16)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(16)
          spacing: Style.space(10)

          Row {
            width: parent.width
            height: Style.space(28)
            spacing: Style.space(8)

            TabChips {
              panel: root
              currentTab: root.tab
              width: parent.width - surpriseButton.width - parent.spacing
              onPicked: function(tab) { root.switchTab(tab) }
            }

            // Surprise Me — a labeled pill (dice glyph + "Surprise me"); the hover
            // tooltip spells out the action. Extracted to SurpriseButton.qml.
            // Disabled (via the built-in Item.enabled, which cascades to the
            // child MouseArea) when the current filter/search yields no open
            // spot, so an empty result never presents a dead button — the
            // Explore tab's empty state provides the feedback.
            SurpriseButton {
              id: surpriseButton
              panel: root
              enabled: root.surpriseAvailable
            }
          }

          // Explore-only pinned search + filter. Pinning them below the tab row
          // keeps search/filter reachable while the card list scrolls; the list
          // remains the only scroller. Hidden on Wishlist/Journal, which own
          // their own search fields inside their tab columns.
          SearchField {
            id: exploreSearch
            visible: root.tab === "explore"
            panel: root
            placeholder: root.searchPlaceholder
            text: root.searchText
            onEdited: function(v) { root.searchText = v }
            onDismissed: root.searchSuggestionsDismissed = true
          }

          // City/neighborhood/state match dropdown, floating under the search
          // field. Kept in the pinned column flow (matching the previous
          // ListView-header behavior) so it grows the pinned region and shrinks
          // the list rather than overlapping the FilterBar. Extracted to
          // SearchResultsDropdown.qml.
          SearchResultsDropdown { panel: root }

          // FilterBar primary row + active-filter summary. The neighborhood
          // chip strip stays in the ExploreTab ListView header (it can be
          // several rows tall and is secondary to the primary row).
          FilterPanel {
            visible: root.tab === "explore"
            panel: root
            showNeighborhoodChips: false
          }
        }
      }

      Flickable {
        id: flick
        anchors.top: pinnedHeader.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentWidth: width
        // On Explore the ListView is the only scroller, so the outer Flickable
        // is pinned to the panel cap (no scroll) and made non-interactive.
        // Other tabs use the active tab's real height (not the content Column's
        // implicitHeight, which sums the hidden tabs) so the Flickable never
        // scrolls into empty space below the content.
        contentHeight: root.spotlight ? spotlightCol.implicitHeight : ((root.tab === "explore") ? root.maxPanelHeight : root.activeTabHeight)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: (root.tab === "explore" && !root.spotlight) ? false : contentHeight > height
        // Coarse scroll bucket for image gating. Cards bind their image
        // visibility to this integer instead of to `contentY`, so a card's
        // binding re-evaluates only when the bucket changes (every
        // `imageBucketHeight` px) rather than on every scroll frame. The
        // Explore tab's own ListView owns its bucket; this one serves the
        // other tabs.
        property int imageWindowStart: 0
        onContentYChanged: {
          var bucket = Math.floor(contentY / root.imageBucketHeight);
          if (bucket !== imageWindowStart) imageWindowStart = bucket;
        }
        // Establish the initial lookahead on load: one batch so the window
        // starts a full page ahead of the viewport even before any scroll
        // event fires (a short first batch would otherwise leave the list
        // short with no scroll to trigger the lookahead).
        Component.onCompleted: {
          if (root.visibleCount < root.filteredCount) root.visibleCount += root.pageSize;
        }

        Column {
          // MUST be bound to the Flickable width: children use `width:
          // parent.width, and an unbound Column collapses to its implicit
          // width (~0), which renders the whole popup empty.
          width: flick.width
          visible: !root.spotlight
          spacing: Style.space(10)
          padding: Style.space(16)
          // The pinned header owns the top padding; no bottom clearance either
          // (the Explore ListView extends to the panel bottom and the
          // back-to-top FAB floats over it).
          topPadding: 0
          bottomPadding: 0

          ExploreTab {
            id: exploreTab
            panel: root
            availableHeight: root.exploreListHeight
          }

          WishlistTab {
            id: wishlistTab
            panel: root
            scrollView: flick
          }

          JournalTab {
            id: journalTab
            panel: root
            scrollView: flick
          }

        }

        SpotlightView { id: spotlightCol; panel: root; scrollView: flick }

      }

      Rectangle {
        z: 10
        visible: exploreTab && exploreTab.contentY > root.backToTopThreshold && root.tab === "explore" && !root.spotlight
        anchors.right: parent.right; anchors.rightMargin: Style.space(16)
        // Tuck the arrow near the panel's bottom edge.
        anchors.bottom: parent.bottom; anchors.bottomMargin: Style.space(16)
        width: 40; height: 40
        radius: 20
        color: root.accentTint
        border.color: root.accentColor
        border.width: 1
        // Fade in/out with the same scroll condition that gates `visible`, so
        // the button doesn't pop. `visible` still hard-gates hit-testing.
        opacity: visible ? 0.85 : 0
        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Text {
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: "\u2191"
          color: root.accentColor
          font.pixelSize: 20
          font.bold: true
        }
        // Quick animated scroll to the top. The animation lives on ExploreTab
        // (it owns the ListView); this button also resets the outer Flickable,
        // whose contentY can retain a residual offset from another tab and
        // would otherwise shift the whole column up, hiding the tab chips.
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (exploreTab) exploreTab.scrollToTop();
            flick.contentY = 0;
          }
        }
      }

    }
  }
}
