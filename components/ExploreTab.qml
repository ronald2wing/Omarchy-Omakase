import QtQuick
import qs.Commons
import "../catalog-utils.js" as CatalogUtils

// Explore tab: virtualized spot list. `panel` is the BarWidget root (filter
// state, helpers, actions). The search field and the FilterBar primary row are
// pinned above this list by BarWidget's pinned header; only the city header and
// the neighborhood chip strip scroll with the cards here.
//
// The root is a ListView (not a Column) so only on-screen cards instantiate:
// the header and footer are ListView header/footer items, and the delegate
// list is the only scroller for this tab. `availableHeight` is set by the root
// from the panel geometry.
ListView {
  id: exploreTab
  property Item panel
  // The pagination window (PagingWindow) — owns the card count and the grow
  // primitives this list's scroll trigger and footer button drive.
  property PagingWindow paging
  property real availableHeight: Style.space(360)
  // Coarse scroll bucket for image gating, mirroring the outer Flickable's
  // imageWindowStart. Cards read this instead of contentY so their image
  // binding re-evaluates only when the bucket changes.
  property int imageWindowStart: 0
  // Height of the trailing FAB-clearance spacer (the footer's last item),
  // written imperatively by updateTrailingSpacer() rather than bound. A live
  // binding over contentHeight would loop: the spacer is part of the footer, so
  // it feeds contentHeight, which the overflow test reads to decide the spacer's
  // own height. The handler compares the REAL content (contentHeight minus the
  // spacer) against availableHeight, and the equality guard skips the write once
  // settled, so the fixed point converges in at most one extra pass.
  property real trailingSpacer: 0

  visible: panel.tab === CatalogUtils.VIEW_EXPLORE && !panel.spotlight
  width: parent.width - panel.contentInset
  // Shrink to fit a short result set (matching Wishlist/Journal): when the
  // content fits inside the viewport the list is exactly contentHeight tall and
  // stops scrolling, so the panel collapses to its cards instead of leaving a
  // large empty region below them. `exploreListMinHeight` is the floor, applied
  // only when the list is EMPTY — it exists so the empty state has room to
  // render, not to pad a short result list. `availableHeight` caps it at the
  // un-shrunk viewport height (tall content keeps scrolling internally).
  height: panel.exploreModel.length === 0
    ? Math.max(panel.exploreListMinHeight, Math.min(availableHeight, contentHeight))
    : Math.min(availableHeight, contentHeight)
  clip: true
  interactive: true
  reuseItems: true
  cacheBuffer: Style.space(500)
  boundsBehavior: Flickable.StopAtBounds
  model: panel.exploreModel

  // Advance the coarse scroll bucket (image gating) when the list scrolls. The
  // write is imperative (imageWindowStart is a plain property, not a binding),
  // so the body is a named function called from onContentYChanged.
  function updateImageWindowBucket() {
    var bucket = CatalogUtils.computeImageWindowBucket(contentY, panel.imageBucketHeight);
    if (bucket !== imageWindowStart) imageWindowStart = bucket;
  }

  onContentYChanged: {
    updateImageWindowBucket();
    // Prefetch the next batch once fewer than one page-height of scroll
    // remains below the viewport. The fill starts immediately (no debounce)
    // and adds a full page per trigger, all at once. `paging.viewportHeight`
    // (the maximum, un-shrunk viewport height) is the measure, not `height`:
    // a shrunk list reads height == contentHeight, which would leave the
    // remaining-headroom ~0 and prefetch the entire match set.
    var remaining = contentHeight - (contentY + paging.viewportHeight);
    if (remaining < paging.pagePx && paging.visibleCount < paging.searchedCount && !paging.prefetching && !paging.holdActive) {
      paging.prefetching = true;
      paging.fillPrefetch();
    }
  }

  // Recompute the trailing FAB-clearance spacer imperatively: the spacer is
  // present (120px) only when the REAL scrollable content — everything except
  // the spacer itself — overflows `availableHeight`, i.e. the list actually
  // scrolls and the back-to-top arrow can overlap the last card. A short,
  // non-scrolling list gets 0. Runs on contentHeight/availableHeight changes;
  // the equality guard makes the contentHeight feedback converge instead of
  // looping.
  function updateTrailingSpacer() {
    var realContent = contentHeight - trailingSpacer;
    var next = realContent > availableHeight ? Style.space(120) : 0;
    if (next !== trailingSpacer) trailingSpacer = next;
  }
  onContentHeightChanged: updateTrailingSpacer()
  onAvailableHeightChanged: updateTrailingSpacer()

  // Animate the list back to its very top so the search/filter header is flush
  // with the viewport. `cancelFlick()` first: a live momentum animation would
  // otherwise keep writing contentY and fight the animation. The final
  // `positionViewAtBeginning()` snaps any residual offset (e.g. a header
  // height that changed mid-animation) so the header is guaranteed visible.
  function scrollToTop() {
    cancelFlick();
    scrollToTopAnim.start();
  }

  NumberAnimation {
    id: scrollToTopAnim
    target: exploreTab
    property: "contentY"
    to: 0
    duration: 250
    easing.type: Easing.OutCubic
    onFinished: exploreTab.positionViewAtBeginning()
  }

  // The search field and the FilterBar primary row are pinned above the list
  // (BarWidget's pinned header), so only the city header and the neighborhood
  // chip strip scroll with the cards here. The chip strip can be several rows
  // tall and is secondary to the primary filter row, so it stays in the header.
  header: Column {
    width: exploreTab.width
    spacing: Style.space(10)

    CityHeader {
      panel: exploreTab.panel
      visible: exploreTab.panel.cityKey !== "" && exploreTab.panel.tab === CatalogUtils.VIEW_EXPLORE
      count: exploreTab.paging.searchedCount
      plural: true
      // The debounced query the list actually filtered by, so the hint's
      // wording and the count can never disagree.
      query: exploreTab.panel.debouncedSearchText
      onBack: {
        exploreTab.panel.selectLocationScope("", "");
        exploreTab.panel.searchText = "";
      }
      // Clearing searchText flushes an empty debouncedSearchText immediately
      // (onSearchTextChanged), so the list returns to the full scope.
      onClearQuery: exploreTab.panel.searchText = ""
    }
    NeighborhoodChips { panel: exploreTab.panel }
  }

  delegate: SpotCard {
    panel: exploreTab.panel
    scrollView: exploreTab
    spot: modelData
    cityKey: modelData._cityKey
    fallbackName: modelData.name
    starsInteractive: true
    showCity: exploreTab.panel.showsCityLabels && !!modelData._cityKey
    useHoverBg: false
    zebraStripe: index % 2
  }

  footer: Column {
    width: exploreTab.width
    spacing: Style.space(8)

    Rectangle {
      width: parent.width
      height: Style.space(40)
      radius: Style.cornerRadius
      color: "transparent"
      border.color: exploreTab.panel.secondaryColor
      border.width: 1
      visible: exploreTab.paging.searchedCount > exploreTab.paging.visibleCount
      Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: {
          var remaining = exploreTab.paging.searchedCount - exploreTab.paging.visibleCount;
          return "Show " + Math.min(exploreTab.paging.pageSize, remaining) + " more (" + remaining + " remaining)";
        }
        color: exploreTab.panel.secondaryColor
        font.pixelSize: Style.font.bodySmall
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          // An explicit request for more rows settles the frozen list first,
          // otherwise the held snapshot ignores the window growth.
          exploreTab.panel.releaseListHold();
          exploreTab.paging.showMore();
        }
      }
    }
    // Empty state — the footer sits after the (empty) delegate list, so it
    // reads as the content area's empty state.
    EmptyState {
      panel: exploreTab.panel
      visible: exploreTab.panel.exploreModel.length === 0
      glyph: "\uf002"
      headline: CatalogUtils.buildEmptyHeadline(
        "",
        exploreTab.panel.debouncedSearchText,
        exploreTab.panel.cityKey ? exploreTab.panel.cityLabel(exploreTab.panel.cityKey) : "")
      caption: CatalogUtils.EMPTY_STATE_CAPTION
      // Both a query and any filter are active: clearing only one changes
      // nothing, so the action clears both in one click. The single-cause
      // states leave actionLabel empty and keep their current look.
      actionLabel: (exploreTab.panel.debouncedSearchText !== "" && exploreTab.panel.hasActiveFilters)
        ? CatalogUtils.EMPTY_STATE_CLEAR_ACTION_LABEL : ""
      action: function () {
        exploreTab.panel.searchText = "";
        exploreTab.panel.clearAllFilters();
      }
    }
    // Trailing clearance for the floating back-to-top arrow (40px tall, 72px
    // from the bottom). Without it the last card sits under the arrow and
    // cannot be scrolled clear. 72 + 40 = 112, rounded up for a small gap.
    // Present only when the content actually overflows the viewport (the list
    // scrolls, so the arrow can appear and overlap the last card): a short,
    // non-scrolling list has no arrow and would otherwise carry this as pure
    // visible padding below the last card. The height is the imperatively
    // computed `trailingSpacer` (see updateTrailingSpacer) — a live binding
    // over contentHeight would loop, since the spacer feeds contentHeight and
    // the overflow test reads contentHeight to decide the spacer's own height.
    Item {
      width: parent.width
      visible: exploreTab.trailingSpacer > 0
      height: exploreTab.trailingSpacer
    }
  }
}
