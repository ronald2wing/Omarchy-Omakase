import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "spot-utils.js" as SpotUtils
import "catalog-utils.js" as CatalogUtils
import "journal-identity.js" as JournalIdentity
import "components"

Panel {
  id: root
  moduleName: "omakase"
  manageIpc: false

  // State directory read by the FileViews below (Service owns every write).
  readonly property string stateDir: Quickshell.env("HOME") + SpotUtils.STATE_DIR_SUFFIX

  // ---- Panel state ----
  property var catalog: ({ cities: [], spotsByCity: Object.create(null), homeLat: 0, homeLon: 0 })
  property var journal: []
  property string cityKey: ""
  // RAW Explore search text, written by the Explore field on every keystroke.
  // Two consumers diverge from it: the search dropdown reads the raw value (via
  // activeViewQuery) so suggestions stay instant, while the card-list search
  // chain reads debouncedSearchText (next) so the expensive full-catalog rank
  // trails typing.
  property string searchText: ""
  // Debounced copy of searchText that ONLY the card-list search chain reads.
  // Typing updates searchText instantly, but this lands searchDebounceMs after
  // the last keystroke, so the full-catalog rank re-runs once per pause, not
  // once per keystroke. Clearing the field flushes immediately
  // (onSearchTextChanged). The Timer handler assigns debouncedSearchText
  // imperatively, never from inside a binding, so it stays clear of the
  // declarative cache model.
  property string debouncedSearchText: ""
  // Dismissal flag for the search-suggestions dropdown (city/neighborhood/state
  // matches). A plain bool, NOT readonly — a readonly binding freezes at
  // creation. Set true by Escape, the dropdown's query row, a card click, a
  // place-row pick, a Surprise me click, or a tab switch; reset to false on a
  // search/query change (typing) so typing re-opens the suggestions. One flag
  // gates all four views' dropdowns (Explore, Wishlist, Journal, Spotlight).
  // Written only from handlers, never inside a binding.
  property bool searchSuggestionsDismissed: false

  // Active search view + its query + the dropdown hits, shared by the four
  // SearchSuggestionsDropdown instances (Explore, Wishlist, Journal, Spotlight).
  // activeSearchView names the view whose search field is on screen; each
  // instance's `active` flag compares against it so only the active view's
  // dropdown is ever visible. `spotlight` wins over `tab` because the
  // spotlight overlays the other tabs while they remain mounted.
  readonly property string activeSearchView: root.spotlight ? CatalogUtils.VIEW_SPOTLIGHT : root.tab

  // Which view's pinned chrome (chip highlight, search field, dropdown, filter
  // panel) is on screen. Spotlight reuses Explore's chrome because both search
  // the whole catalog; otherwise it is the active tab.
  readonly property string chromeView: root.spotlight ? CatalogUtils.VIEW_EXPLORE : root.tab
  // The Explore tab is the on-screen, non-Spotlight list view; the outer
  // Flickable's interactivity and the back-to-top FAB both gate on it.
  readonly property bool exploreActive: root.tab === CatalogUtils.VIEW_EXPLORE && !root.spotlight

  // The query the active view's search field owns, reading the RAW value (never
  // the debounced copy): Explore and Spotlight share searchText; Wishlist and
  // Journal carry their own query properties. The dropdown reads this so
  // suggestions stay instant while the card list trails by searchDebounceMs.
  // The condition reads root.spotlight and root.tab on every evaluation, so
  // this re-runs when the view or the query changes.
  readonly property string activeViewQuery: {
    if (root.spotlight) return root.searchText;
    if (root.tab === CatalogUtils.VIEW_WISHLIST) return root.wishlistQuery;
    if (root.tab === CatalogUtils.VIEW_JOURNAL) return root.journalQuery;
    return root.searchText;
  }

  // The active view's location bundle — the single geography source feeding
  // both the search dropdown (activeSearchHits) and the filter sheet's option
  // builders (cityFilterItems/stateFilterItems/countryFilterItems/
  // neighborhoodOptions), so the two can never disagree about what geography a
  // view contains. Explore and Spotlight stay catalog-wide: the bundle is
  // assembled from the chunked searchIndex + stateOptions + countries +
  // locationAggregates. Wishlist and Journal use their scoped bundles
  // (wishlistSearch/journalSearch, from CatalogUtils.buildScopedSearchIndex),
  // which count only the user's saved/rated spots — the same source the search
  // dropdown reads, so the sheet's option counts match the list being filtered.
  // The dependency list is explicit because the reads inside the branch are
  // otherwise untracked; chromeView (spotlight -> explore) names the on-screen
  // view.
  readonly property var activeLocationBundle: {
    root.chromeView;
    root.searchIndex;
    root.stateOptions;
    root.countries;
    root.locationAggregates;
    root.wishlistSearch;
    root.journalSearch;
    if (root.chromeView === CatalogUtils.VIEW_WISHLIST) return root.wishlistSearch;
    if (root.chromeView === CatalogUtils.VIEW_JOURNAL) return root.journalSearch;
    // The catalog-wide bundle is assembled through CatalogUtils.buildLocationBundle —
    // the same shaper buildScopedSearchIndex uses, so the two producers cannot
    // drift to different field sets.
    return CatalogUtils.buildLocationBundle({
      cities: root.searchIndex.cities,
      names: root.searchIndex.names,
      counts: root.searchIndex.counts,
      byCity: root.searchIndex.byCity,
      foldedNames: root.searchIndex.foldedNames,
      foldedKeys: root.searchIndex.foldedKeys,
      states: root.stateOptions,
      countries: root.countries,
      stateDistances: root.locationAggregates.stateDistances
    });
  }

  // City/neighborhood/state matches for the active view's query, scoped per
  // tab: Wishlist derives geography only from saved spots, Journal only from
  // rated spots, Explore and Spotlight stay catalog-wide. activeLocationBundle
  // is the per-view source (listed explicitly because the reads inside the
  // injected distance resolvers are not tracked), so the hits re-evaluate when a
  // catalog rebuild, home move, or saved/rated change republishes it; activeViewQuery
  // and activeLocationBundle are the per-view inputs (a view switch already
  // republishes the bundle, so activeSearchView is not listed here).
  readonly property var activeSearchHits: {
    root.activeViewQuery;
    root.activeLocationBundle;
    var query = root.activeViewQuery;
    var bundle = root.activeLocationBundle;
    return CatalogUtils.buildSearchHits(query, bundle, bundle.states, bundle.stateDistances, root.cityDistanceKm, root.neighborhoodDistanceKm);
  }

  // Whether any search field currently owns keyboard focus. The Explore field
  // is shared by Explore and Spotlight (chromeView); Wishlist and Journal each
  // carry their own via TabSearchHeader. At most one field is visible at a time,
  // so this aggregate names the single engaged field. `keyCatcher.blocked` reads
  // the same aggregate to route keys to the focused field.
  readonly property bool searchFieldHasFocus:
    exploreHeader.hasFocus || wishlistHeader.hasFocus || journalHeader.hasFocus

  // Whether the suggestions dropdown should be open for the active view. A
  // non-empty hit list, no city scope, the dismissal flag clear, and a search
  // field actually engaged: without the focus gate the dropdown lingers after
  // focus leaves the field (a Surprise me click, a tab switch), covering the
  // Spotlight card with its dismiss overlay.
  readonly property bool searchSuggestionsVisible:
    root.searchFieldHasFocus
    && root.activeSearchHits.length > 0
    && !root.cityKey
    && !root.searchSuggestionsDismissed
  readonly property int searchDebounceMs: 150
  property string kindFilter: CatalogUtils.KIND_FILTER_ALL
  // CatalogUtils.SORT_KEYS[0] ("distance") is the default sort key.
  property string sortBy: CatalogUtils.SORT_KEYS[0]
  property bool sortReversed: false
  property string journalQuery: ""
  property string wishlistQuery: ""
  property string tab: CatalogUtils.VIEW_EXPLORE
  property bool unratedOnly: false
  property string neighborhood: ""
  property string stateFilter: ""  // US state code filter (e.g. "GA"); "" = all
  property string countryFilter: ""  // country filter (e.g. "US"); "" = all
  property int radius: 0  // 0 = off; the km steps live in catalog-utils.js
  // Which filter dropdown is open ("" = none). One string replaces the four
  // per-filter booleans so the FilterSheet rows share a single toggle helper.
  property string openDropdown: ""
  // Whether the floating Filters sheet is open. The sheet holds the location
  // scopes; the primary row stays visible.
  property bool openSheet: false
  // True when any filter owned by the sheet is set. Drives the Filters button's
  // active state. The Radius pill lives in the primary row now, so it is not a
  // sheet filter.
  readonly property bool hasSheetFilters: root.cityKey !== "" || root.stateFilter !== "" || root.countryFilter !== "" || root.neighborhood !== ""
  // True when ANY filter or location scope is active: the sheet's four location
  // scopes (hasSheetFilters) plus the three non-sheet filters (radius, kind,
  // unrated). The both-active empty states key off this so a state/country/
  // neighborhood/radius/kind/unrated filter can never leave the "clear search
  // and filters" action missing (the previous cityKey-only gate missed them all).
  readonly property bool hasActiveFilters:
    root.hasSheetFilters ||
    root.radius > 0 ||
    root.kindFilter !== CatalogUtils.KIND_FILTER_ALL ||
    root.unratedOnly
  // Collapsing the sheet also drops any open option list, so reopening it never
  // shows a stale dropdown.
  onOpenSheetChanged: if (!root.openSheet) root.openDropdown = ""
  // Saved spots as { name, city } objects — city is the canonical catalog slug
  // when resolvable, "" for a name that resolved to nothing (the deliberate
  // wildcard mirroring findJournalIndex's name-only fallback). Array order is
  // save order; every reader re-sorts. Mirrors the journal's name-first +
  // city-disambiguating shape.
  property var saved: []
  // Canonical city slug map (alias token -> slug), rebuilt on every catalog load
  // so canonicalCityKey resolves against the current catalog.
  property var cityAliases: Object.create(null)
  // True once the chunked spot index (spotsByName) is fully built. Gates the
  // write-free -> resolving wishlist migration so it never stamps entries with
  // city:"" before the index exists.
  property bool spotIndexReady: false
  // journalSpotKey (normalized name + canonical city) -> true set for entries
  // that HAVE a city, and normalized-name -> true set for entries whose city is
  // empty — both rebuilt whenever `saved` changes so isSaved() is O(1) instead
  // of an O(saved) indexOf scan per card. Null-prototype so a saved name like
  // "constructor" can't collide with Object.prototype.
  property var savedByCitySet: Object.create(null)
  property var savedNameOnlySet: Object.create(null)
  property bool spotlight: false
  property var spotlightSpot: null
  property var expandedSpotName: null  // spot name that is expanded, or null
  // Auto-save notes staging: stars commit immediately (rateSpot), notes stage
  // here and commit on a debounce via flushNotes(). A single pending tuple + a
  // single debounce timer, so a repeat keystroke restarts the one in-flight
  // commit rather than stacking (the same restart idiom CopyFeedback.qml uses).
  property int notesDebounceMs: 600
  property string _pendingNotesName: ""
  property string _pendingNotesCity: ""
  property string _pendingNotesText: ""
  // Transient "Saved" confirmation for the rating editor: set true by
  // flushNotes() on a real notes commit and reset after the shared copy
  // feedback duration; the editor binds its label visibility to this.
  property bool notesJustSaved: false
  // Restarted by notesEdited() on every keystroke; onTriggered commits the
  // staged notes through flushNotes().
  Timer {
    id: notesDebounceTimer
    interval: root.notesDebounceMs
    repeat: false
    onTriggered: root.flushNotes()
  }
  // Auto-reset for the "Saved" label; flushNotes() restarts it on each commit
  // (the same restart idiom CopyFeedback.qml uses).
  Timer {
    id: notesSavedTimer
    interval: root.copyFeedbackMs
    repeat: false
    onTriggered: root.notesJustSaved = false
  }
  // The spotlight Back link tears the editor down without going through
  // collapseRow() — it clears expandedSpotName directly — so flush on any
  // expandedSpotName -> null transition as a safety net. collapseRow() flushes
  // first, so every other teardown path is a no-op here.
  onExpandedSpotNameChanged: {
    if (root.expandedSpotName === null) root.flushNotes();
  }
  // Neighborhood chip strip cap: cities whose "neighborhoods" are really
  // address fragments (Nagoya chōme) produce hundreds of chips that wall off
  // the panel, so the strip hides and falls back to the dropdown.
  readonly property int maxNeighborhoodChips: 12
  // Show the neighborhood chip strip only when a city is selected and its
  // neighborhood list is small enough to render as chips.
  readonly property bool neighborhoodChipsVisible: root.hasNeighborhoodFilter && root.neighborhoodOptions.length <= root.maxNeighborhoodChips
  // Whether the selected city has neighborhoods worth filtering by. Gates the
  // Neighborhood row in FilterSheet (and its dropdown): a city with no
  // neighborhoods (or none selected) never surfaces a dead neighborhood filter.
  // neighborhoodChipsVisible (above) adds the chip-size cap on top of this, so the
  // cap condition lives in exactly one place.
  readonly property bool hasNeighborhoodFilter: root.cityKey !== "" && root.neighborhoodOptions.length > 0
  // Back-to-top FAB appears as soon as the list is really scrolled; a small
  // dead zone absorbs sub-pixel jitter without hiding the arrow on a real scroll.
  readonly property real backToTopScrollThreshold: Style.space(16)
  // Cap on the panel height; the Flickable scrolls past it.
  readonly property real maxPanelHeight: Style.space(640)
  // Pinned header above the scroller: top padding + the pinned column's own
  // height + gap to the content below. The tab chips + Surprise Me pill always
  // live here; every view's search field and FilterBar primary row join them
  // (Spotlight reuses Explore's chrome), so search/filter stay reachable while
  // the list scrolls. The column's own top padding is 0 (this header owns it).
  //
  // The height is read from the pinned column's implicitHeight rather than a
  // fixed constant: the FilterBar's active-filter summary line is variable
  // height, and the per-view search/filter chrome is visible-gated:
  // hidden children with explicit heights are excluded from the Column's
  // implicitHeight.
  // pinnedColumn's children never depend on this property, so there is no
  // binding cycle.
  readonly property real pinnedHeaderHeight: Style.space(16) + pinnedColumn.implicitHeight + Style.space(10)
  // Bounded height for the Explore ListView: the panel cap minus the card's
  // real vertical chrome (popup padding + border, from KeyboardPanel) and the
  // pinned header. The search field + FilterBar are pinned (not in the ListView
  // header), so they are subtracted here; only the CityHeader + neighborhood
  // chips remain in the ListView header and consume viewport space. The list
  // extends to the panel bottom; the back-to-top FAB floats over it.
  // Floor so the list keeps a usable height even when the panel cap minus the
  // pinned header and popup chrome would collapse it.
  readonly property real exploreListMinHeight: Style.space(200)
  readonly property real exploreListHeight: Math.max(root.exploreListMinHeight, root.maxPanelHeight - panel.verticalContentInset - root.pinnedHeaderHeight)
  // Height of the ACTIVE tab's content, excluding the column's own padding.
  // Read the active tab explicitly rather than the content Column's
  // implicitHeight, which sums all three tabs and would always size the panel
  // to the tallest, leaving Wishlist/Journal with dead space. Wishlist/Journal
  // report their real content height (their inner ListView is height:
  // contentHeight); Explore reports its live list height, which shrinks to fit
  // a short result set (exploreListMinHeight is the floor only while the list is
  // empty, so a non-empty short list collapses to its cards exactly like
  // Wishlist/Journal) and stays at the full viewport height when the content
  // scrolls — capped by maxPanelHeight below.
  readonly property real activeTabHeight: {
    if (root.tab === CatalogUtils.VIEW_WISHLIST) return wishlistTab.implicitHeight
    if (root.tab === CatalogUtils.VIEW_JOURNAL) return journalTab.implicitHeight
    return exploreTab.height
  }
  // How long the Copy pill's "Copied" feedback shows before reverting.
  readonly property int copyFeedbackMs: 1500
  // Whether a `tel:` URI handler is registered, probed once at load via
  // `xdg-mime query default x-scheme-handler/tel`. False is both the pre-probe
  // default and the every-failure-mode result (empty output, non-zero exit,
  // missing binary — on which QProcess emits errorOccurred without finished,
  // so the probe's onExited never fires), so the Call pill can never regress
  // into launching a browser for an unhandled `tel:`.
  property bool telHandlerAvailable: false

  // ---- Theme-derived colors ----
  readonly property color foregroundColor: root.bar ? root.bar.foreground : "#fff"
  readonly property color accentColor: (root.bar && root.bar.activeColor) ? root.bar.activeColor : "#44aaff"
  // Intentionally fixed white: rendered on the accent fill, so it stays legible
  // regardless of the theme-derived accent color.
  readonly property color accentTextColor: "#fff"
  readonly property color secondaryColor: Qt.darker(root.foregroundColor, 1.6)
  // These three read root.foregroundColor only through foregroundAlpha(), a
  // plain function call whose body is not tracked by QML's dependency capture
  // (the same trap as mapToItem): without an explicit tracked read of
  // foregroundColor they would go stale across a runtime theme change while
  // secondaryColor (which reads Qt.darker(root.foregroundColor) inline) updates.
  // The bare read registers the dependency; the value still flows through
  // foregroundAlpha so the alpha stays single-sourced.
  readonly property color cardBackground: {
    root.foregroundColor;
    return root.foregroundAlpha(0.06);
  }
  readonly property color cardHoverBackground: {
    root.foregroundColor;
    return root.foregroundAlpha(0.12);
  }
  readonly property color inputBackground: {
    root.foregroundColor;
    return root.foregroundAlpha(0.08);
  }
  readonly property color accentTint: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.12)
  // Intentionally fixed reds: danger signaling ignores the theme-derived accent.
  readonly property color dangerColor: Qt.rgba(1, 0.3, 0.3, 1)
  readonly property color dangerBorder: Qt.rgba(1, 0.3, 0.3, 0.6)
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

  // Horizontal inset that reduces full-width tab content to the content
  // Column's inner width: 2× its 16px side padding. The tab roots (ExploreTab,
  // SpotListTab) and the SpotlightView rows size themselves with
  // `parent.width - contentInset`, so the doubled padding is stated once here
  // instead of as scattered `Style.space(32)` literals. (TabChips fills its
  // pinned-header Row with plain `parent.width` — that Row already carries the
  // same 16px side margins via the pinnedColumn anchors.)
  //
  // The inner width must come from the popup content container's `parent.width`,
  // never from the root's own `width`: the root's width is the bar slot (its
  // implicitWidth is the bar strip's), not the popup's content width, so
  // `width - contentInset` collapses to ~0 and the tab content silently loses
  // its width — the Wishlist/Journal rows rendered only their cover images while
  // the fixed-width name/spec/score Texts went negative-width.
  readonly property real contentInset: Style.space(32)

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
  readonly property int savedCount: root.saved.length
  readonly property int ratedCount: root.ratedEntries.length

  // Search placeholders. Each count is the view's empty-query list length — the
  // filtered+sorted set the search actually runs over — so the placeholder
  // describes what typing will search. The placeholder is only visible while
  // the field is empty (SearchField gates its Text on `!input.text`), so the
  // search term is irrelevant: sortedSpots/sortedWishlist/sortedJournal are the
  // pre-search lists. The bare list read is the explicit tracked dep (reads
  // inside CatalogUtils.searchPlaceholderFor are untracked), so the count
  // re-evaluates when a filter or the list scope changes. A zero count drops
  // the numeral entirely ("Search spots…" / "Search saved spots…") instead of
  // "Search 0 spots…".
  readonly property string searchPlaceholder: {
    root.sortedSpots;
    return CatalogUtils.searchPlaceholderFor(root.sortedSpots.length, "spot");
  }
  readonly property string wishlistSearchPlaceholder: {
    root.sortedWishlist;
    return CatalogUtils.searchPlaceholderFor(root.sortedWishlist.length, "saved spot");
  }
  readonly property string journalSearchPlaceholder: {
    root.sortedJournal;
    return CatalogUtils.searchPlaceholderFor(root.sortedJournal.length, "rated spot");
  }

  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }

  // Closing the panel drops any rating hold and collapses an open card so a
  // reopened panel is fresh: the deferred resync republishes the snapshots (the
  // reactive caches may have changed under the hold with no control change to
  // release it first).
  onOpenedChanged: {
    if (root.opened) {
      // Re-establish the lookahead on the next event-loop turn so
      // `searchedCount` has settled before seedLookahead() reads it.
      pagingWindow.lookaheadSeeded = false;
      Qt.callLater(function() { pagingWindow.seedLookahead(); });
      return;
    }
    // Flush pending notes BEFORE the collapse and BEFORE dropping the hold:
    // the flush re-rates through rateSpot (which sets ratingHold), and a closed
    // panel must end with no hold.
    root.flushNotes();
    root.ratingHold = false;
    if (root.expandedSpotName !== null) root.collapseRow();
    Qt.callLater(function() { root.resyncListModels(); });
  }

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
      tooltipText: "Omakase — worldwide sushi directory and spot tracker"
      onPressed: function(b) {
        if (b === Qt.LeftButton) root.toggle();
      }
    }
  }

  StateFile {
    path: root.stateDir + "/" + SpotUtils.STATE_FILE
    onParsed: function(content) { root.loadCatalog(content) }
    onMissing: root.loadCatalog("")
  }

  StateFile {
    path: root.stateDir + "/" + SpotUtils.JOURNAL_FILE
    onParsed: function(content) { root.loadJournal(content) }
    onMissing: root.loadJournal("")
  }

  StateFile {
    id: savedFile
    // Vocabulary split: `saved`/`save`/`isSaved`/`toggleSaved` is the
    // heart *action* and its on/off state, while `wishlist`/`Wishlist`/
    // `wishlist.json` is the *collection* the user browses. The split is
    // intentional and matches the UI copy — do not "unify" it (and do not rename
    // the on-disk file).
    path: root.stateDir + "/wishlist.json"
    atomicWrites: true
    onParsed: function(content) { root.loadSaved(content) }
    onMissing: root.loadSaved("")
  }

  // One-shot probe for a registered `tel:` URI handler, run once per widget
  // instance at load (a multi-monitor setup instantiates the widget per
  // monitor, so the probe may run twice — harmless). Mirrors Service.qml's
  // seed-loader Process: a StdioCollector captures stdout, and onExited reads
  // it only after a clean, normal exit. `xdg-mime query default` prints the
  // handler's .desktop id on stdout when one is set and nothing otherwise.
  Process {
    id: telHandlerProbe
    command: ["xdg-mime", "query", "default", "x-scheme-handler/tel"]
    stdout: StdioCollector { id: telProbeStdout; waitForEnd: true }
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0 || exitStatus !== 0) { root.telHandlerAvailable = false; return; }
      root.telHandlerAvailable = String(telProbeStdout.text || "").trim().length > 0;
    }
  }

  // ---- Data loading ----
  // Shared chunked-walk scaffold (components/ChunkedWalk.qml): the catalog
  // stamp, spot index, and distance build below each express one bounded walk
  // as a step callback + done callback; the scaffold owns the token supersede
  // check, the chunk budget, the Qt.callLater rescheduling, and the atomic
  // publish-at-completion.
  ChunkedWalk { id: chunkWalk }

  // Explore pagination window (components/PagingWindow.qml): owns how many
  // cards render and how that window grows — the "Show more" click, the
  // one-page lookahead seed, and the scroll-driven prefetch — so the Explore
  // list-model section below only re-slices on the window's `advanced()`
  // signal. Inputs are injected (the scroll viewport for the fill's geometry
  // read, the post-search count, the hold flag, and a page-height in px), so
  // the component reaches for no sibling ids. `holdActive` binds the two hold
  // terms inline rather than calling listHoldActive(), whose function body the
  // binding engine cannot track.
  PagingWindow {
    id: pagingWindow
    viewport: exploreTab
    searchedCount: root.searchedSpots.length
    holdActive: root.expandedSpotName !== null || root.ratingHold
    pagePx: pageSize * root.collapsedCardHeight
    // The maximum (un-shrunk) viewport height: the prefetch gate must measure
    // against this, not the live viewport.height, which ExploreTab shrinks to
    // its content when a short result set fits — see PagingWindow.viewportHeight.
    viewportHeight: root.exploreListHeight
  }

  // Restartable search debounce timer. Each non-empty searchText change
  // restarts it; onTriggered copies searchText -> debouncedSearchText so the
  // declarative searchedSpots chain (which lists debouncedSearchText as a
  // tracked dep) re-runs once per pause, not once per keystroke. Clearing the
  // field stops it and flushes an empty debouncedSearchText immediately.
  Timer {
    id: searchDebounceTimer
    interval: root.searchDebounceMs
    repeat: false
    onTriggered: root.debouncedSearchText = root.searchText
  }

  // Stamp each spot with its city key ONCE at load so the filter pass never
  // mutates the shared catalog objects (which spotsByName and other readers
  // hold by reference). _cityKey is a stable field thereafter. Stamping ~5k spots with ~10 SpotUtils formatters froze the UI
  // for several frames on startup and every home move, so the loop runs through
  // runChunked in chunkSize-spot slices; root.catalog is reassigned only
  // once stamping completes, so readers never observe a partially stamped
  // catalog, and a superseded load is discarded by token (a newer state.json
  // load landed).
  // Spots processed per event-loop turn by every chunked walk (this catalog
  // stamp, the spot index, and the distance build) — one value, three walks.
  readonly property int chunkSize: 400
  property int catalogToken: 0
  // Catalog-change counter: onCatalogChanged bumps it on every catalog load and
  // home move so the catalog-derived caches that list it explicitly
  // (sortedCities) re-evaluate. Distinct from catalogToken, the
  // in-flight chunked-load supersede token. A home move bumps it too (it never
  // signals "spots changed" on its own), which is why the load path needs
  // catalogSpotsFingerprint to tell a home move from a catalog change.
  property int catalogVersion: 0
  // Fingerprint of the spots currently in `catalog`, recomputed on every
  // state.json load. A home move re-serializes byte-identical spots with only
  // homeLat/homeLon changed, so a matching fingerprint is the "spots unchanged"
  // signal that gates the stamp + index walks; a differing fingerprint is a real
  // catalog change (first run, refresh, or a seed-data edit).
  property string catalogSpotsFingerprint: ""
  // One-shot flag set by loadCatalog on the home-move-only path so
  // onCatalogChanged skips the stamp-dependent walks (the spot index + flat-list
  // rebuild) while still re-running the distance walk. Read-and-reset at the top
  // of onCatalogChanged so it can never leak into a later load.
  property bool catalogHomeMoveOnly: false

  function loadCatalog(raw) {
    root.catalogToken++;
    var catalog = SpotUtils.parseJson(raw, {});
    var spotsByCity = catalog.spotsByCity || {};
    // Tell a catalog change from a home move. Only the distance walk depends on
    // home; the derived-field stamp and the spot index are pure functions of the
    // spots, so a home move (identical spots, new homeLat/homeLon) must skip both
    // and reuse the already-stamped + indexed spot objects instead of re-parsing
    // them unstamped. The distance walk still runs on a home move (below, via
    // onCatalogChanged). An identical reload (same spots AND same home) skips
    // everything.
    var fingerprint = CatalogUtils.catalogSpotsHash(spotsByCity);
    var spotsChanged = fingerprint !== root.catalogSpotsFingerprint;
    root.catalogSpotsFingerprint = fingerprint;
    var homeMoved = ((catalog.homeLat || 0) !== (root.catalog.homeLat || 0)) ||
                    ((catalog.homeLon || 0) !== (root.catalog.homeLon || 0));
    if (!spotsChanged) {
      if (!homeMoved) return;
      // Home moved only: keep the stamped + indexed spot objects and the flat
      // list (they are unchanged), and swap in only the new home. Reassigning
      // `catalog` wholesale is what makes homeLat/homeLon re-evaluate (the
      // bindings track `catalog`, not its nested fields), so this must still
      // reassign rather than mutate in place.
      root.catalogHomeMoveOnly = true;
      root.catalog = {
        cities: root.catalog.cities || [],
        spotsByCity: root.catalog.spotsByCity || {},
        homeLat: catalog.homeLat || 0,
        homeLon: catalog.homeLon || 0
      };
      return;
    }
    // Catalog changed: stamp the derived fields as today. Iterate the spotsByCity
    // keys (not catalog.cities) to preserve the exact set and order of the catalog.
    var ctx = { city: 0, spot: 0, cityKeys: Object.keys(spotsByCity), spotsByCity: spotsByCity, catalog: catalog };
    chunkWalk.runSpotWalk({
      getToken: function () { return root.catalogToken; },
      chunkSize: root.chunkSize,
      ctx: ctx,
      cities: function (ctx) { return ctx.cityKeys; },
      onSpot: function (ctx, spot, cityKey) {
        // Stamp the spot's derived display fields once at load (shared helper
        // in spot-utils, unit-tested) so SpotCard reads a field instead of
        // re-running ~10 formatters per delegate bind.
        SpotUtils.applyDerivedFields(spot, cityKey);
      },
      done: function (ctx) {
        root.catalog = ctx.catalog;
      }
    }, root.catalogToken);
  }
  // State-file load: parse, then keep only an array — a top-level object (or
  // any non-array) degrades to an empty list rather than throwing on the later
  // .push/.splice/.length (see SpotUtils.parseJsonArray).
  function loadJournal(raw) { root.journal = SpotUtils.parseJsonArray(raw); }
  function loadSaved(raw) {
    var parsed = SpotUtils.parseJsonArray(raw);
    // Normalize the shape in memory (null resolver: shape only, no write), then
    // attempt the resolving migration — migrateSaved gates on spotIndexReady, so
    // on a cold start it defers until the catalog index is built.
    root.saved = JournalIdentity.normalizeSavedEntries(parsed, root.cityAliases, null).entries;
    root.migrateSaved();
  }

  // ---- Data access ----

  // All spots for a city (seed + user spots). Rated spots stay visible.
  // Returns the catalog's own array — callers only read/filter it (filter/map
  // return new arrays), so no defensive copy is needed.
  function spotsForCity(city) {
    return (root.catalog.spotsByCity && root.catalog.spotsByCity[city]) ? root.catalog.spotsByCity[city] : [];
  }

  // Flat list of every catalog spot (cities then spots, catalog order), shared
  // by computeSortedSpots (multi-city view) and the location aggregates. A
  // function call (not a binding) so `catalog` stays an untracked
  // dependency of its callers — they gate on distanceVersion, not catalogVersion,
  // so they never re-run against the empty distance map installed at the start
  // of a catalog/home move.
  //
  // `flatSpotsCache` is the one flat array built once per catalog change by
  // buildFlatSpots (called from onCatalogChanged, never from inside a binding)
  // and read back here. The previous reduce(concat) rebuilt ~23 throwaway arrays
  // (copying ~60k elements) on every distance change and filter toggle; the
  // callers only read/filter it, so one shared array is safe.
  property var flatSpotsCache: []
  function cachedFlatSpots() {
    return root.flatSpotsCache;
  }
  function buildFlatSpots() {
    var cities = root.catalog.cities || [];
    var total = 0;
    for (var i = 0; i < cities.length; i++) total += spotsForCity(cities[i]).length;
    var flat = new Array(total);
    var offset = 0;
    for (var j = 0; j < cities.length; j++) {
      var spots = spotsForCity(cities[j]);
      for (var k = 0; k < spots.length; k++) flat[offset++] = spots[k];
    }
    root.flatSpotsCache = flat;
  }

  // Average rating for a spot from the precomputed ratingsBySpot map, or null.
  function averageRatingFor(spotName) {
    var entry = root.ratingsBySpot[SpotUtils.normalizeName(spotName)];
    if (!entry || !entry.count) return null;
    return Math.round(entry.total / entry.count * 10) / 10;
  }

  // User rating when present, else the stamped Yelp rating — the shared rating
  // fallback both sort spec maps use (spotSortSpecs' rating primary + price
  // tie-break, and wishlistSortSpecs' rating primary + price tie-break). `name`
  // is resolved against the rating map; `spot` supplies the stamped
  // `_yelpRating`, and a null spot falls back to 0 (a saved name with no
  // catalog match sorts 0).
  function effectiveRating(spot, name) {
    return root.averageRatingFor(name) || (spot ? spot._yelpRating : 0);
  }

  // Most recent journal entry for a spot. O(1) lookup into journalByName,
  // rebuilt whenever the journal changes.
  function latestJournalFor(name) {
    return root.journalByName[SpotUtils.normalizeName(name)] || null;
  }

  // Rated journal entries. Declarative so the binding engine owns the
  // recompute: no getter writes a property during a binding evaluation.
  readonly property var ratedEntries: {
    root.journal;
    return (root.journal || []).filter(function(entry) { return !!entry.rating; });
  }

  // Precomputed per-name rating aggregates. averageRatingFor() reads this map instead
  // of scanning the journal on every delegate render. Both maps are plain
  // (non-binding) properties assigned imperatively, so onJournalChanged rebuilds
  // them whenever the journal changes — a plain property never re-evaluates
  // itself the way a declarative binding does.
  // All three are keyed by spot name, so they are null-prototype: a spot named
  // "constructor"/"toString"/"__proto__" must not resolve to an inherited
  // Object.prototype member (which would poison the aggregate or the index).
  property var ratingsBySpot: Object.create(null)
  property var journalByName: Object.create(null)
  // name -> [ { spot, cityKey } ] across all cities, in catalog order (cities
  // then spots). Rebuilt on every catalog change so resolveSpot() resolves a name
  // in O(1) instead of scanning every city's spots.
  property var spotsByName: Object.create(null)
  // Chunked rebuild state for spotsByName. Building the map synchronously froze
  // the UI for several frames on startup and every home move (the catalog is a
  // ~1.9 MB parse producing ~5k spots), so the build runs through runChunked in
  // chunkSize-spot slices. The map is swapped in atomically only when
  // complete, so spotsByName is never observed partially built; a superseded
  // build is discarded when its token no longer matches (a newer catalog change
  // landed).
  property int spotIndexToken: 0

  function refreshRatings() {
    // Iterate `journal` directly, NOT `ratedEntries`: `ratedEntries` is a
    // declarative binding over `journal`, and this function runs synchronously
    // from `onJournalChanged` — before the engine re-evaluates `ratedEntries`.
    // Reading it here returns the stale (pre-write) array, leaving ratingsBySpot
    // empty and breaking the Unrated filter (averageRatingFor always null). The
    // aggregation itself (normalize key, accumulate total/count, last-write-wins
    // journal map) lives in CatalogUtils.buildRatingMaps.
    var result = CatalogUtils.buildRatingMaps(root.journal);
    root.ratingsBySpot = result.ratingsBySpot;
    root.journalByName = result.journalByName;
  }

  function rebuildCatalogIndex() {
    root.spotIndexToken++;
    // The index is being rebuilt: keep the migration gate closed until the
    // walk's done publishes spotsByName/searchIndex, or migrateSaved would stamp
    // every entry with city:"" against a stale/empty index.
    root.spotIndexReady = false;
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
      byCity: Object.create(null)
    };
    chunkWalk.runSpotWalk({
      getToken: function () { return root.spotIndexToken; },
      chunkSize: root.chunkSize,
      ctx: ctx,
      cities: function (ctx) { return ctx.cities; },
      onCityDone: function (ctx, cityKey) { root.recordCityIndex(ctx, cityKey); },
      onSpot: function (ctx, spot, cityKey) {
        // Precompute the folded search blob + record the name→entries index
        // entry (the per-spot body lives in CatalogUtils.indexSpot).
        CatalogUtils.indexSpot(spot, cityKey, ctx.map);
      },
      done: function (ctx) {
        // Both maps are reassigned whole, so declarative readers observe the
        // fresh index on their own: sortedJournal/sortedWishlist track
        // spotsByName, and the search dropdown tracks searchIndex
        // (its buildSearchHits() reads are otherwise untracked through the
        // function call).
        root.spotsByName = ctx.map;
        root.searchIndex = { cities: ctx.ordered, names: ctx.names, counts: ctx.counts, byCity: ctx.byCity, foldedNames: ctx.foldedNames, foldedKeys: ctx.foldedKeys };
        // The index is now complete: open the migration gate and run the
        // resolving wishlist migration (a no-op when already canonical).
        root.spotIndexReady = true;
        root.migrateSaved();
      }
    }, root.spotIndexToken);
  }

  function refreshSavedSet() {
    var byCity = Object.create(null);
    var nameOnly = Object.create(null);
    // Two null-prototype maps rebuilt from `saved`: entries with a canonical
    // city key on JournalIdentity.journalSpotKey (normalized name + canonical
    // city), and entries whose city is empty (legacy/unresolved) keyed by
    // normalized name alone — the name-only fallback mirroring findJournalIndex.
    // isSaved() reads both, so it stays O(1) and case-insensitive; the on-disk
    // `saved` array still holds the original casing unchanged.
    for (var i = 0; i < root.saved.length; i++) {
      var entry = root.saved[i];
      if (!SpotUtils.isPlainObject(entry)) continue;
      var key = JournalIdentity.journalSpotKey(entry, root.cityAliases);
      if (!key) continue;
      var city = JournalIdentity.canonicalCityKey(entry.city, root.cityAliases);
      if (city) byCity[key] = true;
      else nameOnly[key] = true;
    }
    root.savedByCitySet = byCity;
    root.savedNameOnlySet = nameOnly;
  }

  Component.onCompleted: {
    root.refreshRatings();
    root.buildCityLabelMap();
    root.refreshSavedSet();
    telHandlerProbe.running = true;
  }

  // Resolve a spot by name. A non-empty city match wins first; otherwise the
  // first city (in catalog order) holding the name is returned — an O(1) read
  // from spotsByName.
  // Returns { spot, cityKey } or null when no city contains the spot.
  function resolveSpot(name, city) {
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

  function resolveSavedCity(name) {
    var located = root.resolveSpot(name, "");
    return located && located.cityKey ? located.cityKey : "";
  }

  // One-time wishlist migration: resolves empty-city entries against the built
  // catalog index and rewrites the file in the new { name, city } shape. Gated
  // on spotIndexReady — before the index exists every entry would stamp
  // city:"" and defeat the change. Idempotent: canonical input yields no
  // change and no write (savedFile.setText also skips byte-identical content).
  function migrateSaved() {
    if (!root.spotIndexReady) return;
    var n = JournalIdentity.normalizeSavedEntries(root.saved, root.cityAliases, root.resolveSavedCity);
    var d = JournalIdentity.dedupeJournalEntries(n.entries, root.cityAliases);
    if (!n.changed && d.merged === 0) return;
    root.saved = d.entries;
    savedFile.setText(JSON.stringify(root.saved));
  }

  function findSavedIndex(name, city) {
    return JournalIdentity.findJournalIndex(root.saved, name, city, root.cityAliases);
  }

  function isSaved(spotName, cityKey) {
    var key = SpotUtils.normalizeName(spotName);
    if (!key) return false;
    var city = JournalIdentity.canonicalCityKey(cityKey, root.cityAliases);
    if (city && root.savedByCitySet[JournalIdentity.journalSpotKey({ name: spotName, city: cityKey }, root.cityAliases)]) return true;
    return !!root.savedNameOnlySet[key];
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
    cities.forEach(function (cityKey) {
      if (map[cityKey] === undefined) map[cityKey] = CatalogUtils.cityLabelFor(cityKey);
    });
    var journal = root.journal || [];
    journal.forEach(function (entry) {
      var city = entry.city;
      if (city && map[city] === undefined) map[city] = CatalogUtils.cityLabelFor(city);
    });
    root.cityLabelMap = map;
  }
  function cityLabel(key) {
    var cached = root.cityLabelMap[key];
    if (cached !== undefined) return cached;
    return CatalogUtils.cityLabelFor(key);
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
    var located = spots.find(function (spot) { return SpotUtils.hasCoords(spot.lat, spot.lon); });
    return located ? SpotUtils.haversine(root.homeLat, root.homeLon, located.lat, located.lon) : Infinity;
  }

  // Per-coordinate haversine cache keyed on coordinates (not object identity).
  // Distances depend only on home + a spot's lat/lon, so they are computed once
  // per catalog/home change and reused across filter toggles instead of
  // recomputed on every sortedSpots rebuild. A key collision can only cause a
  // redundant computation, never a wrong value.
  //
  // The build is chunked (chunkSize spots per event-loop turn, yielding
  // via Qt.callLater) because ~5k synchronous haversines froze the UI on
  // startup and every home move. The staged map is published atomically to
  // distanceByCoords only when complete, and distanceVersion is bumped in the
  // same turn; declarative readers track distanceVersion (not distanceByCoords)
  // so they never observe a partial map. A superseded build is discarded when
  // its token no longer matches (a newer catalog/home change landed).
  property var distanceByCoords: Object.create(null)
  property int distanceVersion: 0
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
      chunkSize: root.chunkSize,
      ctx: ctx,
      cities: function (ctx) { return ctx.cities; },
      onSpot: function (ctx, spot, cityKey) {
        // The hasCoords gate + coordKey + first-write-wins step lives in
        // CatalogUtils.stageSpotDistance.
        CatalogUtils.stageSpotDistance(spot, root.homeLat, root.homeLon, ctx.staged);
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
  function distanceKmOrUndefined(spot) {
    if (!spot || !SpotUtils.hasCoords(spot.lat, spot.lon) || !root.homeLat || !root.homeLon) return undefined;
    var cached = root.distanceByCoords[CatalogUtils.coordKey(spot.lat, spot.lon)];
    if (cached !== undefined) return cached;
    return SpotUtils.haversine(root.homeLat, root.homeLon, spot.lat, spot.lon);
  }

  // distanceKmOrUndefined's `undefined` folded to Infinity — the "no distance"
  // sentinel for sort contexts where geo-less entries sort last.
  function distanceKmOrInfinity(spot) {
    var km = distanceKmOrUndefined(spot);
    return km === undefined ? Infinity : km;
  }

  // Distance from home to a neighborhood's representative spot (the first spot
  // with coordinates in that neighborhood, recorded by the index walk), Infinity
  // when the neighborhood has no located spot or home is unknown. Mirrors
  // cityDistanceKm's first-spot fallback; reuses distanceKmOrInfinity so the
  // per-coordinate cache serves the lookup.
  function neighborhoodDistanceKm(nb) {
    if (!nb || !nb.lat || !nb.lon) return Infinity;
    return distanceKmOrInfinity({ lat: nb.lat, lon: nb.lon });
  }

  // Distance from home to a spot, formatted for display; empty when unknown.
  function spotDistanceLabel(spot) {
    var km = distanceKmOrUndefined(spot);
    return km === undefined ? "" : SpotUtils.formatDistance(km);
  }

  // True when `root.radius` is active (>0) and the spot falls within it.
  function isWithinRadius(spot) {
    var km = distanceKmOrUndefined(spot);
    return km === undefined ? false : km <= root.radius;
  }

  // The active neighborhood filter, pre-lowercased for the case-insensitive
  // per-spot comparison. A function (not a property) so each compute pass reads
  // it fresh: the passes re-run when root.neighborhood changes (their tracked
  // dep), so the fold is never stale. Empty/absent neighborhood folds to "",
  // which matchesNeighborhood treats as "no filter".
  function foldedNeighborhoodFilter() {
    return root.neighborhood ? root.neighborhood.toLowerCase() : "";
  }

  // Whether a spot's neighborhood matches the active neighborhood filter.
  // `neighborhoodFolded` is the already-lowercased filter value, hoisted out of
  // the per-spot pass by the caller (it is constant for the whole pass).
  function matchesNeighborhood(spot, neighborhoodFolded) {
    if (!neighborhoodFolded) return true;
    return spot && String(spot.neighborhood || "").toLowerCase() === neighborhoodFolded;
  }

  // ---- Filtering ----

  // Shared global filter predicates (kind, city, radius, neighborhood, state,
  // country, unratedOnly) for a single spot. `spot` may be null (a name no longer
  // in the catalog); `cityKey` is the spot's city key ("" when unknown); `opts`
  // toggles per-caller predicates:
  //   city         — filter by root.cityKey against cityKey
  //   unratedOnly  — hide spots that already have a rated journal entry
  //   name         — the name checked against the rating map (defaults to spot.name)
  //   neighborhoodFolded — pre-lowercased root.neighborhood (hoisted per pass)
  function passesFilters(spot, cityKey, opts) {
    opts = opts || {};
    if (root.kindFilter !== CatalogUtils.KIND_FILTER_ALL && (!spot || spot._spotKind !== root.kindFilter)) return false;
    if (opts.city && root.cityKey && cityKey !== root.cityKey) return false;
    if (root.radius > 0 && !root.isWithinRadius(spot)) return false;
    if (!root.matchesNeighborhood(spot, opts.neighborhoodFolded)) return false;
    // State/country apply to every list source (Explore, Wishlist, Journal). A
    // null spot carries no location, so it passes only when neither filter is
    // active (the `if` guards skip the predicate) and drops otherwise — the same
    // contract as isWithinRadius(null) → false.
    if (root.stateFilter || root.countryFilter) {
      // The state code alone is ambiguous: a foreign region code can collide
      // with a US state code (Milan's "CO"/"VA" are Lombardy provinces). The
      // country gate (CatalogUtils.isUsState) keeps those foreign spots out of
      // a selected US state, matching the aggregate pass in computeLocationAggregates.
      // State/country are normalized via the shared normalizeStateCountry (trim
      // + uppercase), which also picks up the .trim() the inline form omitted.
      var normalized = spot ? CatalogUtils.normalizeStateCountry(spot) : { state: "", country: "" };
      if (root.stateFilter && !(normalized.state === root.stateFilter && CatalogUtils.isUsState(spot))) return false;
      if (root.countryFilter && normalized.country !== root.countryFilter) return false;
    }
    if (opts.unratedOnly && root.unratedOnly && root.tab !== CatalogUtils.VIEW_JOURNAL && root.averageRatingFor(opts.name || (spot ? spot.name : "")) !== null) return false;
    return true;
  }

  // ---- Search & list model ----

  // City/neighborhood/state matches for the search dropdown live in
  // CatalogUtils.buildSearchHits (pure, unit-tested), called from
  // activeSearchHits above with the two distance resolvers injected.

  // Precomputed search index: city names + spot counts (O(1) lookups) and, per
  // city, the neighborhood tally in first-seen order. Built by the same chunked
  // spot-index walk as spotsByName (rebuildCatalogIndex) so the ~5k-spot scan runs
  // in bounded slices instead of one synchronous pass in the catalogVersion
  // cascade. `byCity` keeps one record per (city, neighborhood) pair — a plain
  // neighborhood→record map would collapse the neighborhoods shared across
  // cities (e.g. "CBD"). Published atomically with spotsByName; the empty
  // structure below keeps readers safe before the first build completes.
  property var searchIndex: ({ cities: [], names: Object.create(null), counts: Object.create(null), byCity: Object.create(null), foldedNames: Object.create(null), foldedKeys: Object.create(null) })

  // Record one city into the in-flight search-index ctx — its key, display
  // name, folded match strings, spot count, and neighborhood records. Called
  // from the chunked walk when a city's spots are exhausted (including empty
  // cities, which yield an empty record list). Resolves names through
  // CatalogUtils.cityLabelFor (the same seam as cityLabel) rather than cityLabel
  // itself, so it never depends on cityLabelMap, which is rebuilt after this
  // walk starts.
  function recordCityIndex(ctx, cityKey) {
    ctx.ordered.push(cityKey);
    var label = CatalogUtils.cityLabelFor(cityKey);
    ctx.names[cityKey] = label;
    // Precompute the folded match strings once per catalog version so the
    // per-keystroke search dropdown folds only the query (see buildSearchHits).
    ctx.foldedNames[cityKey] = SpotUtils.foldSearchText(label);
    ctx.foldedKeys[cityKey] = SpotUtils.foldSearchText(cityKey);
    var spots = ctx.spotsByCity[cityKey] || [];
    ctx.counts[cityKey] = spots.length;
    // The neighborhood tally lives in CatalogUtils.buildNeighborhoodRecords —
    // one pure definition shared with the scoped Wishlist/Journal search index.
    // Its String() guard on the stored neighborhood field is what keeps a wrong-
    // typed value from throwing inside the walk step (a throw escapes before the
    // Qt.callLater reschedule and leaves the index never published).
    ctx.byCity[cityKey] = CatalogUtils.buildNeighborhoodRecords(spots, cityKey, label);
  }

  // Sorted rated journal entries (query + sort applied). Declarative so no
  // binding ever writes it. The dependency list is explicit because reads
  // inside the compute function are not tracked. distanceVersion — not
  // homeLat/homeLon — is the distance trigger (see sortedSpots), so a home move
  // re-runs this only after the chunked distance build completes.
  readonly property var sortedJournal: {
    root.journal;
    root.sortBy;
    root.sortReversed;
    root.journalQuery;
    root.kindFilter;
    root.cityKey;
    root.radius;
    root.neighborhood;
    root.stateFilter;
    root.countryFilter;
    root.spotsByName;
    root.ratingsBySpot;
    root.cityLabelMap;
    root.distanceVersion;
    return root.computeSortedJournal();
  }
  function computeSortedJournal() {
    // The shared resolve + filter + query-match + sort pipeline (the pure
    // CatalogUtils.resolveFilterSort). `locate` resolves each entry's spot ONCE;
    // journalSortSpecs reads the pre-resolved located spot and the rating key
    // reads entry.rating directly; mapItem folds the located record into the
    // delegate's plain shape (modelData.spot reads a property, not a
    // non-reactive function-call binding). passesFilters keys the city predicate
    // off the journal entry's own `city` (not the located spot's catalog key).
    return CatalogUtils.resolveFilterSort(
      root.ratedEntries,
      function (entry) {
        var located = root.resolveSpot(entry.name, entry.city);
        return { entry: entry, located: located };
      },
      root.journalQuery || "",
      {
        foldNeighborhood: function () { return root.foldedNeighborhoodFilter(); },
        passesFilters: function (item, neighborhoodFolded) {
          var entry = item.entry;
          return root.passesFilters(item.located ? item.located.spot : null, entry.city, { city: true, neighborhoodFolded: neighborhoodFolded });
        },
        matchFields: function (item) {
          return [item.entry.name, item.entry.notes];
        },
        sortBy: root.sortBy,
        sortReversed: root.sortReversed,
        sortSpecs: root.journalSortSpecs,
        mapItem: function (item) {
          var entry = item.entry;
          return { name: entry.name, cityKey: entry.city, spot: item.located ? item.located.spot : null, entry: entry };
        }
      }
    );
  }

  // City labels render when the list spans cities: no single city is selected,
  // or a radius mixes multiple cities. A property (not a function) so card
  // bindings read it directly and the engine tracks cityKey/radius — a function
  // call is not tracked, so every caller had to re-list the deps by hand.
  property bool showsCityLabels: !root.cityKey || root.radius > 0

  // Sort specs, keyed by sortBy, consumed by CatalogUtils.sortBySpec.
  // Each entry is { extract(item) -> primary value, tieBreakers?: [extractor] };
  // the extractors close over `root` (averageRatingFor, the distance cache) and
  // are pure reads, so sortBySpec evaluates them once per item — never twice
  // per comparison. The two spot-shaped specs (spotSortSpecs and
  // wishlistSortSpecs below) are built by CatalogUtils.makeSortSpecs with the
  // rating and distance resolvers injected; see that factory for the tie-break
  // semantics (rating → review count → name, all direction-independent under
  // Price ↑/↓).

  // Journal entries: `extract` maps a resolved { entry, located } record to its
  // sort value. The price and distance keys read the pre-resolved located spot;
  // the rating key reads entry.rating directly (the entry's own rating, not the
  // effectiveRating fallback). Journal entries carry no tie-breakers, so this map
  // cannot share makeSortSpecs.
  readonly property var journalSortSpecs: ({
    rating: {
      extract: function (item) { return item.entry.rating || 0; }
    },
    price: {
      extract: function (item) {
        return SpotUtils.priceSortKey(item.located ? item.located.spot : null);
      }
    },
    distance: {
      extract: function (item) {
        return distanceKmOrInfinity(item.located ? item.located.spot : null);
      }
    }
  })

  // Spot arrays: the item is the spot itself, so spotOf is the identity and
  // nameOf reads spot.name.
  readonly property var spotSortSpecs: CatalogUtils.makeSortSpecs(
    function (spot) { return spot; },
    function (spot) { return spot.name; },
    root.effectiveRating,
    distanceKmOrInfinity
  )

  // Wishlist entries ({ name, spot, cityKey }): sort the resolved spot exactly
  // like sortedSpots sorts spots (spotSortSpecs), but through the entry's
  // `spot` field — a saved name with no catalog match carries a null spot, which
  // sorts last (Infinity) for price/distance and 0 for rating. nameOf substitutes
  // `item.name` when the spot is null; the null-guarded review count returns 0.
  readonly property var wishlistSortSpecs: CatalogUtils.makeSortSpecs(
    function (item) { return item.spot; },
    function (item) { return item.spot ? item.spot.name : item.name; },
    root.effectiveRating,
    distanceKmOrInfinity
  )

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
  readonly property var sortedSpots: {
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
    return root.computeSortedSpots();
  }
  function computeSortedSpots() {
    var spots = root.showsCityLabels ? root.cachedFlatSpots() : spotsForCity(root.cityKey);
    // Lowercase the neighborhood filter once per pass, not once per spot.
    var neighborhoodFolded = root.foldedNeighborhoodFilter();
    // Shared global predicates (type/city/radius/neighborhood/state/country/
    // unratedOnly). City is already enforced by the collection above; the rest
    // live in passesFilters.
    spots = spots.filter(function (spot) { return root.passesFilters(spot, spot._cityKey || "", { unratedOnly: true, neighborhoodFolded: neighborhoodFolded }); });
    // Single spec lookup + decoratedSort (CatalogUtils.sortBySpec): the
    // spotSortSpecs extractors read the stamped `_*` fields (and the distance
    // cache) so the sort agrees with SpotCard. priceSortKey keeps
    // discount-cheapest and unpriced-always-last.
    spots = CatalogUtils.sortBySpec(spots, root.sortBy, root.sortReversed, root.spotSortSpecs);
    return spots;
  }

  // Search rank over the base result. Declarative so the rank re-runs only when
  // the base data or the debounced query changes. The query is
  // debouncedSearchText (not searchText) so the full-catalog pass trails typing
  // by searchDebounceMs.
  // rankSpots groups matches by class descending — NAME_EXACT (2) > MATCH (1) —
  // and preserves the incoming order (the user's active sort) within a class, so
  // proximity decides among equal-quality (partial) matches. It is a two-rung
  // class ladder, not a score: an exact name match floats to the top, and every
  // other name/neighborhood match shares one tier. The city label is deliberately
  // not matched here — proximity must dominate the tail, and city scoping belongs
  // to the search dropdown.
  readonly property var searchedSpots: {
    root.sortedSpots;
    root.debouncedSearchText;
    return root.computeSearchedSpots();
  }
  function computeSearchedSpots() {
    var spots = root.sortedSpots;
    if (!root.debouncedSearchText) return spots;
    return CatalogUtils.rankSpots(spots, root.debouncedSearchText);
  }

  // Only the first `pagingWindow.visibleCount` cards render — keeps delegate
  // instantiation cheap for the ~5k spot dataset. "Show more" extends the
  // window. The slice is computed imperatively, never inside a binding, because
  // `visibleCount` is written by the paging window's showMore()/fillPrefetch()
  // during the render pass: a live binding over it re-enters when that write
  // lands mid-evaluation and Qt logs a binding-loop warning.
  property var exploreModel: []
  function refreshExploreModel() {
    var all = root.searchedSpots;
    // A lazy binding's first read fires this handler mid-evaluation, before
    // searchedSpots has settled; property access on that undefined value throws.
    if (!Array.isArray(all)) return;
    root.exploreModel = all.length <= pagingWindow.visibleCount ? all : all.slice(0, pagingWindow.visibleCount);
  }
  onSearchedSpotsChanged: {
    if (!root.listHoldActive()) root.refreshExploreModel();
    pagingWindow.seedLookahead();
  }
  // The paging window emits `advanced()` whenever its window size changes (a
  // reset or a grow) — the imperative re-slice trigger the old
  // onVisibleCountChanged handler provided. Same hold gate: while a rating/save
  // is in flight the model stays frozen and catches up on release.
  Connections {
    target: pagingWindow
    function onAdvanced() {
      if (!root.listHoldActive()) root.refreshExploreModel();
    }
  }

  // `exploreModel` is a plain array fed by the handlers above, never bound to a
  // reactive compute path: the chunked distance build bumps distanceVersion
  // (which sortedSpots tracks) mid-evaluation, so a `model:` binding over that
  // path would self-re-enter. The handlers fire only when searchedSpots is
  // reassigned or the paging window grows, so the model is stable across
  // unrelated re-evaluations.

  // Journal/Wishlist list-model snapshots, mirroring exploreModel. Each
  // ListView binds `model:` to this plain array; the handler snapshots the
  // declarative result whenever it is reassigned, so the model binding never
  // re-enters a reactive compute path.
  property var journalModel: []
  onSortedJournalChanged: if (!root.listHoldActive()) root.publishListModels()
  property var wishlistModel: []
  onSortedWishlistChanged: if (!root.listHoldActive()) root.publishListModels()

  // Rating hold: while a rating/save is in flight (or a card is open), freeze
  // the three list-model snapshots so rating a spot never re-sorts its row out
  // from under the user. Only snapshot PUBLICATION is gated — the declarative
  // compute chain keeps running, so the open card's live reads still update.
  // ratingHold is set by the rating/save action functions (rateSpot/unrateSpot/
  // toggleSaved), not onJournalChanged/onSavedChanged, which also fire on the
  // startup FileView load and would freeze the panel at first render. A card
  // open holds via expandedSpotName (the gate's other term), so collapsing a
  // card without rating leaves no hold behind.
  property bool ratingHold: false
  function listHoldActive() {
    return root.expandedSpotName !== null || root.ratingHold;
  }
  // Publish the Journal/Wishlist snapshot models from their declarative
  // sources. Used by the gated reactive handlers above and by resyncListModels
  // (ungated, below).
  function publishListModels() {
    root.journalModel = root.sortedJournal;
    root.wishlistModel = root.sortedWishlist;
  }
  // Re-publish all three snapshots from their declarative sources. Ungated on
  // purpose: the release path must catch up even though the reactive handlers
  // above are still gated while held.
  function resyncListModels() {
    root.refreshExploreModel();
    root.publishListModels();
  }
  // Drop the hold, then resync one Qt.callLater turn later so the reactive
  // caches have recomputed regardless of handler ordering (a closure — never a
  // bare method reference, see components/ChunkedWalk.qml).
  function releaseListHold() {
    if (!root.listHoldActive()) return;
    root.ratingHold = false;
    Qt.callLater(function() { root.resyncListModels(); });
  }
  // A rating/save action either re-ranks the affected spot (still present in
  // the active list — keep holding; that re-order is exactly what the hold
  // freezes) or drops it from the list (unrate in Journal, unsave in Wishlist,
  // rate under the Unrated chip) — and a held row must not outlive the spot's
  // membership. holdCheckName records which spot to check; the check runs one
  // turn after the data-change handler fires (rate/unrate land async via the
  // Service's file write, toggleSaved synchronously) so the declarative caches
  // have settled, and it clears the name first so it can never run twice for
  // one action or loop back on the release.
  property string holdCheckName: ""
  function spotsForActiveView() {
    if (root.tab === CatalogUtils.VIEW_EXPLORE) return root.searchedSpots;
    if (root.tab === CatalogUtils.VIEW_WISHLIST) return root.sortedWishlist;
    return root.sortedJournal;
  }
  function scheduleHoldCheck() {
    if (!root.holdCheckName) return;
    Qt.callLater(function() { root.checkHoldRelease(); });
  }
  // Normalize the probe name once, then scan `list` for an element whose
  // comparable name (`nameOf`) matches — the "normalize then scan for
  // membership" rule checkHoldRelease uses to decide whether a rated/saved spot
  // is still in the active view's list. Returns the first matching index, or -1.
  function indexOfNormalizedName(list, probeName, nameOf) {
    var key = SpotUtils.normalizeName(probeName);
    for (var i = 0; i < list.length; i++) {
      if (list[i] && SpotUtils.normalizeName(nameOf(list[i])) === key) return i;
    }
    return -1;
  }

  function checkHoldRelease() {
    var name = root.holdCheckName;
    root.holdCheckName = "";
    if (!name || !root.ratingHold) return;
    // Spotlight renders one stored pick, not a list: there is no membership to
    // enforce, and its card is expected to persist after the rating.
    if (root.spotlight) return;
    var list = root.spotsForActiveView();
    if (root.indexOfNormalizedName(list, name, function (entry) { return entry.name; }) >= 0) return;
    // The spot left the active list: drop the hold and close its card (if it
    // was the open one) so the row disappears on the deferred resync.
    root.releaseListHold();
    if (root.expandedSpotName === name) root.collapseRow();
  }

  // Saved spots resolved to { name, spot, cityKey } after the shared Explore
  // filters + wishlist query. Declarative so the binding engine owns the
  // recompute.
  // The dependency list is explicit because reads inside the compute function
  // are not tracked. spotsByName is reassigned whole when the catalog changes,
  // so it is a tracked dep on its own. distanceVersion is the distance-map
  // trigger (see sortedSpots);
  // homeLat/homeLon are not listed because they change with the catalog and
  // would re-run this against the empty map before the build completes.
  readonly property var sortedWishlist: {
    root.saved;
    root.wishlistQuery;
    root.sortBy;
    root.sortReversed;
    root.kindFilter;
    root.cityKey;
    root.radius;
    root.neighborhood;
    root.stateFilter;
    root.countryFilter;
    root.unratedOnly;
    root.spotsByName;
    root.ratingsBySpot;
    root.distanceVersion;
    root.cityLabelMap;
    return root.computeSortedWishlist();
  }
  function computeSortedWishlist() {
    // The shared resolve + filter + query-match + sort pipeline (the pure
    // CatalogUtils.resolveFilterSort). `locate` resolves each saved name to
    // { name, spot, cityKey } ONCE; the wishlist sort spec maps the resolved spot
    // exactly like sortedSpots. A saved name with no catalog match keeps its null
    // spot (sorts last for price/distance, 0 for rating); the records are already
    // delegate-shaped, so mapItem is omitted.
    return CatalogUtils.resolveFilterSort(
      root.saved,
      function (entry) {
        var located = root.resolveSpot(entry.name, entry.city);
        return { name: entry.name, spot: located ? located.spot : null, cityKey: located ? located.cityKey : "" };
      },
      root.wishlistQuery || "",
      {
        foldNeighborhood: function () { return root.foldedNeighborhoodFilter(); },
        passesFilters: function (entry, neighborhoodFolded) {
          return root.passesFilters(entry.spot, entry.cityKey, { city: true, unratedOnly: true, name: entry.name, neighborhoodFolded: neighborhoodFolded });
        },
        matchFields: function (entry) {
          var spot = entry.spot;
          return [entry.name, spot ? spot.neighborhood : null];
        },
        sortBy: root.sortBy,
        sortReversed: root.sortReversed,
        sortSpecs: root.wishlistSortSpecs
      }
    );
  }

  // Scoped search-suggestion sources for the Wishlist and Journal dropdowns.
  // Geography (city names/keys, neighborhoods, states) is derived ONLY from the
  // user's own saved/rated spots — not the catalog-wide searchIndex — so typing
  // in Wishlist/Journal surfaces the places the user actually saved/rated, not
  // every city in the catalog. The full saved/rated sets (root.saved/root.journal)
  // are the input — never wishlistModel/journalModel, which are filtered by the
  // active query and would collapse the dropdown to zero while typing.
  // Both tabs share one pipeline: resolve each item to its located
  // { spot, cityKey } (the resolver returns null for a name no longer in the
  // catalog), drop the nulls, then build the scoped index. Only the source list
  // differs — each resolves its entry against its stored city ("" for an
  // unresolved saved name).
  function scopedSearchIndexFor(items, resolveEntry) {
    var entries = items.map(resolveEntry).filter(Boolean);
    return CatalogUtils.buildScopedSearchIndex(entries, root.distanceKmOrUndefined);
  }
  function computeWishlistSearch() {
    var entries = root.saved || [];
    return root.scopedSearchIndexFor(entries, function (entry) {
      var located = root.resolveSpot(entry.name, entry.city);
      return located && located.spot ? { spot: located.spot, cityKey: located.cityKey } : null;
    });
  }
  function computeJournalSearch() {
    return root.scopedSearchIndexFor(root.ratedEntries, function (entry) {
      var located = root.resolveSpot(entry.name, entry.city);
      return located && located.spot ? { spot: located.spot, cityKey: located.cityKey } : null;
    });
  }
  // The dependency list is explicit because reads inside the compute functions
  // are not tracked. spotsByName makes each wait for the async index publish
  // (resolveSpot reads it); distanceVersion keeps the subset's state distances
  // consistent with the distance cache. Subsets are tens of spots, so no chunking.
  readonly property var wishlistSearch: { root.saved; root.spotsByName; root.distanceVersion; return root.computeWishlistSearch() }
  readonly property var journalSearch: { root.journal; root.spotsByName; root.distanceVersion; return root.computeJournalSearch() }

  // ---- Navigation ----

  // The surprise pool: the filtered+searched result minus permanently-closed
  // spots (CatalogUtils.isSurpriseEligible — and here only; the normal list/
  // filter semantics are unchanged). surprisePoolSize is declarative and lists
  // `searchedSpots` as its tracked dep (the read inside countSurprisePool() is
  // untracked, so it is stated explicitly) so the SurpriseButton's enabled state
  // and the spotlight's "Try another" visibility track it with no manual
  // invalidation. countSurprisePool() tallies eligible spots with a plain loop —
  // no pool array — because the binding only reads the count; surprisePoolSpots()
  // still materializes the array, but only in surpriseMe() on a click, never on
  // a keystroke or a filter/search settle.
  function surprisePoolSpots() {
    return root.searchedSpots.filter(CatalogUtils.isSurpriseEligible);
  }
  function countSurprisePool() {
    var spots = root.searchedSpots;
    var count = 0;
    for (var i = 0; i < spots.length; i++) {
      if (CatalogUtils.isSurpriseEligible(spots[i])) count++;
    }
    return count;
  }
  readonly property int surprisePoolSize: {
    root.searchedSpots;
    return root.countSurprisePool();
  }

  // Pick a random spot from the current filter results and open the spotlight
  // view on it with the rating editor expanded (rating the pick is the point of
  // the flow). Returns true when a candidate exists. While the spotlight is
  // already open (the "Another" path) the current spot's name is passed as
  // `excludeName`, so a shuffle never returns the spot already on screen when
  // an alternative exists. The pick itself is the pure `CatalogUtils.pickRandom`
  // (injectable rng for tests, empty pool -> null). The pool comes from the
  // shared surprisePoolSpots() accessor, materialized on this click (not a binding),
  // so typing never allocates a pool for the pick.
  function surpriseMe() {
    var excludeName = (root.spotlight && root.spotlightSpot) ? root.spotlightSpot.name : "";
    var pool = root.surprisePoolSpots();
    var pick = CatalogUtils.pickRandom(pool, Math.random, excludeName);
    // pickRandom refuses to repeat the current pick, but a one-spot pool has no
    // alternative — display that spot rather than no-op.
    if (!pick && pool.length > 0) pick = pool[0];
    if (!pick) return false;
    root.spotlightSpot = pick;
    root.expandedSpotName = pick.name;
    root.spotlight = true;
    // Opening Spotlight navigates away from the search field and the filter
    // sheet: dismiss both so neither floats over the spotlight card.
    root.dismissPopovers();
    return true;
  }

  // Collapse any expanded row. Flush pending notes BEFORE the editor is torn
  // down (expandedSpotName -> null), so collapsing commits the notes.
  function collapseRow() {
    root.flushNotes();
    root.expandedSpotName = null;
  }

  // Leave the spotlight view. The Back link and the Escape spotlight branch
  // both route here so the teardown is one body. Rating from the spotlight
  // sets ratingHold, and checkHoldRelease early-returns while spotlight is set,
  // so the hold must be dropped here or the Explore snapshots stay frozen.
  // Clearing expandedSpotName is the notes-flush safety net (see
  // onExpandedSpotNameChanged); it lands before releaseListHold so a flush that
  // re-rates through rateSpot still gets its hold dropped, matching switchTab.
  function leaveSpotlight() {
    root.spotlight = false;
    root.expandedSpotName = null;
    root.dismissPopovers();
    root.releaseListHold();
  }

  // Switch the active tab and collapse any expanded row. Its only caller — the
  // pinned header's TabChips — closes the spotlight view first (the chips stay
  // reachable from Spotlight because its chrome is the pinned header's).
  function switchTab(tab) {
    root.tab = tab;
    // Entering a tab must not raise the suggestions dropdown or leave the
    // filter sheet floating over the destination tab: dismiss both. Typing
    // re-opens the dropdown via the query-change clears below.
    root.dismissPopovers();
    // Flush pending notes before releaseListHold: the flush re-rates through
    // rateSpot (which sets ratingHold), and the tab switch drops that hold.
    root.flushNotes();
    root.releaseListHold();
    root.collapseRow();
  }

  // Dismiss the filter sheet and the search-suggestions dropdown. Shared by the
  // two outside-tap dismiss surfaces and the navigate-away paths (surpriseMe,
  // switchTab, leaveSpotlight), so dismissing on navigation lives in one place.
  // Unconditional on purpose: writing a flag to its current value is a no-op,
  // so callers need not gate on visibility. The sheet's onOpenSheetChanged
  // clears openDropdown; the dropdown's searchSuggestionsDismissed is the same
  // flag handleSearchEscape sets.
  function dismissPopovers() {
    root.openSheet = false;
    root.searchSuggestionsDismissed = true;
  }

  // Ordered Escape chain shared by the search fields' onDismissed and the key
  // catcher's onCloseRequested. Escape dismisses, in order, the FIRST thing that
  // is open — the suggestions dropdown, the filter sheet, Spotlight, an expanded
  // card — and only closes the panel once nothing else is open. Each field's
  // onDismissed routes here (the field owns focus, so Escape reaches its
  // Keys.onPressed rather than the key catcher's onCloseRequested); the key
  // catcher routes here too when no search field owns focus.
  function handleSearchEscape() {
    if (root.searchSuggestionsVisible) {
      root.searchSuggestionsDismissed = true;
    } else if (root.openSheet) {
      root.openSheet = false;
    } else if (root.spotlight) {
      root.leaveSpotlight();
    } else if (root.expandedSpotName !== null) {
      root.collapseRow();
    } else {
      root.close();
    }
  }

  // Toggle a row's expanded state; tapping the expanded row collapses it. The
  // editor reads the journal entry directly — stars commit immediately and notes
  // stage via notesEdited() — so there is no edit state to seed on open.
  function toggleRow(spotName) {
    if (root.expandedSpotName === spotName) {
      root.collapseRow();
    } else {
      root.expandedSpotName = spotName;
    }
  }

  function toggleSaved(spotName, cityKey) {
    root.ratingHold = true;
    root.holdCheckName = spotName;
    // Compare name-first with the stored city as disambiguator, so a spot saved
    // under old casing (or the same name in a different city) is recognized and
    // toggled off instead of duplicated; the entry written to `saved` still
    // keeps its original casing and the canonical city slug.
    var index = root.findSavedIndex(spotName, cityKey);
    if (index >= 0) {
      root.saved.splice(index, 1);
    } else {
      root.saved.push({ name: spotName, city: cityKey });
    }
    // Reassign a fresh array so bindings on `saved` (Repeater model, heart
    // glyphs) re-evaluate after the in-place mutation.
    root.saved = root.saved.slice();
    savedFile.setText(JSON.stringify(root.saved));
  }

  // Fire an omakase IPC command. The method string is a parameter (the typed
  // rateSpot/unrateSpot wrappers below pass "rate"/"unrate"), so this seam
  // stays generic. All rating actions go through the Service, which owns the
  // journal — the bar widget never writes it.
  function sendIpcCommand(method, args) {
    Quickshell.execDetached(["omarchy-shell", root.moduleName, method].concat(args));
  }

  // Stage a notes edit and (re)start the debounce timer; flushNotes() commits
  // the tuple once the timer expires. `restart()` covers a repeat keystroke
  // while a previous commit is still pending.
  function notesEdited(name, text, cityKey) {
    root._pendingNotesName = name;
    root._pendingNotesCity = cityKey;
    root._pendingNotesText = text;
    notesDebounceTimer.restart();
  }

  // Commit the staged notes edit, if any. Reads the spot's CURRENT rating from
  // the journal and re-rates with the staged notes; clears the pending tuple
  // either way. A spot with no rating is a no-op (the notes box is disabled
  // without one) — guarded, not assumed.
  function flushNotes() {
    if (root._pendingNotesName === "") return;
    var name = root._pendingNotesName;
    var city = root._pendingNotesCity;
    var text = root._pendingNotesText;
    root._pendingNotesName = "";
    root._pendingNotesCity = "";
    root._pendingNotesText = "";
    var entry = root.latestJournalFor(name);
    if (!entry || !entry.rating) return;
    // Dispatch before the flash. The flash is decoration; it must never sit
    // between the pending state being cleared and the write going out, or a
    // throw in it silently drops the user's notes.
    root.rateSpot(name, String(entry.rating), text, city);
    root.notesJustSaved = true;
    notesSavedTimer.restart();
  }

  // Typed wrappers so call sites stop assembling the argument array themselves.
  // The encoding stays byte-identical to what the Service truncates and parses.
  function rateSpot(name, stars, notes, city) {
    root.ratingHold = true;
    root.holdCheckName = name;
    // A star click passes the spot's committed journal notes, which lag a notes
    // edit still staged in the debounce tuple. Adopt that pending text for the
    // SAME spot and cancel the timer, so the click carries what the user typed
    // instead of the stale journal value — and the two writes cannot race (the
    // pending flush would otherwise fire after the click and overwrite it).
    if (root._pendingNotesName !== "" &&
        SpotUtils.normalizeName(root._pendingNotesName) === SpotUtils.normalizeName(name)) {
      notes = root._pendingNotesText;
      root._pendingNotesName = "";
      root._pendingNotesCity = "";
      root._pendingNotesText = "";
      notesDebounceTimer.stop();
    }
    sendIpcCommand("rate", [name, String(stars), notes, city]);
  }
  function unrateSpot(name, city) {
    root.ratingHold = true;
    root.holdCheckName = name;
    sendIpcCommand("unrate", [name, city]);
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
  function selectLocationScope(scope, value) {
    root.setLocationScopes(scope, value);
    root.radius = 0;
  }

  // Clear the named location scopes (city/state/country/neighborhood) while
  // KEEPING the radius — the radius is not a location scope, so dropping a
  // location token must not zero it. This is the keep-radius seam
  // FilterBar.clearLocationScope delegates to (the Location-token path);
  // selectLocationScope is the real-scope-pick path, which clears the scopes
  // AND zeroes the radius.
  function clearLocationScopeFilters() {
    root.clearFilterState({});
  }

  // Shared scope assignments: the picked scope gets `value`, every other scope
  // clears (they are mutually exclusive), and any open dropdown closes. The
  // radius is deliberately not part of this body — selectLocationScope clears it
  // on a real pick, clearLocationScopeFilters (the Radius pill path) leaves it alone —
  // so a fifth scope still needs only this one edit site.
  function setLocationScopes(scope, value) {
    root.cityKey = (scope === CatalogUtils.SCOPE_CITY) ? value : "";
    root.stateFilter = (scope === CatalogUtils.SCOPE_STATE) ? value : "";
    root.countryFilter = (scope === CatalogUtils.SCOPE_COUNTRY) ? value : "";
    root.neighborhood = (scope === CatalogUtils.SCOPE_NEIGHBORHOOD) ? value : "";
    root.openDropdown = "";
  }

  // Single clear body behind every clear entry point, so a future filter cannot
  // be cleared from only one of them. The four location scopes always clear
  // through setLocationScopes("", "") — the one place that knows which fields
  // are location scopes. The non-location clearers are flag-gated:
  //   radius  — zero the radius (the Radius pill path must not)
  //   filters — reset kind + unrated to their defaults
  //   sort    — reset sortBy/sortReversed to distance/ascending
  //   sheet   — close the floating filter sheet
  function clearFilterState(opts) {
    opts = opts || {};
    root.setLocationScopes("", "");
    if (opts.radius) root.radius = 0;
    if (opts.filters) {
      root.kindFilter = CatalogUtils.KIND_FILTER_ALL;
      root.unratedOnly = false;
    }
    if (opts.sort) {
      root.sortBy = CatalogUtils.SORT_KEYS[0];  // reset to the default sort key
      root.sortReversed = false;
    }
    if (opts.sheet) root.openSheet = false;
  }

  // A neighborhood pick sets both the neighborhood filter and its city key:
  // selectLocationScope sets the neighborhood name, then the city key is applied
  // here (the two scopes live together — a neighborhood always belongs to its
  // city).
  function selectNeighborhood(neighborhood, cityKey) {
    root.selectLocationScope(CatalogUtils.SCOPE_NEIGHBORHOOD, neighborhood);
    root.cityKey = cityKey;
  }

  function selectCity(cityKey) {
    root.selectLocationScope(CatalogUtils.SCOPE_CITY, cityKey);
  }

  function selectState(stateKey) {
    root.selectLocationScope(CatalogUtils.SCOPE_STATE, stateKey);
  }

  function selectCountry(countryKey) {
    root.selectLocationScope(CatalogUtils.SCOPE_COUNTRY, countryKey);
  }

  // Clear every filter in one click — the surviving clear-all name (FilterBar's
  // "Clear all filters" and the both-active empty-state "Clear search and filters" both
  // route here). Location scopes + radius clear, kind and unrated return to
  // their defaults, sort returns to distance/ascending, and the sheet closes.
  // A future filter is cleared by adding one line to clearFilterState, never by
  // re-implementing a clear.
  function clearAllFilters() {
    root.clearFilterState({ radius: true, filters: true, sort: true, sheet: true });
  }

  // ---- Utility ----

  // Unique neighborhood names for the current city, sorted, scoped to the
  // active view (the bundle's byCity records for the selected city — so a
  // Journal/Wishlist view surfaces only neighborhoods its own spots reach). The
  // "All neighborhoods" clear affordance lives in the dropdown's clearLabel row
  // and the chip strip's leading "All neighborhoods" chip, not in this list. Declarative so
  // no binding ever writes it; it is a pure read.
  readonly property var neighborhoodOptions: {
    root.cityKey;
    root.activeLocationBundle;
    var bundle = root.activeLocationBundle;
    var records = (bundle.byCity && bundle.byCity[root.cityKey]) || [];
    return CatalogUtils.computeNeighborhoodNames(records);
  }

  // Single-pass state + country aggregation, shared by states and countries so
  // the catalog is scanned once instead of twice. Only US states are surfaced
  // as "state" filters — a spot counts as a state only when its `region_code` is a
  // 2-letter US code AND its `country` is "US" (computeLocationAggregates gates
  // via CatalogUtils.isUsState), so a foreign region code that collides with a
  // US state code (e.g. Amsterdam's "NH" = Noord-Holland) never appears as a
  // state, and non-US region codes (e.g. "VIC"/"11") never cluttered the picker
  // in the first place. Declarative so no binding ever writes it; it is a pure
  // read. distanceVersion is the catalog trigger (see sortedSpots) so the
  // nearest-value ordering never reads the empty map installed at the start of
  // a catalog/home change. cachedFlatSpots() and the distance accessor are function
  // calls, so their `catalog`/`distanceByCoords`/`homeLat` reads stay untracked
  // and distanceVersion remains the only trigger that fires.
  readonly property var locationAggregates: {
    root.distanceVersion;
    return CatalogUtils.computeLocationAggregates(root.cachedFlatSpots(), function (spot) {
      return distanceKmOrUndefined(spot);
    });
  }

  // States present in the catalog (from Yelp "region_code" field), each aggregated
  // across all cities with its spot count, sorted alphabetically with the
  // nearest state first. Result is [{ key, count, foldedCode, foldedName }].
  // foldedCode/foldedName are precomputed by CatalogUtils.buildStateOptions
  // (once per catalog/home change) so buildSearchHits folds only the query per
  // keystroke.
  readonly property var stateOptions: {
    root.locationAggregates;
    return CatalogUtils.buildStateOptions(root.locationAggregates);
  }

  // Countries present in the catalog (Yelp "country" field), aggregated across
  // all cities with spot counts, sorted alphabetically with the nearest country
  // first. [{ key, count }].
  readonly property var countries: {
    root.locationAggregates;
    var aggregates = root.locationAggregates;
    return CatalogUtils.sortedCountList(aggregates.countryCounts, aggregates.nearestCountry);
  }

  // Cities ordered by distance from home (nearest first); geo-less cities last,
  // scoped to the active view (the bundle's cities — so a Journal/Wishlist view
  // only offers cities its own spots reach). Each record is { key, distance }:
  // the haversine runs once here, and cityFilterItems formats its label from
  // `distance`, so the sort and the label can never read a different distance.
  // Depends on catalogVersion (city list + fallback coords) and home (distance),
  // plus the active view's bundle.
  readonly property var sortedCities: {
    root.activeLocationBundle;
    root.catalogVersion;
    root.homeLat;
    root.homeLon;
    return CatalogUtils.computeSortedCities(root.activeLocationBundle.cities, function (cityKey) {
      return root.cityDistanceKm(cityKey);
    });
  }

  // FilterDropdown item lists — { key, label } pairs consumed by the generic
  // dropdown. The builders live in catalog-utils.js (pure, unit-tested); these
  // declarative properties pass the resolved inputs so the four FilterPanel
  // instances share one build per catalog/filter change instead of rebuilding
  // the arrays on every evaluation. Each lists its source data as an explicit
  // dep because reads inside the builder callbacks are not tracked. The list
  // AND its counts come from the active view's bundle, so a scoped view never
  // offers (or counts) a location its own spots can't match. City labels format
  // from the `sortedCities` records' own `distance` (the shared builder reuses
  // it), so the sort and the label read one distance — the haversine runs once.
  readonly property var cityFilterItems: {
    root.sortedCities;
    root.activeLocationBundle;
    return CatalogUtils.buildCityFilterItems(root.sortedCities, function (cityKey) {
      var counts = root.activeLocationBundle.counts;
      return (counts && counts[cityKey]) || 0;
    });
  }

  readonly property var stateFilterItems: {
    root.activeLocationBundle;
    return CatalogUtils.buildCodeCountItems(root.activeLocationBundle.states);
  }

  readonly property var countryFilterItems: {
    root.activeLocationBundle;
    return CatalogUtils.buildCodeCountItems(root.activeLocationBundle.countries);
  }

  readonly property var neighborhoodFilterItems: {
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

  // Copy `text` to the clipboard via wl-copy, falling back to xclip. This is
  // the single clipboard mechanism both the card's Copy action (SpotCard) and
  // the collapsed cluster's phone cell (SpotCard) share; the "Copied"
  // feedback stays with each caller's own transient state.
  function copyToClipboard(text) {
    Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy 2>/dev/null || printf '%s' \"$1\" | xclip -selection clipboard 2>/dev/null", "_", text]);
  }

  // Shared body for the nine filter/sort/scope controls below: a change to any
  // is an explicit control change, so it drops the rating hold and resets the
  // paging window. QML cannot bind one handler to multiple signals, so each
  // control keeps a one-line stub that calls this.
  function resetWindowAndRelease() { root.releaseListHold(); pagingWindow.reset() }

  onCityKeyChanged: root.resetWindowAndRelease()
  onNeighborhoodChanged: root.resetWindowAndRelease()
  onKindFilterChanged: root.resetWindowAndRelease()
  onRadiusChanged: root.resetWindowAndRelease()
  onSortByChanged: root.resetWindowAndRelease()
  onSortReversedChanged: root.resetWindowAndRelease()
  onSearchTextChanged: {
    // A search-text change is debounced: debouncedSearchText (and therefore
    // searchedSpots/searchedCount) settles only after searchDebounceMs, so the
    // window reset must defer its lookahead seed — reading the count now would
    // consume the one-shot against the previous query's stale result count. The
    // seed runs from onSearchedSpotsChanged when the debounced value lands (and
    // for the cleared-field flush below, when the empty value is applied
    // immediately).
    root.releaseListHold();  // a query edit is a control change
    pagingWindow.reset(true)  // defer the lookahead seed (see above)
    // Re-open the suggestions dropdown (a query change clears the dismissal
    // flag). The hold is already released above; calling handleQueryEdited
    // here would release it a second time.
    root.searchSuggestionsDismissed = false
    // A query edit is a control change too: clicking into the field closes the
    // filter sheet so it never floats over the typing surface.
    root.openSheet = false
    if (root.searchText === "") {
      // Clearing the field is instant: stop the timer and flush an empty
      // debouncedSearchText so the full list reappears without waiting out the
      // debounce window.
      searchDebounceTimer.stop()
      root.debouncedSearchText = ""
    } else {
      searchDebounceTimer.restart()
    }
  }
  // Shared body for the Wishlist/Journal query edits: re-open the suggestions
  // dropdown (any query change clears the dismissal flag) and release the list
  // hold (a query edit is an explicit control change, so a held snapshot must
  // drop). onSearchTextChanged does NOT call this — it already releases the
  // hold before pagingWindow.reset(true) and only needs the dismissal flag
  // cleared, so routing it here would double-release on every keystroke. QML
  // cannot bind one handler to multiple signals, hence the shared function.
  function handleQueryEdited() {
    root.searchSuggestionsDismissed = false;
    root.releaseListHold();
    // A query edit is a control change: close the sheet alongside the hold
    // release so the Wishlist/Journal fields dismiss it on focus.
    root.openSheet = false;
  }
  onWishlistQueryChanged: root.handleQueryEdited()
  onJournalQueryChanged: root.handleQueryEdited()
  onUnratedOnlyChanged: root.resetWindowAndRelease()
  onStateFilterChanged: root.resetWindowAndRelease()
  onCountryFilterChanged: root.resetWindowAndRelease()
  // Journal data feeds ratedEntries/sortedJournal (declarative) and the
  // eagerly-maintained rating maps; rebuild those maps and the display-city map.
  onJournalChanged: { refreshRatings(); buildCityLabelMap(); root.scheduleHoldCheck() }
  onSavedChanged: { refreshSavedSet(); root.scheduleHoldCheck() }
  // Neighborhood list derives from catalog data, not just cityKey.
  onCatalogChanged: {
    // Read-and-reset first so the flag can never leak into a later load (the
    // empty-catalog guard below returns before the rebuilds).
    var homeMoveOnly = root.catalogHomeMoveOnly;
    root.catalogHomeMoveOnly = false;
    // `catalog` is a lazily-evaluated `property var` binding, so its first read
    // (cachedFlatSpots inside the sortedSpots binding) evaluates it and fires this
    // handler while sortedSpots is mid-evaluation. Running the rebuild then
    // would write sortedSpots's tracked deps — distanceVersion (via
    // refreshDistanceCache) and ratingsBySpot/journalByName (via
    // buildCityLabelMap -> journal -> onJournalChanged -> refreshRatings) — and
    // re-enter the binding. The placeholder catalog is empty, so there is
    // nothing to rebuild: skip it until real data lands.
    if (!root.catalog.cities || root.catalog.cities.length === 0) return;
    // Build the canonical-city alias map BEFORE the index walk is kicked off, so
    // the aliases are ready when the walk's done runs the resolving wishlist
    // migration (canonicalCityKey must see the current catalog's slugs).
    var cityKeys = (root.catalog.cities && root.catalog.cities.length)
      ? root.catalog.cities
      : Object.keys(root.catalog.spotsByCity || {});
    root.cityAliases = JournalIdentity.buildCityAliases(cityKeys);
    root.refreshSavedSet();
    // The derived-field stamp, the spot index, and the flat list are pure
    // functions of the spots, so a home move (identical spots, only homeLat/
    // homeLon changed) skips all three — loadCatalog already reused the stamped
    // spot objects. The distance walk is the one walk that depends on home, so
    // it always runs (below).
    if (!homeMoveOnly) {
      buildFlatSpots();
      rebuildCatalogIndex();
    }
    refreshDistanceCache();
    buildCityLabelMap();
    catalogVersion++;
  }
  // homeLat/homeLon are derived solely from `catalog`, so onCatalogChanged
  // already bumps catalogVersion for a home move. The distance-keyed caches
  // (sortedSpots/sortedWishlist/sortedJournal/locationAggregates) deliberately
  // gate on distanceVersion — bumped by refreshDistanceCache above — rather
  // than homeLat/homeLon, so they never re-run against the empty distance map;
  // sortedCities is the one cache that lists homeLat/homeLon directly.

  KeyboardPanel {
    id: panel
    anchorItem: barButton
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(450))
    contentHeight: Math.min(
      root.pinnedHeaderHeight
      + (root.spotlight ? spotlightView.implicitHeight : root.activeTabHeight)
      + panel.verticalContentInset,
      root.maxPanelHeight)
    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // While any search field owns keyboard focus, forward ALL keys to it so
      // typing (including Space/arrows) and Escape reach the field instead of
      // the panel's cursor/close shortcuts. `searchFieldHasFocus` is a live
      // activeFocus aggregate across the Explore, Wishlist, and Journal search
      // fields (Spotlight reuses Explore's field).
      blocked: root.searchFieldHasFocus
      onCloseRequested: root.handleSearchEscape()

      // Dismiss overlay: covers the region below the pinned header and dismisses
      // the open popover (filter sheet or search-suggestions dropdown) on an
      // outside tap. Declared BEFORE pinnedHeader so, at the shared z: 2, the
      // pinned header — and everything inside it (the sheet, the dropdowns, the
      // search fields and chips) — paints above this and stays interactive, while
      // the card list (flick at z: 0, delegates at z: 1) sits below. Anchored to
      // pinnedHeader.bottom, so it covers only the content below the header: the
      // header stays visible in Spotlight too, and the sheet/dropdown live inside
      // it, so the overlay never paints over them.
      Item {
        id: popoverDismissOverlay
        anchors.top: pinnedHeader.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        z: 2
        visible: root.openSheet || root.searchSuggestionsVisible

        // TapHandler rather than MouseArea: an outside tap must dismiss only, never
        // activate the card or control underneath. Dismissal reuses the existing
        // paths — the sheet's openSheet flag (its onOpenSheetChanged clears
        // openDropdown) and the dropdown's searchSuggestionsDismissed flag (the
        // same one handleSearchEscape sets).
        TapHandler {
          onTapped: root.dismissPopovers()
        }
      }

      // Pinned header: tab chips + Surprise Me, above the scroller so they stay
      // visible while the list scrolls. Stays visible in Spotlight too — the
      // spotlight view reuses this header's Explore chrome.
      Item {
        id: pinnedHeader
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.pinnedHeaderHeight
        // Lift the pinned header above the Flickable so the search dropdown and
        // the floating FilterSheet paint over the cards instead of under them.
        // The back-to-top FAB (z: 10) stays above this.
        z: 2

        // Header dismiss surface: a tap on the header's non-interactive area
        // (the 16px margins, the gaps between controls, the space below the
        // pinned column) dismisses an open popover, mirroring the overlay
        // below. A TapHandler observes passively, so a control's MouseArea
        // still takes the exclusive grab and this handler never fires for a
        // control click — the control does its job, including the "More
        // filters" toggle, which this handler therefore cannot invert. The
        // floating FilterSheet and the search dropdown live in pinnedColumn
        // (z: 2, above this z: 0 surface), so a tap on either popover reaches
        // the popover, not this surface.
        Item {
          anchors.fill: parent
          visible: root.openSheet || root.searchSuggestionsVisible
          TapHandler {
            onTapped: root.dismissPopovers()
          }
        }

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
              // Spotlight reuses Explore's chrome (chromeView), but no tab is
              // active there — the Surprise pill carries the active state.
              activeTab: root.spotlight ? "" : root.tab
              width: parent.width - surpriseButton.width - parent.spacing
              onPicked: function(tab) { root.spotlight = false; root.switchTab(tab) }
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
              active: root.spotlight
              enabled: root.surprisePoolSize > 0
            }
          }

          // Pinned search + filter for every tab. Pinning them below the tab row
          // keeps search/filter reachable while the card list scrolls; the list
          // remains the only scroller. Each view's chrome is visible-gated
          // (search field + dropdown, then FilterPanel) so exactly one view's
          // search/filter exists on screen at a time.
          // Explore search + suggestions. Shared with Spotlight (which reuses
          // Explore's chrome), so the header gates its dropdown on chromeView
          // via useChromeView rather than activeSearchView. The Explore field
          // keeps SearchField's default insets, so they are passed explicitly
          // (the tabs use TabSearchHeader's tighter 8px defaults).
          TabSearchHeader {
            id: exploreHeader
            visible: root.chromeView === CatalogUtils.VIEW_EXPLORE
            panel: root
            viewName: CatalogUtils.VIEW_EXPLORE
            useChromeView: true
            query: root.searchText
            placeholder: root.searchPlaceholder
            leftInset: Style.space(10)
            rightInset: Style.space(6)
            onEdited: function(v) { root.searchText = v }
            onDismissed: root.handleSearchEscape()
            onFieldClicked: root.openSheet = false
          }

          // FilterBar primary row + active-filter summary. The neighborhood
          // chip strip stays in the ExploreTab ListView header (it can be
          // several rows tall and is secondary to the primary row).
          FilterPanel {
            visible: root.chromeView === CatalogUtils.VIEW_EXPLORE
            panel: root
            allowNeighborhoodChips: false
          }

          // Wishlist pinned search + filter. The search field carries its own
          // suggestions dropdown (inside TabSearchHeader), so the order
          // search -> filter holds per view.
          TabSearchHeader {
            id: wishlistHeader
            visible: root.chromeView === CatalogUtils.VIEW_WISHLIST
            panel: root
            viewName: CatalogUtils.VIEW_WISHLIST
            query: root.wishlistQuery
            placeholder: root.wishlistSearchPlaceholder
            onEdited: function(v) { root.wishlistQuery = v }
            onDismissed: root.handleSearchEscape()
            onFieldClicked: root.openSheet = false
          }
          FilterPanel {
            visible: root.chromeView === CatalogUtils.VIEW_WISHLIST
            panel: root
            allowNeighborhoodChips: true
          }

          // Journal pinned search + filter. The Journal search field is taller
          // with a smaller clear button than the default.
          TabSearchHeader {
            id: journalHeader
            visible: root.chromeView === CatalogUtils.VIEW_JOURNAL
            panel: root
            viewName: CatalogUtils.VIEW_JOURNAL
            query: root.journalQuery
            placeholder: root.journalSearchPlaceholder
            fieldHeight: Style.space(36)
            clearSize: 16
            onEdited: function(v) { root.journalQuery = v }
            onDismissed: root.handleSearchEscape()
            onFieldClicked: root.openSheet = false
          }
          FilterPanel {
            visible: root.chromeView === CatalogUtils.VIEW_JOURNAL
            panel: root
            allowNeighborhoodChips: false
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
        contentHeight: root.spotlight ? spotlightView.implicitHeight : ((root.tab === CatalogUtils.VIEW_EXPLORE) ? root.maxPanelHeight : root.activeTabHeight)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: !root.exploreActive && contentHeight > height
        // Coarse scroll bucket for image gating. Cards bind their image
        // visibility to this integer instead of to `contentY`, so a card's
        // binding re-evaluates only when the bucket changes (every
        // `imageBucketHeight` px) rather than on every scroll frame. The
        // Explore tab's own ListView owns its bucket; this one serves the
        // other tabs.
        property int imageWindowStart: 0
        onContentYChanged: {
          var bucket = CatalogUtils.computeImageWindowBucket(contentY, root.imageBucketHeight);
          if (bucket !== imageWindowStart) imageWindowStart = bucket;
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
            paging: pagingWindow
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

        SpotlightView { id: spotlightView; panel: root; scrollView: flick }

      }

      Rectangle {
        z: 10
        visible: exploreTab && exploreTab.contentY > root.backToTopScrollThreshold && root.exploreActive
        anchors.right: parent.right; anchors.rightMargin: Style.space(16)
        // Tuck the arrow near the panel's bottom edge.
        anchors.bottom: parent.bottom; anchors.bottomMargin: Style.space(16)
        width: Style.space(40); height: Style.space(40)
        radius: Style.space(20)
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
          font.pixelSize: Style.font.iconLarge
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
