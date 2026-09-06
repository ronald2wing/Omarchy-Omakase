import QtQuick
import qs.Commons

// Spotlight view: full-panel single-spot view opened by Surprise Me. `panel` is
// the BarWidget root; `scrollView` is the outer Flickable the root passes in for
// image gating.
Column {
  id: spotlightView
  property Item panel
  property var scrollView

  visible: panel.spotlight
  width: parent.width
  spacing: Style.space(10)
  padding: Style.space(16)

  // Tab chips
  TabChips {
    panel: spotlightView.panel
    currentTab: spotlightView.panel.tab
    onPicked: function(tab) { spotlightView.panel.spotlight = false; spotlightView.panel.tab = tab; spotlightView.panel.collapseRow(); }
  }

  // Search bar
  SearchField {
    id: spotlightInput
    panel: spotlightView.panel
    placeholder: spotlightView.panel.searchPlaceholder
    text: spotlightView.panel.searchText
    height: Style.space(40)
    onEdited: function(v) { spotlightView.panel.searchText = v }
  }

  // Filters
  FilterPanel { panel: spotlightView.panel }

  // Back link + pick criteria
  Row {
    width: parent.width
    spacing: Style.space(8)
    BackLink {
      panel: spotlightView.panel
      label: "Back"
      onClicked: { spotlightView.panel.spotlight = false; spotlightView.panel.expandedSpotName = null }
    }
    Text {
      textFormat: Text.PlainText
      text: spotlightView.panel.searchedSpots.length + " spots in " + spotlightView.panel.filterDescriptionData
      color: spotlightView.panel.secondaryColor
      font.pixelSize: Style.font.caption
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
    }
  }

  // Spot card — centered within the full-width column. A Column is a
  // positioner that manages only Y, so a fixed-width child cannot be
  // horizontally centered directly; a full-width wrapper Item (a plain
  // Item, not a positioner) is required for anchors to take effect.
  Item {
    id: spotlightCardWrap
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
      showCity: spotlightView.panel.isMultiCityView() && !!(spotlightView.panel.spotlightEntry && spotlightView.panel.spotlightEntry._cityKey)
      useHoverBg: false
      zebraStripe: 0
    }
  }

  // Try Another — same width + centering as the card, so the whole
  // spotlight form is one aligned 450px block.
  Item {
    width: parent.width - Style.space(32)
    height: tryAnotherBtn.height
    Rectangle {
      id: tryAnotherBtn
      width: Math.min(parent.width, Style.space(450))
      anchors.horizontalCenter: parent.horizontalCenter
      height: Style.space(44)
      radius: Style.space(22)
      color: spotlightView.panel.accentColor
      Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: "Try Another"
        color: spotlightView.panel.accentTextColor
        font.bold: true
        font.pixelSize: Style.font.bodySmall
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: spotlightView.panel.surpriseMe()
      }
    }
  }
}
