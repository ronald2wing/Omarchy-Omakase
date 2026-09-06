import QtQuick

// Non-visual owner of the Explore pagination window. It tracks how many cards
// render (`visibleCount`) and every way that window grows: one page per "Show
// more" click, a one-page lookahead seed once per filter/search change, and a
// scroll-driven prefetch that keeps adding a page while the viewport is within
// a page-height of the bottom. The consumer injects the scroll viewport so the
// fill reads live geometry instead of reaching for a sibling id, plus the live
// hold/spot-count/page inputs so this file carries no BarWidget reads of its
// own.
//
// `advanced()` fires whenever the window size changes (a reset or a grow). The
// consumer re-slices its exploreModel on it — imperative, not a binding,
// because `visibleCount` is written mid-render by the grow primitives below.
QtObject {
  id: paging

  // ---- Inputs (set by the consumer) ----
  // The scrollable list whose geometry the fill reads. The fill computes the
  // remaining headroom as contentHeight - (contentY + viewportHeight), using the
  // injected maximum viewport height (not the live `height`, which the consumer
  // may shrink to fit a short result set). Typed Flickable (the viewport is the
  // Explore ListView) so the fill's contentHeight/contentY reads lint clean.
  property Flickable viewport
  // One page of cards. 88 by design: a Japanese lucky number (八十八 / 末広がり),
  // and roughly one viewport of collapsed cards at the consumer's card height.
  property int pageSize: 88
  // Post-search spot count — the total the window grows toward.
  property int searchedCount: 0
  // Whether the list is held (a rating/save in flight or a card open). A held
  // list never grows its window: the frozen snapshots don't change, so a
  // prefetch would balloon visibleCount and render everything on release.
  property bool holdActive: false
  // One page-height of scroll, in px — pageSize × the consumer's collapsed card
  // height. The fill compares the remaining headroom against it.
  property real pagePx: 0
  // The MAXIMUM viewport height (the consumer's un-shrunk list height). The
  // fill measures remaining headroom against this, NOT the live `viewport.height`,
  // because the consumer now shrinks the Explore ListView to its content when a
  // short result set fits the viewport: if the gate read the shrunk height,
  // remaining would collapse to ~0, the `remaining < pagePx` check would be
  // permanently true, and the fill would prefetch the entire match set — loading
  // everything and defeating pagination. A fixed maximum keeps the gate
  // independent of the shrink.
  property real viewportHeight: 0

  // ---- Outputs ----
  // How many cards render. Written imperatively by reset()/showMore() during the
  // render pass; the readonly alias keeps consumers from writing it back.
  property int _visibleCount: pageSize
  readonly property int visibleCount: _visibleCount
  // Guards the incremental prefetch: set while a fill is stepping through
  // event-loop turns so a storm of scroll events can't start a second fill.
  property bool prefetching: false
  // One-page lookahead has been established for the current filter/search
  // window; seedLookahead() runs at most once per change.
  property bool lookaheadSeeded: false
  // Emitted whenever the window size changes (reset or grow) so the consumer
  // re-slices its rendered list.
  signal advanced()

  on_VisibleCountChanged: paging.advanced()

  // Reset the paging window on every filter change. The consumer's declarative
  // caches re-evaluate on their own tracked inputs; no manual invalidation is
  // needed here.
  function reset(deferSeed) {
    paging._visibleCount = pageSize;
    paging.lookaheadSeeded = false;
    // The search-text path passes deferSeed: the debounced query (and therefore
    // searchedCount) does not land until the consumer's search debounce elapses,
    // so seeding here would read the previous query's stale count and consume
    // the one-shot lookahead. The consumer seeds from its searched-list-changed
    // handler once the debounced value actually lands.
    if (deferSeed) return;
    paging.seedLookahead();
  }
  // Grow the visible window by one page — the single primitive behind the
  // "Show N more" button and the automatic prefetch's fill step.
  function showMore() { paging._visibleCount += paging.pageSize }
  // Establish the one-page lookahead once per filter/search change: grow the
  // window by a single batch so the list starts a full page ahead of the
  // viewport even before any scroll event fires. Seeded from the consumer's
  // panel-open, reset, and searched-list-changed paths; `lookaheadSeeded` makes
  // it run at most once per change.
  function seedLookahead() {
    if (paging.lookaheadSeeded || paging.searchedCount <= 0 || paging.visibleCount >= paging.searchedCount) return;
    paging.lookaheadSeeded = true;
    paging.showMore();
  }
  // Prefetch: add a full page at once, then re-check the lookahead on the next
  // event-loop turn. `prefetching` is cleared once the lookahead is satisfied or
  // the list is exhausted, letting the next scroll event start a fresh fill.
  function fillPrefetch() {
    // A held list never grows its window (the frozen snapshots don't change),
    // so the lookahead would balloon visibleCount and render everything on
    // release. Stop and clear the guard; the next scroll restarts the fill.
    if (paging.holdActive) { paging.prefetching = false; return; }
    paging.showMore();
    var remaining = paging.viewport.contentHeight - (paging.viewport.contentY + paging.viewportHeight);
    if (remaining < paging.pagePx && paging.visibleCount < paging.searchedCount) {
      Qt.callLater(function() { paging.fillPrefetch(); });
    } else {
      paging.prefetching = false;
    }
  }
}
