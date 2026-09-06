import QtQuick
import qs.Commons
import "../catalog-utils.js" as CatalogUtils

// Spotlight view: full-panel single-spot view opened by Surprise Me. `panel` is
// the BarWidget root; `scrollView` is the outer Flickable the root passes in for
// image gating.
Column {
  id: spotlightView
  property Item panel
  property var scrollView
  // Mirrors SearchField.hasFocus so the panel's PanelKeyCatcher can `block`
  // key interception while the spotlight's search field is being typed into.
  readonly property bool searchFieldHasFocus: spotlightSearch.hasFocus

  // Criteria summary for the surprise pool — every filter that restricts which
  // spots are IN the draw, including the search query, but NOT the sort (the
  // sort orders the displayed list and cannot change pool membership). This
  // differs from BarWidget.filterDescription (the Explore summary), which
  // reports the sort and omits the query. Declarative so the binding engine
  // owns the recompute; the dependency list is explicit because reads inside
  // the compute function (cityLabel / surprisePoolCriteria) are not tracked.
  // cityLabelMap is listed because cityLabel() reads it directly.
  property string criteria: {
    spotlightView.panel.cityKey;
    spotlightView.panel.kindFilter;
    spotlightView.panel.unratedOnly;
    spotlightView.panel.radius;
    spotlightView.panel.neighborhood;
    spotlightView.panel.searchQuery;
    spotlightView.panel.cityLabelMap;
    return CatalogUtils.surprisePoolCriteria(
      spotlightView.panel.cityKey ? spotlightView.panel.cityLabel(spotlightView.panel.cityKey) : "",
      spotlightView.panel.kindFilter,
      spotlightView.panel.unratedOnly,
      spotlightView.panel.radius,
      spotlightView.panel.neighborhood,
      spotlightView.panel.searchQuery
    );
  }

  visible: panel.spotlight
  width: parent.width
  spacing: Style.space(10)
  padding: Style.space(16)

  // Tab chips
  TabChips {
    panel: spotlightView.panel
    currentTab: spotlightView.panel.tab
    onPicked: function(tab) { spotlightView.panel.openTab(tab) }
  }

  // Search bar
  SearchField {
    id: spotlightSearch
    panel: spotlightView.panel
    placeholder: spotlightView.panel.searchPlaceholder
    text: spotlightView.panel.searchText
    height: Style.space(40)
    onEdited: function(v) { spotlightView.panel.searchText = v }
    // No suggestions dropdown in the spotlight, so Escape closes the panel —
    // matching the Wishlist and Journal tabs.
    onDismissed: spotlightView.panel.close()
  }

  // Filters
  FilterPanel { panel: spotlightView.panel }

  // Back link + pick criteria + "Another surprise" shuffle chip
  Row {
    // Inset to the Column's content width (padding: Style.space(16) each side),
    // otherwise the rightmost chip overflows the clipped Flickable.
    width: parent.width - Style.space(32)
    spacing: Style.space(8)
    BackLink {
      id: spotlightBack
      panel: spotlightView.panel
      label: "Back"
      anchors.verticalCenter: parent.verticalCenter
      onClicked: { spotlightView.panel.spotlight = false; spotlightView.panel.expandedSpotName = null }
    }
    Text {
      textFormat: Text.PlainText
      // Bounded to the space left of the Back link and the "Another surprise"
      // chip (matching CityHeader) so `elide` actually fires and a long filter
      // summary elides instead of overflowing the clipped Flickable. The chip is
      // always rendered while the spotlight is active (disabled, not hidden, at
      // a one-spot pool), so its width is always subtracted.
      width: Math.max(0, parent.width - spotlightBack.width - parent.spacing
          - anotherChip.width - parent.spacing)
      text: "Surprise" + CatalogUtils.SEP + CatalogUtils.spotCountLabel(spotlightView.panel.surpriseCount) + " in " + spotlightView.criteria
      color: spotlightView.panel.secondaryColor
      font.pixelSize: Style.font.caption
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
    }
    // "Another surprise" — the shuffle control moved into the Back row (was a
    // full-width pill at the foot). Compact accent-tinted chip, always rendered
    // while the spotlight is active so the re-roll stays discoverable; disabled
    // (dimmed, non-clickable) when the pool holds a single spot, since the one
    // showing has no alternative. `enabled` cascades to the child MouseArea.
    // The chip lives in an untinted wrapper so its disabled 0.55 opacity does
    // not also dim the tooltip explaining why it is disabled.
    Item {
      width: anotherChip.width
      height: anotherChip.height
      anchors.verticalCenter: parent.verticalCenter
      Rectangle {
        id: anotherChip
        enabled: spotlightView.panel.surpriseCount > 1
        opacity: anotherChip.enabled ? 1.0 : 0.55
        anchors.verticalCenter: parent.verticalCenter
        width: anotherRow.implicitWidth + Style.space(16)
        height: Style.space(28)
        radius: Style.cornerRadius
        color: spotlightView.panel.accentTint
        border.color: spotlightView.panel.accentColor
        border.width: 1
        Row {
          id: anotherRow
          anchors.centerIn: parent
          spacing: Style.space(5)
          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: "\u21bb"
            color: spotlightView.panel.accentColor
            font.pixelSize: Style.font.caption
          }
          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: "Another surprise"
            color: spotlightView.panel.accentColor
            font.bold: true
            font.pixelSize: Style.font.caption
          }
        }
        HoverHandler { id: anotherHover }
        MouseArea {
          anchors.fill: parent
          cursorShape: anotherChip.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: spotlightView.panel.surpriseMe()
        }
      }
      Tooltip {
        visible: anotherHover.hovered && !anotherChip.enabled
        anchors.bottom: anotherChip.top
        anchors.bottomMargin: Style.space(4)
        anchors.horizontalCenter: anotherChip.horizontalCenter
        panel: spotlightView.panel
        text: "Only one spot matches your filters"
      }
    }
  }

  // Spot card — centered within the full-width column. A Column is a
  // positioner that manages only Y, so a fixed-width child cannot be
  // horizontally centered directly; a full-width wrapper Item (a plain
  // Item, not a positioner) is required for anchors to take effect.
  Item {
    width: parent.width - Style.space(32)
    height: spotlightCard.height

    SpotCard {
      id: spotlightCard
      panel: spotlightView.panel
      scrollView: spotlightView.scrollView
      width: Math.min(parent.width, Style.space(450))
      anchors.horizontalCenter: parent.horizontalCenter
      spot: spotlightView.panel.spotlightEntry
      cityKey: spotlightView.panel.spotlightEntry ? (spotlightView.panel.spotlightEntry._cityKey || "") : ""
      fallbackName: spotlightView.panel.spotlightEntry ? spotlightView.panel.spotlightEntry.name : ""
      journalEntry: spotlightView.panel.spotlightEntry ? spotlightView.panel.latestJournalFor(spotlightView.panel.spotlightEntry.name) : null
      starsInteractive: true
      showCity: spotlightView.panel.showsCityLabels() && !!(spotlightView.panel.spotlightEntry && spotlightView.panel.spotlightEntry._cityKey)
      useHoverBg: false
      zebraStripe: 0
    }
  }
}
