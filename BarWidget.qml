import QtQuick
import Quickshell
import Quickshell.Io
import QtQuick.Layouts
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
  property string kindFilter: "all"
  property string sortBy: "distance"
  property bool sortReversed: false
  property string journalQuery: ""
  property string wishlistQuery: ""
  property string tab: "explore"
  property bool unvisited: false
  property string neighborhood: ""
  property string stateFilter: ""  // Yelp state filter (e.g. "GA"); "" = all
  property string countryFilter: ""  // country filter (e.g. "US"); "" = all
  property int radius: 0  // 0 = off; 5/10/20 = km radius
  // Which filter dropdown is open ("" = none). One string replaces the four
  // per-filter booleans so the FilterBar pills share a single toggle helper.
  property string openDropdown: ""
  property var saved: []
  // name -> true set rebuilt whenever `saved` changes, so isSaved() is O(1)
  // instead of an O(saved) indexOf scan per card. Null-prototype so a saved
  // name like "constructor" can't collide with Object.prototype.
  property var savedSet: Object.create(null)
  property bool spotlight: false
  property var spotlightEntry: null
  property var expandedSpotName: null  // spot name that is expanded, or null
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
  readonly property bool showNeighborhoodChips: root.cityKey !== "" && root.neighborhoodOptions.length > 1 && root.neighborhoodOptions.length <= root.maxNeighborhoodChips
  // Back-to-top FAB appears once the list is scrolled past this offset.
  readonly property real backToTopThreshold: Style.space(400)
  // Cap on the (non-spotlight) panel height; the Flickable scrolls past it.
  readonly property real maxPanelHeight: Style.space(640)
  // Bounded height for the Explore ListView: the panel cap minus the card's
  // real vertical chrome (popup padding + border, from KeyboardPanel) and the
  // column's top padding. The header (tab chips, search, filters) lives inside
  // the ListView, so it consumes viewport space rather than being subtracted
  // here. The list extends to the panel bottom; the Surprise Me / back-to-top
  // FABs float over it.
  readonly property real exploreListHeight: Math.max(Style.space(200), root.maxPanelHeight - panel.verticalContentInset - Style.space(16))
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

  // Foreground-derived tint at a given alpha — single source for the many
  // semi-transparent card/border/dropdown colors.
  function foregroundAlpha(a) { return Qt.rgba(root.foregroundColor.r, root.foregroundColor.g, root.foregroundColor.b, a) }

  readonly property string repoUrl: "https://github.com/ronald2wing/Omarchy-Omakase"

  readonly property real collapsedCardHeight: Style.space(104)  // collapsed card height
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
  property var totalSpotCount: {
    root.catalogVersion;
    var spotCount = 0;
    var spotsByCity = (root.catalog && root.catalog.spotsByCity) ? root.catalog.spotsByCity : {};
    for (var key in spotsByCity) spotCount += spotsByCity[key].length;
    return spotCount;
  }

  readonly property string searchPlaceholder: {
    var cityCount = (root.catalog && root.catalog.cities) ? root.catalog.cities.length : 0;
    return "Search " + cityCount + " cities · " + root.totalSpotCount + " spots";
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

  // Stamp each spot with its city key ONCE at load so the filter pass never
  // mutates the shared catalog objects (which spotsByName and other readers
  // hold by reference). _cityKey is a stable field thereafter, not a sort-time
  // side-channel. Stamping ~5k spots with ~10 SpotUtils formatters froze the UI
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
    // set and order the old synchronous for...in loop stamped.
    var ctx = { city: 0, spot: 0, cityKeys: Object.keys(spotsByCity), spotsByCity: spotsByCity, catalog: catalog };
    chunkWalk.runChunked({
      getToken: function () { return root.catalogToken; },
      chunkSize: root.catalogChunkSize,
      ctx: ctx,
      step: function (ctx) {
        var spots = ctx.spotsByCity[ctx.cityKeys[ctx.city]] || [];
        if (ctx.spot >= spots.length) {
          ctx.spot = 0;
          ctx.city++;
          return { processed: 0, more: ctx.city < ctx.cityKeys.length };
        }
        var spot = spots[ctx.spot];
        spot._cityKey = ctx.cityKeys[ctx.city];
        // Stamp the pure-function display results once per spot so SpotCard's
        // derived properties read a field instead of re-running ~10 formatters
        // on every delegate bind. These are pure functions of immutable spot
        // fields, so the values never change after load.
        spot._spotKind = SpotUtils.spotKind(spot);
        spot._isClosed = SpotUtils.isClosed(spot);
        spot._canBook = SpotUtils.canBook(spot);
        spot._imageUrl = SpotUtils.spotImageUrl(spot);
        spot._priceLabel = SpotUtils.formatPrice(spot);
        spot._priceNumber = SpotUtils.priceNumber(spot.price);
        spot._courses = SpotUtils.formatCourses(spot);
        spot._yelpRating = Number(spot.yelp_rating) || 0;
        spot._yelpReviewCount = spot.yelp_review_count || 0;
        spot._yelpPrice = spot.yelp_price || "";
        spot._mapsUrl = SpotUtils.mapsUrl(spot);
        ctx.spot++;
        if (ctx.spot >= spots.length) {
          ctx.spot = 0;
          ctx.city++;
        }
        return { processed: 1, more: ctx.city < ctx.cityKeys.length };
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
  // ~2.8 MB parse producing ~3k spots), so the build runs through runChunked in
  // spotIndexChunkSize-spot slices. The map is swapped in atomically only when
  // complete, so spotsByName is never observed partially built; a superseded
  // build is discarded when its token no longer matches (a newer catalog change
  // landed).
  readonly property int spotIndexChunkSize: 400
  property int spotIndexToken: 0

  function refreshRatings() {
    var ratingsMap = Object.create(null);
    var journalMap = Object.create(null);
    var ratedEntries = root.ratedEntries;
    for (var i = 0; i < ratedEntries.length; i++) {
      var entry = ratedEntries[i];
      var key = entry.name;
      if (!ratingsMap[key]) ratingsMap[key] = { total: 0, count: 0 };
      ratingsMap[key].total += entry.rating;
      ratingsMap[key].count++;
      // Entries are oldest-first, so the last write wins: the map keeps the most
      // recent rated entry per name, mirroring latestJournalFor's old reverse scan.
      journalMap[key] = entry;
    }
    root.ratingsBySpot = ratingsMap;
    root.journalByName = journalMap;
  }

  function refreshSpotIndex() {
    root.spotIndexToken++;
    // The catalog is snapshotted once per build (not re-read per slice); a newer
    // catalog change bumps the token and supersedes any in-flight build before
    // it can publish from this stale snapshot. One walk builds both the
    // name→entries index and the neighborhood search index, so the catalog is
    // scanned once instead of twice.
    var ctx = {
      city: 0,
      spot: 0,
      cities: root.catalog.cities || [],
      spotsByCity: root.catalog.spotsByCity || {},
      map: Object.create(null),
      ordered: [],
      names: Object.create(null),
      counts: Object.create(null),
      byCity: Object.create(null),
      nbCounts: Object.create(null),
      nbOrder: []
    };
    chunkWalk.runChunked({
      getToken: function () { return root.spotIndexToken; },
      chunkSize: root.spotIndexChunkSize,
      ctx: ctx,
      step: function (ctx) {
        var cityKey = ctx.cities[ctx.city];
        var spots = ctx.spotsByCity[cityKey] || [];
        if (ctx.spot >= spots.length) {
          root.recordCityNeighborhoods(ctx, cityKey);
          ctx.spot = 0;
          ctx.city++;
          return { processed: 0, more: ctx.city < ctx.cities.length };
        }
        var spot = spots[ctx.spot];
        var name = spot.name;
        if (name !== undefined && name !== null) {
          if (!ctx.map[name]) ctx.map[name] = [];
          ctx.map[name].push({ spot: spot, cityKey: cityKey });
        }
        var neighborhood = (spot.neighborhood || "").trim();
        if (neighborhood) {
          if (ctx.nbCounts[neighborhood] === undefined) ctx.nbOrder.push(neighborhood);
          ctx.nbCounts[neighborhood] = (ctx.nbCounts[neighborhood] || 0) + 1;
        }
        ctx.spot++;
        if (ctx.spot >= spots.length) {
          root.recordCityNeighborhoods(ctx, cityKey);
          ctx.spot = 0;
          ctx.city++;
        }
        return { processed: 1, more: ctx.city < ctx.cities.length };
      },
      done: function (ctx) {
        root.spotsByName = ctx.map;
        root.neighborhoodSearchIndex = { cities: ctx.ordered, names: ctx.names, counts: ctx.counts, byCity: ctx.byCity };
        // filteredWishlist reads spotsByName through locateSpot but lists
        // dataRevision as an explicit dep (the async build only signals completion
        // through a bump), so bump it once the fresh index is in place.
        // Declarative readers (sortedJournalData) re-evaluate on their own
        // tracked spotsByName dependency. searchMatches() is called from a
        // function binding, so it needs the same bump to observe the new index.
        root.dataRevision++;
      }
    }, root.spotIndexToken);
  }

  function refreshSavedSet() {
    var set = Object.create(null);
    for (var i = 0; i < root.saved.length; i++) set[root.saved[i]] = true;
    root.savedSet = set;
  }

  Component.onCompleted: { root.refreshRatings(); root.buildDisplayCityMap(); root.refreshSavedSet() }

  // Resolve a spot by name. A non-empty city match wins first; otherwise the
  // first city (in catalog order) holding the name is returned — the same
  // resolution as the old linear scan, now an O(1) read from spotsByName.
  // Returns { spot, cityKey } or null when no city contains the spot.
  function locateSpot(name, city) {
    var entries = root.spotsByName[name];
    if (!entries || !entries.length) return null;
    var cityKey = city || "";
    if (cityKey) {
      for (var index = 0; index < entries.length; index++) {
        if (entries[index].cityKey === cityKey) return entries[index];
      }
    }
    return entries[0];
  }

  // Resolve a saved entry (journal/wishlist) name to { spot, cityKey }, or a
  // null spot with an empty city key when the name is no longer in the catalog.
  // The single resolver the two saved lists share instead of each re-nulling
  // locateSpot's result.
  function resolveSavedEntry(name, city) {
    return root.locateSpot(name, city) || { spot: null, cityKey: "" };
  }

  function isSaved(spotName) {
    return !!root.savedSet[spotName];
  }

  function capitalize(text) { var value = text || ""; return value.charAt(0).toUpperCase() + value.slice(1); }

  // ---- Formatting ----

  // Display-name lookup: city key -> { name, country, lat, lon }. Keys are the
  // internal slugs used in data/*.jsonl filenames and the state `city` field;
  // the map holds the real city name, its country, and city-center coordinates
  // (used for the home-to-city distance display).
  readonly property var cityMeta: ({
    "australia": { name: "Sydney", country: "Australia", lat: -33.8688, lon: 151.2093 },
    "bangkok": { name: "Bangkok", country: "Thailand", lat: 13.7563, lon: 100.5018 },
    "chicago": { name: "Chicago", country: "USA", lat: 41.8781, lon: -87.6298 },
    "dubai": { name: "Dubai", country: "UAE", lat: 25.2048, lon: 55.2708 },
    "hong-kong": { name: "Hong Kong", country: "China", lat: 22.3193, lon: 114.1694 },
    "kyoto": { name: "Kyoto", country: "Japan", lat: 35.0116, lon: 135.7681 },
    "las-vegas": { name: "Las Vegas", country: "USA", lat: 36.1699, lon: -115.1398 },
    "london": { name: "London", country: "UK", lat: 51.5074, lon: -0.1278 },
    "los-angeles": { name: "Los Angeles", country: "USA", lat: 34.0522, lon: -118.2437 },
    "mexico-city": { name: "Mexico City", country: "Mexico", lat: 19.4326, lon: -99.1332 },
    "nyc": { name: "New York City", country: "USA", lat: 40.7128, lon: -74.0060 },
    "osaka": { name: "Osaka", country: "Japan", lat: 34.6937, lon: 135.5023 },
    "paris": { name: "Paris", country: "France", lat: 48.8566, lon: 2.3522 },
    "san-francisco": { name: "San Francisco", country: "USA", lat: 37.7749, lon: -122.4194 },
    "sao-paulo": { name: "São Paulo", country: "Brazil", lat: -23.5505, lon: -46.6333 },
    "seoul": { name: "Seoul", country: "South Korea", lat: 37.5665, lon: 126.9780 },
    "shanghai": { name: "Shanghai", country: "China", lat: 31.2304, lon: 121.4737 },
    "singapore": { name: "Singapore", country: "", lat: 1.3521, lon: 103.8198 },
    "taipei": { name: "Taipei", country: "Taiwan", lat: 25.0330, lon: 121.5654 },
    "tokyo": { name: "Tokyo", country: "Japan", lat: 35.6762, lon: 139.6503 },
    "toronto": { name: "Toronto", country: "Canada", lat: 43.6532, lon: -79.3832 },
    "vancouver": { name: "Vancouver", country: "Canada", lat: 49.2827, lon: -123.1207 }
  })

  // cityMeta is a fixed literal keyed by known slugs, but the lookup key is an
  // untrusted catalog city. Read through hasOwnProperty so a city like
  // "constructor" can never resolve to an Object.prototype member.
  function cityMetaFor(key) {
    return Object.prototype.hasOwnProperty.call(root.cityMeta, key) ? root.cityMeta[key] : null;
  }

  // Map a city key to its display string: "nyc" -> "New York City". Falls back
  // to title-casing the key for unknown cities. City label is the pure city
  // name — country and state are rendered separately in the meta row.
  //
  // `displayCityMap` is the single memoization cache, rebuilt eagerly from
  // onCatalogChanged/onJournalChanged (never written from inside displayCity,
  // which is called from card bindings). It is seeded from cityMeta so mapped
  // keys resolve in one lookup; unknown keys fall back to a pure computation so
  // a binding read never mutates state.
  property var displayCityMap: Object.create(null)
  function buildDisplayCityMap() {
    var map = Object.create(null);
    var metaKeys = Object.keys(root.cityMeta);
    for (var metaIndex = 0; metaIndex < metaKeys.length; metaIndex++) {
      map[metaKeys[metaIndex]] = root.cityMeta[metaKeys[metaIndex]].name;
    }
    var cities = root.catalog.cities || [];
    for (var cityIndex = 0; cityIndex < cities.length; cityIndex++) {
      if (map[cities[cityIndex]] === undefined) map[cities[cityIndex]] = CatalogUtils.displayNameFor(cities[cityIndex]);
    }
    var journal = root.journal || [];
    for (var entryIndex = 0; entryIndex < journal.length; entryIndex++) {
      var city = journal[entryIndex].city;
      if (city && map[city] === undefined) map[city] = CatalogUtils.displayNameFor(city);
    }
    root.displayCityMap = map;
  }
  function displayCity(key) {
    var cached = root.displayCityMap[key];
    if (cached !== undefined) return cached;
    return CatalogUtils.displayNameFor(key);
  }

  // Human-readable summary of the active filters (city, type, unvisited, sort,
  // radius, neighborhood, search). Shared by the spotlight header and the
  // Surprise Me FAB tooltip so both describe the same current-filter state.
  // Declarative so the binding engine owns the recompute; the dependency list is
  // explicit because reads inside the compute function are not tracked.
  // dataRevision is listed because displayCity() reads the eagerly-rebuilt
  // displayCityMap, whose reassignment is not tracked through the function call.
  property string filterDescriptionData: {
    root.cityKey;
    root.kindFilter;
    root.unvisited;
    root.sortBy;
    root.radius;
    root.neighborhood;
    root.searchText;
    root.dataRevision;
    return root.computeFilterDescription();
  }
  function computeFilterDescription() {
    var desc = (root.cityKey ? root.displayCity(root.cityKey) : "All cities");
    if (root.kindFilter !== "all") desc += " · " + root.capitalize(root.kindFilter);
    if (root.unvisited) desc += " · Unvisited";
    if (root.sortBy !== "distance") desc += " · " + root.capitalize(root.sortBy);
    if (root.radius > 0) desc += " · Within " + root.radius + " km";
    if (root.neighborhood) desc += " · " + root.neighborhood;
    if (root.searchText) desc += " · \"" + root.searchText + "\"";
    return desc;
  }

  // Raw distance (km) from home to a city center. Uses cityMeta coordinates
  // when available, else falls back to the first spot's coords (Yelp cities
  // aren't in cityMeta). Returns Infinity when no home or no coords.
  function cityDistanceKm(cityKey) {
    if (!root.homeLat || !root.homeLon) return Infinity;
    var entry = root.cityMetaFor(cityKey);
    if (entry && entry.lat && entry.lon) return SpotUtils.haversine(root.homeLat, root.homeLon, entry.lat, entry.lon);
    var spots = root.catalog.spotsByCity && root.catalog.spotsByCity[cityKey] ? root.catalog.spotsByCity[cityKey] : [];
    for (var index = 0; index < spots.length; index++) {
      if (spots[index].lat && spots[index].lon) {
        return SpotUtils.haversine(root.homeLat, root.homeLon, spots[index].lat, spots[index].lon);
      }
    }
    return Infinity;
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
  // (spotDistance, isWithinRadius, computeLocationAggregates, the distance sort) fall
  // back to a fresh haversine on a miss, so an empty map during the build is
  // correct, just uncached. Declarative readers do not track distanceByCoords,
  // so the clear does not re-run them.
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
    chunkWalk.runChunked({
      getToken: function () { return root.distanceToken; },
      chunkSize: root.distanceChunkSize,
      ctx: ctx,
      step: function (ctx) {
        var spots = ctx.spotsByCity[ctx.cities[ctx.city]] || [];
        if (ctx.spot >= spots.length) {
          ctx.spot = 0;
          ctx.city++;
          return { processed: 0, more: ctx.city < ctx.cities.length };
        }
        var lat = spots[ctx.spot].lat || 0;
        var lon = spots[ctx.spot].lon || 0;
        var key = CatalogUtils.coordKey(lat, lon);
        if (ctx.staged[key] === undefined) ctx.staged[key] = SpotUtils.haversine(root.homeLat, root.homeLon, lat, lon);
        ctx.spot++;
        if (ctx.spot >= spots.length) {
          ctx.spot = 0;
          ctx.city++;
        }
        return { processed: 1, more: ctx.city < ctx.cities.length };
      },
      done: function (ctx) {
        root.distanceByCoords = ctx.staged;
        root.distanceVersion++;
      }
    }, root.distanceToken);
  }

  // Distance from home to a spot, formatted for display; empty when unknown.
  // Reads the shared per-coordinate cache (the same value the distance sort
  // uses), falling back to a fresh haversine for spots without a cached
  // coordinate (none in practice once the cache is built).
  function spotDistance(spot) {
    if (!root.homeLat || !root.homeLon) return "";
    if (!spot) return "";
    var cached = root.distanceByCoords[CatalogUtils.coordKey(spot.lat, spot.lon)];
    if (cached) return SpotUtils.formatDistance(cached);
    if (!spot.lat || !spot.lon) return "";
    return SpotUtils.formatDistance(SpotUtils.haversine(root.homeLat, root.homeLon, spot.lat, spot.lon));
  }

  // True when `root.radius` is active (>0) and the spot falls within it.
  // Reads the shared per-coordinate distance cache (same value the distance
  // sort uses), falling back to a fresh haversine on a cache miss.
  function isWithinRadius(spot) {
    if (!spot || !spot.lat || !spot.lon || !root.homeLat || !root.homeLon) return false;
    var key = CatalogUtils.coordKey(spot.lat, spot.lon);
    var cached = root.distanceByCoords[key];
    if (cached === undefined) cached = SpotUtils.haversine(root.homeLat, root.homeLon, spot.lat, spot.lon);
    return cached <= root.radius;
  }

  function matchesNeighborhood(spot) {
    if (!root.neighborhood) return true;
    return spot && (spot.neighborhood || "").toLowerCase() === root.neighborhood.toLowerCase();
  }

  // ---- Filtering ----

  // Shared global filter predicates (kind, city, radius, neighborhood,
  // unvisited) for a single spot. `spot` may be null (a name no longer in the
  // catalog); `cityKey` is the spot's city key ("" when unknown); `opts` toggles
  // per-caller predicates:
  //   city      — filter by root.cityKey against cityKey
  //   unvisited — hide spots that already have a rated journal entry
  //   name      — the name checked against the rating map (defaults to spot.name)
  function passesFilters(spot, cityKey, opts) {
    opts = opts || {};
    if (root.kindFilter !== "all" && (!spot || (spot._spotKind !== undefined ? spot._spotKind : SpotUtils.spotKind(spot)) !== root.kindFilter)) return false;
    if (opts.city && root.cityKey && cityKey !== root.cityKey) return false;
    if (root.radius > 0 && !root.isWithinRadius(spot)) return false;
    if (!root.matchesNeighborhood(spot)) return false;
    if (opts.unvisited && root.unvisited && root.averageRatingFor(opts.name || (spot ? spot.name : "")) !== null) return false;
    return true;
  }

  // City/neighborhood matches for the search dropdown. Returns
  // { type: "city", key, name, count } or { type: "neighborhood", key, name, cityKey, cityName, count }.
  // The per-city neighborhood tally is independent of the query, so it is
  // precomputed once per catalog version (neighborhoodSearchIndex) and this
  // function only filters the cached city names + neighborhood records + the
  // cached statesData — no per-keystroke rescan of all spots.
  function searchMatches(query) {
    var term = (query || "").toLowerCase().trim();
    if (term.length < 2) return [];
    var results = [];
    var index = root.neighborhoodSearchIndex;
    for (var cityIndex = 0; cityIndex < index.cities.length; cityIndex++) {
      var cityKey = index.cities[cityIndex];
      var cityName = index.names[cityKey];
      if (cityName.toLowerCase().indexOf(term) >= 0 || cityKey.indexOf(term) >= 0) {
        results.push({ type: "city", key: cityKey, name: cityName, count: index.counts[cityKey] });
      }
      var records = index.byCity[cityKey];
      for (var nbIdx = 0; nbIdx < records.length; nbIdx++) {
        var nb = records[nbIdx];
        if (nb.name.toLowerCase().indexOf(term) >= 0) {
          results.push({ type: "neighborhood", key: nb.key, name: nb.name, cityKey: nb.cityKey, cityName: nb.cityName, count: nb.count });
        }
      }
    }
    // State match (Yelp "state" field, e.g. "GA"): one result per state,
    // aggregated across all cities so "NY" appears once, not per city.
    var stateList = root.statesData;
    for (var stateIndex = 0; stateIndex < stateList.length; stateIndex++) {
      // `stateList` is [ { key, name, count } ] sorted by count desc.
      var stateHit = stateList[stateIndex];
      if (stateHit.name.toLowerCase().indexOf(term) >= 0) {
        results.push({ type: "state", key: stateHit.key, name: stateHit.name, cityKey: "", cityName: "", count: stateHit.count });
      }
    }
    return results;
  }

  // Precomputed search index: city names + spot counts (O(1) lookups) and, per
  // city, the neighborhood tally in first-seen order. Built by the same chunked
  // spot-index walk as spotsByName (refreshSpotIndex) so the ~5k-spot scan runs
  // in bounded slices instead of one synchronous pass in the catalogVersion
  // cascade. `byCity` keeps one record per (city, neighborhood) pair — a plain
  // neighborhood→record map would collapse the neighborhoods shared across
  // cities (e.g. "CBD"). Published atomically with spotsByName; the empty
  // structure below keeps readers safe before the first build completes.
  property var neighborhoodSearchIndex: ({ cities: [], names: Object.create(null), counts: Object.create(null), byCity: Object.create(null) })

  // Record one city's neighborhoods into the in-flight index ctx and
  // reset the per-city accumulators. Called from the chunked walk when a city's
  // spots are exhausted (including empty cities, which yield an empty record
  // list). Uses cityMetaFor/CatalogUtils.displayNameFor directly rather than
  // displayCity so it never depends on displayCityMap, which is rebuilt after
  // this walk starts.
  function recordCityNeighborhoods(ctx, cityKey) {
    ctx.ordered.push(cityKey);
    var meta = root.cityMetaFor(cityKey);
    ctx.names[cityKey] = (meta && meta.name) ? meta.name : CatalogUtils.displayNameFor(cityKey);
    var spots = ctx.spotsByCity[cityKey] || [];
    ctx.counts[cityKey] = spots.length;
    var records = [];
    for (var nbIdx = 0; nbIdx < ctx.nbOrder.length; nbIdx++) {
      var neighborhood = ctx.nbOrder[nbIdx];
      records.push({ key: neighborhood, name: neighborhood, cityKey: cityKey, cityName: ctx.names[cityKey], count: ctx.nbCounts[neighborhood] });
    }
    ctx.byCity[cityKey] = records;
    ctx.nbCounts = Object.create(null);
    ctx.nbOrder = [];
  }

  // Sorted rated journal entries (query + sort applied). Declarative so no
  // binding ever writes it. The dependency list is explicit because reads
  // inside the compute function are not tracked.
  property var sortedJournalData: {
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
    root.displayCityMap;
    root.homeLat;
    root.homeLon;
    return root.computeSortedJournal();
  }
  function computeSortedJournal() {
    var entries = root.ratedEntries.slice();
    var query = (root.journalQuery || "").toLowerCase().trim();
    if (query) {
      entries = entries.filter(function(entry) {
        return (entry.name || "").toLowerCase().indexOf(query) >= 0 ||
               root.displayCity(entry.city).toLowerCase().indexOf(query) >= 0 ||
               (entry.notes || "").toLowerCase().indexOf(query) >= 0 ||
               (entry.city || "").toLowerCase().indexOf(query) >= 0;
      });
    }
    // Global filters carried over from Explore (type/city/radius/neighborhood).
    // passesFilters matches the located spot, but the city predicate keys off
    // the journal entry's own `city` (not the located spot's catalog key) — the
    // same value the old inline filter compared against root.cityKey.
    entries = entries.filter(function(entry) {
      var located = root.locateSpot(entry.name, entry.city);
      return root.passesFilters(located ? located.spot : null, entry.city, { city: true });
    });
    if (root.sortBy === "date") {
      entries = root.sortJournalBy(entries, function(entry) {
        return entry.timestamp || 0;
      }, "date");
    } else if (root.sortBy === "rating") {
      entries = root.sortJournalBy(entries, function(entry) {
        return entry.rating || 0;
      }, "rating");
    } else if (root.sortBy === "price") {
      entries = root.sortJournalBy(entries, function(spot) {
        return SpotUtils.priceNumber(spot && spot.price);
      }, "price");
    } else {
      // distance (default) — same decorate-sort-undecorate strategy.
      entries = root.sortJournalBy(entries, function(spot) {
        return (spot && spot.lat && spot.lon && root.homeLat && root.homeLon) ? SpotUtils.haversine(root.homeLat, root.homeLon, spot.lat, spot.lon) : Infinity;
      }, "distance");
    }
    return entries;
  }

  function isMultiCityView() { return !root.cityKey || root.radius > 0; }

  // Decorate-sort-undecorate lives in catalog-utils (decoratedSort) so the
  // scalar sort is shared with the unit tests; the sortReversed flip is passed
  // explicitly at each call site below.
  //
  // Journal entries: resolve each entry's located spot once (locateSpot is
  // O(spots) per call), sort on the extracted values, then strip the decoration.
  // `extract` maps a located spot (or null) to its sort value.
  function sortJournalBy(entries, extract, key) {
    return CatalogUtils.decoratedSort(entries, function(entry) {
      var located = root.locateSpot(entry.name, entry.city);
      return extract(located ? located.spot : null);
    }, function(entry) { return entry; }, key, root.sortReversed);
  }

  // Spot arrays: extract each spot's sort key once, sort, then strip.
  function sortSpotsBy(spots, extract, key) {
    return CatalogUtils.decoratedSort(spots, extract, function(spot) { return spot; }, key, root.sortReversed);
  }

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
    root.unvisited;
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
    var spots = [];
    if (root.isMultiCityView()) {
      var cities = root.catalog.cities || [];
      for (var cityIndex = 0; cityIndex < cities.length; cityIndex++) {
        var citySpots = spotsForCity(cities[cityIndex]);
        for (var spotIndex = 0; spotIndex < citySpots.length; spotIndex++) {
          spots.push(citySpots[spotIndex]);
        }
      }
    } else {
      spots = spotsForCity(root.cityKey);
    }
    // Shared global predicates (type/radius/neighborhood/unvisited). City is
    // already enforced by the collection above; state/country stay local below.
    spots = spots.filter(function (spot) { return root.passesFilters(spot, spot._cityKey || "", { unvisited: true }); });
    if (root.stateFilter) {
      spots = spots.filter(function (spot) {
        return (spot.state || "").toUpperCase() === root.stateFilter.toUpperCase();
      });
    }
    if (root.countryFilter) {
      spots = spots.filter(function (spot) {
        return (spot.country || "").toUpperCase() === root.countryFilter.toUpperCase();
      });
    }
    if (root.sortBy === "price") {
      spots = root.sortSpotsBy(spots, function (spot) {
        return spot._priceNumber || (spot.yelp_price || "").length * 10;
      }, "price");
    } else if (root.sortBy === "distance") {
      var distances = root.distanceByCoords;
      spots = root.sortSpotsBy(spots, function (spot) {
        var cached = distances[CatalogUtils.coordKey(spot.lat, spot.lon)];
        // Fall back to a fresh haversine while the chunked cache is still
        // building (or for a coord it has not reached yet), so a re-run that
        // lands mid-build still sorts by real distance, never all-Infinity.
        if (cached === undefined) {
          if (!spot.lat || !spot.lon || !root.homeLat || !root.homeLon) return Infinity;
          return SpotUtils.haversine(root.homeLat, root.homeLon, spot.lat, spot.lon);
        }
        return cached;
      }, "distance");
    } else if (root.sortBy === "rating") {
      spots = root.sortSpotsBy(spots, function (spot) {
        return root.averageRatingFor(spot.name) || (spot.yelp_rating || 0);
      }, "rating");
    } else if (root.sortBy === "date") {
      spots = root.sortSpotsBy(spots, function (spot) {
        var journalEntry = root.latestJournalFor(spot.name);
        return journalEntry ? (journalEntry.timestamp || 0) : 0;
      }, "date");
    }
    return spots;
  }

  // Search post-filter over the base result. Declarative so the search pass
  // re-runs only when the base data, the query, or the city-name index changes.
  property var searchedSpots: {
    root.filteredSpots;
    root.searchText;
    root.neighborhoodSearchIndex;
    return root.computeSearchedSpots();
  }
  function computeSearchedSpots() {
    var spots = root.filteredSpots;
    if (!root.searchText) return spots;
    return CatalogUtils.applySearchFilter(spots, root.searchText, root.neighborhoodSearchIndex.names);
  }

  // Only the first `visibleCount` cards render — keeps delegate instantiation
  // cheap for the 3k+ spot dataset. "Show more" extends the window. Declarative
  // so the slice is reused across unrelated re-evaluations: it re-runs only when
  // the searched result or the window size actually changes, never on a bare
  // dataRevision bump.
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
  // ListView binds `model: root.exploreSpots`. The handler fires only when
  // pagedSpots is reassigned (filter/search/window change), so the model is
  // stable across unrelated re-evaluations.
  property var exploreSpots: []
  onPagedSpotsChanged: root.exploreSpots = root.pagedSpots

  // Journal/Wishlist list-model snapshots, mirroring exploreSpots. Each
  // ListView binds `model:` to this plain array; the handler snapshots the
  // declarative result whenever it is reassigned, so the model binding never
  // re-enters a reactive compute path (and never needs dataRevision as a
  // manual invalidation dep).
  property var journalModel: []
  onSortedJournalDataChanged: root.journalModel = root.sortedJournalData
  property var wishlistModel: []
  onFilteredWishlistChanged: root.wishlistModel = root.filteredWishlist

  // Saved spot names after the shared Explore filters + wishlist query.
  // Declarative so the binding engine owns the recompute (the old function-call
  // binding re-ran on every dataRevision bump). The dependency list is explicit
  // because reads inside the compute function are not tracked. spotsByName is
  // reassigned whole when the catalog changes, so it is a tracked dep on its own
  // — no dataRevision bump is needed to observe it. distanceVersion is the
  // distance-map trigger (see filteredSpots); homeLat/homeLon are not listed
  // because they change with the catalog and would re-run this against the
  // empty map before the build completes.
  property var filteredWishlist: {
    root.saved;
    root.wishlistQuery;
    root.kindFilter;
    root.cityKey;
    root.radius;
    root.neighborhood;
    root.unvisited;
    root.spotsByName;
    root.ratingsBySpot;
    root.distanceVersion;
    root.displayCityMap;
    return root.computeFilteredWishlist();
  }
  function computeFilteredWishlist() {
    var names = root.saved.slice();
    // Global filters carried over from Explore (shared with filteredSpots).
    names = names.filter(function(name) {
      var located = root.locateSpot(name, "");
      return root.passesFilters(located ? located.spot : null, located ? located.cityKey : "", { city: true, unvisited: true, name: name });
    });
    var query = (root.wishlistQuery || "").toLowerCase().trim();
    if (!query) return names;
    return names.filter(function(name) {
      if (name.toLowerCase().indexOf(query) >= 0) return true;
      var located = root.locateSpot(name, "");
      var spot = located ? located.spot : null;
      if (!spot) return false;
      if ((spot.neighborhood || "").toLowerCase().indexOf(query) >= 0) return true;
      var cityKey = located.cityKey;
      if (cityKey && root.displayCity(cityKey).toLowerCase().indexOf(query) >= 0) return true;
      return false;
    });
  }

  // ---- Navigation ----

  // Pick a random spot from the current filter results and open the spotlight
  // view on it. Returns true when at least one candidate exists.
  function surpriseMe() {
    var pool = root.searchedSpots;
    if (pool.length === 0) return false;
    var pick = pool[Math.floor(Math.random() * pool.length)];
    root.spotlightEntry = pick;
    root.expandedSpotName = pick.name;
    root.spotlight = true;
    var journalEntry = root.latestJournalFor(pick.name);
    root.editStars = journalEntry ? journalEntry.rating : 0;
    root.editNotes = journalEntry ? journalEntry.notes : "";
    return true;
  }

  // Collapse any expanded row and reset its rating state.
  function collapseRow() {
    root.expandedSpotName = null;
    root.editStars = 0;
    root.editNotes = "";
  }

  // Toggle a row's expanded state; tapping the expanded row collapses it.
  function toggleRow(spotName, stars, notes) {
    if (root.expandedSpotName === spotName) {
      root.collapseRow();
    } else {
      root.expandedSpotName = spotName;
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
  // The picked scope is set to `value`; every other scope is cleared. A
  // neighborhood also carries its city key, so it sets both.
  function applyLocationScope(scope, value) {
    root.cityKey = (scope === "city" || scope === "neighborhood") ? value : "";
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

  // Clear every Explore filter back to its default and close any open dropdown.
  function resetFilters() {
    root.kindFilter = "all";
    root.sortBy = "distance";
    root.sortReversed = false;
    root.unvisited = false;
    root.applyLocationScope("", "");
  }

  // ---- Utility ----

  // Unique neighborhood names for the current city, sorted, "" (All) first.
  // Declarative so no binding ever writes it; it is a pure read. Depends on the
  // catalog too (a city's neighborhoods come from its spots), hence catalogVersion.
  property var neighborhoodOptions: {
    root.cityKey;
    root.catalogVersion;
    return root.computeNeighborhoodOptions();
  }
  function computeNeighborhoodOptions() {
    var result = [""];
    if (root.cityKey) {
      var spots = spotsForCity(root.cityKey);
      var seenNeighborhoods = Object.create(null);
      for (var spotIndex = 0; spotIndex < spots.length; spotIndex++) {
        var neighborhood = (spots[spotIndex].neighborhood || "").trim();
        if (neighborhood && !seenNeighborhoods[neighborhood]) seenNeighborhoods[neighborhood] = true;
      }
      result = [""].concat(Object.keys(seenNeighborhoods).sort());
    }
    return result;
  }

  // One catalog pass builds both the state and country count maps plus the
  // single nearest-to-home value for each field. The old code ran
  // aggregateByField twice, scanning every spot and re-running the nearest
  // distance comparison per field; this walks the catalog once. `stateCounts`
  // is restricted to US 2-letter codes (root.usStates); `countryCounts` counts
  // every non-empty country. Returns { stateCounts, countryCounts,
  // nearestState, nearestCountry }.
  function computeLocationAggregates() {
    var stateCounts = Object.create(null);
    var countryCounts = Object.create(null);
    var nearestState = "";
    var nearestCountry = "";
    var nearestDistance = Infinity;
    var distances = root.distanceByCoords;
    var usStates = root.usStates;
    var cities = root.catalog.cities || [];
    for (var cityIndex = 0; cityIndex < cities.length; cityIndex++) {
      var spots = root.catalog.spotsByCity && root.catalog.spotsByCity[cities[cityIndex]] ? root.catalog.spotsByCity[cities[cityIndex]] : [];
      for (var spotIndex = 0; spotIndex < spots.length; spotIndex++) {
        var spot = spots[spotIndex];
        var stateValue = (spot.state || "").trim().toUpperCase();
        if (stateValue && usStates[stateValue]) stateCounts[stateValue] = (stateCounts[stateValue] || 0) + 1;
        var countryValue = (spot.country || "").trim().toUpperCase();
        if (countryValue) countryCounts[countryValue] = (countryCounts[countryValue] || 0) + 1;
        // Track the value of the spot nearest home (for the "current" first
        // entry). Only meaningful when home coords are known.
        if (root.homeLat && root.homeLon && spot.lat && spot.lon) {
          var distanceKm = distances[CatalogUtils.coordKey(spot.lat, spot.lon)];
          if (distanceKm === undefined) distanceKm = SpotUtils.haversine(root.homeLat, root.homeLon, spot.lat, spot.lon);
          if (distanceKm < nearestDistance) {
            nearestDistance = distanceKm;
            nearestState = stateValue;
            nearestCountry = countryValue;
          }
        }
      }
    }
    return { stateCounts: stateCounts, countryCounts: countryCounts, nearestState: nearestState, nearestCountry: nearestCountry };
  }

  // Only US states (2-letter codes) are surfaced as "state" filters. Yelp
  // returns region codes for non-US cities (e.g. "VIC" for Melbourne, "11"
  // for Lisbon) which are not states and would clutter the picker.
  readonly property var usStates: ({
    "AL":1,"AK":1,"AZ":1,"AR":1,"CA":1,"CO":1,"CT":1,"DE":1,
    "FL":1,"GA":1,"HI":1,"ID":1,"IL":1,"IN":1,"IA":1,"KS":1,"KY":1,"LA":1,
    "ME":1,"MD":1,"MA":1,"MI":1,"MN":1,"MS":1,"MO":1,"MT":1,"NE":1,"NV":1,
    "NH":1,"NJ":1,"NM":1,"NY":1,"NC":1,"ND":1,"OH":1,"OK":1,"OR":1,"PA":1,
    "RI":1,"SC":1,"SD":1,"TN":1,"TX":1,"UT":1,"VT":1,"VA":1,"WA":1,"WV":1,
    "WI":1,"WY":1,"DC":1
  })

  // Single-pass state + country aggregation, shared by statesData and
  // countriesData so the catalog is scanned once instead of twice. Declarative
  // so no binding ever writes it; it is a pure read. distanceVersion is the
  // catalog trigger (see filteredSpots) so the nearest-value ordering never
  // reads the empty map installed at the start of a catalog/home change.
  property var locationAggregatesData: {
    root.distanceVersion;
    return root.computeLocationAggregates();
  }

  // States present in the catalog (from Yelp "state" field), each aggregated
  // across all cities with its spot count, sorted alphabetically with the
  // nearest state first. Result is [{ key, name, count }].
  property var statesData: {
    root.locationAggregatesData;
    var aggregates = root.locationAggregatesData;
    return CatalogUtils.aggregateList(aggregates.stateCounts, aggregates.nearestState);
  }

  // Countries present in the catalog (Yelp "country" field), aggregated across
  // all cities with spot counts, sorted alphabetically with the nearest country
  // first. [{ key, name, count }].
  property var countriesData: {
    root.locationAggregatesData;
    var aggregates = root.locationAggregatesData;
    return CatalogUtils.aggregateList(aggregates.countryCounts, aggregates.nearestCountry);
  }

  // Cities ordered by distance from home (nearest first); geo-less cities last.
  // Declarative so the 65 cityDistanceKm() haversines run once per catalog/home
  // change instead of on every cityFilterItemsData evaluation. Depends on
  // catalogVersion (city list + fallback coords) and home (distance).
  property var sortedCitiesData: {
    root.catalogVersion;
    root.homeLat;
    root.homeLon;
    return root.computeSortedCities();
  }
  function computeSortedCities() {
    // Decorate-sort-undecorate: resolve each city's distance once (O(n)) instead
    // of twice per comparison (O(n log n)), sort on the scalars, then strip the
    // decoration. Mirrors sortSpotsBy.
    var cities = root.catalog.cities || [];
    var decorated = cities.map(function (cityKey) {
      return { key: cityKey, distance: root.cityDistanceKm(cityKey) };
    });
    decorated.sort(function (first, second) { return first.distance - second.distance });
    return decorated.map(function (record) { return record.key });
  }

  // FilterDropdown item lists — { key, label } pairs consumed by the generic
  // dropdown. Labels are baked here (single source) so each call site passes
  // `items` directly. Declarative properties (not functions) so the four
  // FilterPanel instances share one build per catalog/filter change instead of
  // rebuilding the arrays on every evaluation. Each lists its source data as an
  // explicit dep because reads inside the map callbacks are not tracked.
  property var cityFilterItemsData: {
    root.sortedCitiesData;
    root.catalogVersion;
    return root.sortedCitiesData.map(function (key) {
      var meta = root.cityMetaFor(key) || {};
      var count = (root.catalog.spotsByCity && root.catalog.spotsByCity[key]) ? root.catalog.spotsByCity[key].length : 0;
      var distanceKm = root.cityDistanceKm(key);
      var distance = isFinite(distanceKm) ? SpotUtils.formatMiles(SpotUtils.kmToMiles(distanceKm)) : "";
      var label = (meta.name || root.displayCity(key)) + (distance ? " · " + distance : "") + " · " + count + " spots";
      return { key: key, label: label };
    });
  }

  property var stateFilterItemsData: {
    root.statesData;
    return root.statesData.map(function (state) {
      return { key: state.key, label: state.name + " · " + state.count + " spots" };
    });
  }

  property var countryFilterItemsData: {
    root.countriesData;
    return root.countriesData.map(function (country) {
      return { key: country.key, label: country.name + " · " + country.count + " spots" };
    });
  }

  property var neighborhoodFilterItemsData: {
    root.neighborhoodOptions;
    return root.neighborhoodOptions.map(function (nb) {
      return { key: nb, label: nb === "" ? "All neighborhoods" : nb };
    });
  }

  // Open a URL only for an allowed scheme, guarding against arbitrary schemes
  // smuggled in through seed/user data. The scheme is parsed (not prefix-
  // matched) so case is normalized once, and the same normalized string is
  // what gets opened. Only https:// and a validated tel: number are allowed;
  // cleartext http:// is rejected.
  function openUrl(url) {
    if (!url) return;
    var target = String(url).trim();
    var match = target.match(/^([a-z][a-z0-9+.\-]*):(.*)$/i);
    if (!match) return; // no scheme — reject
    var scheme = match[1].toLowerCase();
    if (scheme === "https") {
      Qt.openUrlExternally("https:" + match[2]);
      return;
    }
    if (scheme === "tel") {
      // A phone number may only carry a leading "+", digits, and phone
      // punctuation. Anything else could smuggle a payload, so reject it.
      var number = match[2].trim();
      if (/^\+?[0-9()\-\s]+$/.test(number)) Qt.openUrlExternally("tel:" + number);
    }
  }

  // The memoized values above are declarative properties, so the binding engine
  // re-evaluates them from their tracked inputs. `dataRevision` remains as the
  // async spotsByName completion signal and as an explicit dep of
  // filterDescriptionData (whose displayCity read is not tracked through the
  // function call); it is bumped on any filter change.
  property int dataRevision: 0
  property int catalogVersion: 0
  // Post-search spot count for the scroll handler. Reads the declarative
  // searched result directly, so it re-evaluates only when that result changes.
  readonly property int filteredCount: root.searchedSpots.length
  // Reset the paging window and bump the data revision — the two steps every
  // filter change needs so dependent bindings re-run. The declarative caches
  // re-evaluate on their own tracked inputs; no manual invalidation needed.
  function resetListWindow() { visibleCount = pageSize; dataRevision++ }
  // Prefetch: add a full page at once, then re-check the lookahead on the next
  // event-loop turn. `prefetching` is cleared once the lookahead is
  // satisfied or the list is exhausted, letting the next scroll event start a
  // fresh fill.
  function fillPrefetch() {
    visibleCount += pageSize;
    var pagePx = pageSize * collapsedCardHeight;
    var remaining = exploreTab ? exploreTab.contentHeight - (exploreTab.contentY + exploreTab.height) : 0;
    if (remaining < pagePx && visibleCount < filteredCount) {
      Qt.callLater(root.fillPrefetch);
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
  onSearchTextChanged: resetListWindow()
  onUnvisitedChanged: resetListWindow()
  onStateFilterChanged: resetListWindow()
  onCountryFilterChanged: resetListWindow()
  // Journal data feeds ratedEntries/sortedJournalData (declarative) and the
  // eagerly-maintained rating maps; rebuild those maps and the display-city map.
  onJournalChanged: { refreshRatings(); buildDisplayCityMap(); dataRevision++ }
  onSavedChanged: refreshSavedSet()
  // Neighborhood list derives from catalog data, not just cityKey.
  onCatalogChanged: {
    refreshSpotIndex();
    refreshDistanceCache();
    buildDisplayCityMap();
    dataRevision++;
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
    contentHeight: root.spotlight ? (spotlightCol.implicitHeight + panel.verticalContentInset) : Math.min(contentColumn.implicitHeight + panel.verticalContentInset, root.maxPanelHeight)
    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        // On Explore the ListView is the only scroller, so the outer Flickable
        // is pinned to the panel cap (no scroll) and made non-interactive.
        contentHeight: root.spotlight ? spotlightCol.implicitHeight : ((root.tab === "explore") ? root.maxPanelHeight : contentColumn.implicitHeight)
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
          id: contentColumn
          // MUST be bound to the Flickable width: children use `width:
          // parent.width, and an unbound Column collapses to its implicit
          // width (~0), which renders the whole popup empty.
          width: flick.width
          visible: !root.spotlight
          spacing: Style.space(10)
          padding: Style.space(16)
          // No bottom clearance: the Explore ListView extends to the panel
          // bottom and the Surprise Me / back-to-top FABs float over it.
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
        id: backToTop
        z: 10
        visible: exploreTab && exploreTab.contentY > root.backToTopThreshold && root.tab === "explore" && !root.spotlight
        anchors.right: parent.right; anchors.rightMargin: Style.space(16)
        anchors.bottom: fab.top; anchors.bottomMargin: Style.space(12)
        width: 40; height: 40
        radius: 20
        color: root.accentTint
        border.color: root.accentColor
        border.width: 1
        opacity: 0.85
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

      Rectangle {
        id: fab
        z: 10
        visible: root.tab === "explore" && !root.spotlight
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.margins: Style.space(16)
        width: fabText.implicitWidth + Style.space(28)
        height: Style.space(44)
        radius: Style.space(22)
        color: root.accentColor
        Text {
          textFormat: Text.PlainText
          id: fabText
          anchors.centerIn: parent
          text: "Surprise Me"
          color: root.accentTextColor
          font.bold: true
          font.pixelSize: Style.font.bodySmall
        }
        Rectangle {
          visible: fabHover.hovered
          anchors.bottom: parent.top
          anchors.bottomMargin: Style.space(6)
          anchors.horizontalCenter: parent.horizontalCenter
          width: tooltipText.width + Style.space(16)
          height: tooltipText.implicitHeight + Style.space(12)
          radius: Style.cornerRadius
          color: Qt.rgba(0, 0, 0, 0.8)
          Text {
            textFormat: Text.PlainText
            id: tooltipText
            anchors.centerIn: parent
            text: "Random spot from: " + root.filterDescriptionData
            color: "#fff"
            font.pixelSize: Style.font.caption
            width: fab.width * 2
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
          }
        }
        HoverHandler { id: fabHover }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.surpriseMe()
        }
      }
    }
  }
}
