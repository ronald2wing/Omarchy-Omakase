import QtQuick
import qs.Commons

// Explore tab: search + city search dropdown + filter panel + virtualized spot
// list. `panel` is the BarWidget root (filter state, helpers, actions).
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
  model: panel.exploreSpots

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

  // Animate the list back to its very top so the header (TabChips) is flush
  // with the viewport. `cancelFlick()` first: a live momentum animation would
  // otherwise keep writing contentY and fight the animation. The final
  // `positionViewAtBeginning()` snaps any residual offset (e.g. a header
  // height that changed mid-animation) so the chips are guaranteed visible.
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

  header: Column {
    width: exploreTab.width
    spacing: Style.space(10)
    // Lift the header above the delegates so a floating filter dropdown
    // (FilterPanel) paints over the cards below it instead of under them.
    z: 1

    // Tab chips scroll with the list (they live in the header, not pinned
    // above it). Width overridden to match the search field below.
    TabChips {
      panel: exploreTab.panel
      currentTab: exploreTab.panel.tab
      width: parent.width
      onPicked: function(tab) { exploreTab.panel.tab = tab; exploreTab.panel.collapseRow() }
    }

    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: "Explore"
      color: exploreTab.panel.secondaryColor
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1
      font.capitalization: Font.AllUppercase
    }

    SearchField {
      id: exploreInput
      panel: exploreTab.panel
      placeholder: exploreTab.panel.searchPlaceholder
      text: exploreTab.panel.searchText
      onEdited: function(v) { exploreTab.panel.searchText = v }
    }

    Column {
      id: searchDropdown
      width: parent.width
      spacing: 0
      readonly property var hits: exploreTab.panel.searchMatches(exploreTab.panel.searchText)
      visible: hits.length > 0 && !exploreTab.panel.cityKey
      Rectangle {
        width: parent.width
        height: cityDropList.implicitHeight + Style.space(8)
        radius: Style.cornerRadius
        color: exploreTab.panel.cardBackground
        border.color: exploreTab.panel.foregroundAlpha(0.1)
        Column {
          id: cityDropList
          anchors.left: parent.left; anchors.leftMargin: Style.space(8)
          anchors.right: parent.right; anchors.rightMargin: Style.space(8)
          anchors.top: parent.top; anchors.topMargin: Style.space(4)
          spacing: Style.space(2)
          Repeater {
            model: searchDropdown.hits
            delegate: Rectangle {
              width: parent.width; height: Style.space(28); radius: Style.cornerRadius
              color: hover ? exploreTab.panel.cardHoverBackground : "transparent"
              property bool hover: false
              HoverHandler { onHoveredChanged: parent.hover = hovered }
              Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left; anchors.leftMargin: Style.space(6)
                spacing: Style.space(6)
                Text {
                  textFormat: Text.PlainText
                  text: modelData.name
                  color: exploreTab.panel.foregroundColor
                  font.pixelSize: Style.font.bodySmall
                  font.bold: modelData.type === "city"
                }
                Text {
                  textFormat: Text.PlainText
                  text: modelData.type === "neighborhood" ? (modelData.cityName + " · " + modelData.count + " spots") : (modelData.type === "state" ? ("entire " + modelData.name + " state · " + modelData.count + " spots") : ("· " + modelData.count + " spots"))
                  color: exploreTab.panel.secondaryColor
                  font.pixelSize: Style.font.caption
                }
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (modelData.type === "neighborhood") {
                    exploreTab.panel.selectNeighborhood(modelData.key, modelData.cityKey)
                  } else if (modelData.type === "state") {
                    exploreTab.panel.selectState(modelData.key)
                  } else {
                    exploreTab.panel.selectCity(modelData.key)
                  }
                }
              }
            }
          }
        }
      }
    }

    CityHeader {
      panel: exploreTab.panel
      visible: exploreTab.panel.cityKey !== "" && exploreTab.panel.tab === "explore"
      count: exploreTab.panel.searchedSpots.length
      label: "spots"
      onBack: {
        exploreTab.panel.applyLocationScope("", "");
        exploreTab.panel.searchText = "";
      }
    }
    FilterPanel { panel: exploreTab.panel }
  }

  delegate: SpotCard {
    panel: exploreTab.panel
    scrollView: exploreTab
    spot: modelData
    cityKey: modelData._cityKey || exploreTab.panel.cityKey
    fallbackName: modelData.name
    journalEntry: exploreTab.panel.latestJournalFor(modelData.name)
    starsInteractive: true
    showCity: exploreTab.panel.isMultiCityView() && !!modelData._cityKey
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
        text: "Show " + Math.min(exploreTab.panel.pageSize, exploreTab.panel.searchedSpots.length - exploreTab.panel.visibleCount) + " more · " + (exploreTab.panel.searchedSpots.length - exploreTab.panel.visibleCount) + " remaining"
        color: exploreTab.panel.secondaryColor
        font.pixelSize: Style.font.bodySmall
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: exploreTab.panel.visibleCount += exploreTab.panel.pageSize
      }
    }
    Text {
      textFormat: Text.PlainText
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: exploreTab.panel.cityKey ? "No spots in " + exploreTab.panel.displayCity(exploreTab.panel.cityKey) + " match your filters" : "No spots match your filters"
      color: exploreTab.panel.secondaryColor
      font.pixelSize: Style.font.bodySmall
      visible: exploreTab.panel.searchedSpots.length === 0
      topPadding: Style.space(20)
    }
  }
}
