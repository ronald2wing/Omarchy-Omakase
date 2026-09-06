import QtQuick
import qs.Commons

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
  property real availableHeight: Style.space(360)
  // Coarse scroll bucket for image gating, mirroring the outer Flickable's
  // imageWindowStart. Cards read this instead of contentY so their image
  // binding re-evaluates only when the bucket changes.
  property int imageWindowStart: 0

  visible: panel.tab === "explore" && !panel.spotlight
  width: parent.width - Style.space(32)
  height: availableHeight
  clip: true
  interactive: true
  reuseItems: true
  cacheBuffer: Style.space(500)
  boundsBehavior: Flickable.StopAtBounds
  model: panel.exploreModel

  onContentYChanged: {
    var bucket = Math.floor(contentY / panel.imageBucketHeight);
    if (bucket !== imageWindowStart) imageWindowStart = bucket;
    // Prefetch the next batch once fewer than one page-height of scroll
    // remains below the viewport. The fill starts immediately (no debounce)
    // and adds a full page per trigger, all at once.
    var pagePx = panel.pageSize * panel.collapsedCardHeight;
    var remaining = contentHeight - (contentY + height);
    if (remaining < pagePx && panel.visibleCount < panel.filteredCount && !panel.prefetching) {
      panel.prefetching = true;
      panel.fillPrefetch();
    }
  }

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
      visible: exploreTab.panel.cityKey !== "" && exploreTab.panel.tab === "explore"
      count: exploreTab.panel.searchedSpots.length
      plural: true
      // The debounced query the list actually filtered by, so the hint's
      // wording and the count can never disagree.
      query: exploreTab.panel.searchQuery
      onBack: {
        exploreTab.panel.applyLocationScope("", "");
        exploreTab.panel.searchText = "";
      }
      // Clearing searchText flushes an empty searchQuery immediately
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
    journalEntry: exploreTab.panel.latestJournalFor(modelData.name)
    starsInteractive: true
    showCity: exploreTab.panel.showsCityLabels() && !!modelData._cityKey
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
      visible: exploreTab.panel.searchedSpots.length > exploreTab.panel.visibleCount
      Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: "Show " + Math.min(exploreTab.panel.pageSize, exploreTab.panel.searchedSpots.length - exploreTab.panel.visibleCount) + " more (" + (exploreTab.panel.searchedSpots.length - exploreTab.panel.visibleCount) + " remaining)"
        color: exploreTab.panel.secondaryColor
        font.pixelSize: Style.font.bodySmall
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: exploreTab.panel.visibleCount += exploreTab.panel.pageSize
      }
    }
    // Empty state — the footer sits after the (empty) delegate list, so it
    // reads as the content area's empty state.
    EmptyState {
      panel: exploreTab.panel
      visible: exploreTab.panel.searchedSpots.length === 0
      glyph: "\uf002"
      headline: {
        var where = exploreTab.panel.cityKey
          ? "No spots in " + exploreTab.panel.cityLabel(exploreTab.panel.cityKey) + " match"
          : "No spots match";
        return where + (exploreTab.panel.searchQuery ? " your search." : " your filters.");
      }
      caption: "Try a different search or clear your filters."
    }
    // Trailing clearance for the floating back-to-top arrow (40px tall, 72px
    // from the bottom). Without it the last card sits under the arrow and
    // cannot be scrolled clear. 72 + 40 = 112, rounded up for a small gap.
    // Collapsed in the empty state — there is no last card to clear, and the
    // arrow is hidden, so the clearance would only pad the panel.
    Item {
      width: parent.width
      height: exploreTab.panel.searchedSpots.length > 0 ? Style.space(120) : 0
    }
  }
}
