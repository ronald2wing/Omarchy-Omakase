import QtQuick
import qs.Commons

// City/state/country/neighborhood filter stack shared by every tab and the
// spotlight view. Reads panel.* filter state directly. The Journal tab omits
// the neighborhood chip strip, so `showNeighborhoodChips` gates it.
//
// The dropdowns float below the pill row instead of sitting in the layout
// column. A dropdown that grew the column would change the Explore ListView
// header's height, and the ListView compensates by shifting the header item
// up to keep the first delegate stable — dragging the pill row with it. The
// floating dropdown leaves the header height untouched, so the pill row stays
// fixed; `z` lifts it above the content that follows.
Item {
  id: filterPanel
  property Item panel
  property bool showNeighborhoodChips: true
  width: parent.width
  height: fixedColumn.implicitHeight
  z: 1

  // Qt Quick's ListView gives delegates, the header, and the footer a default
  // z of 1. A header left at z: 1 therefore ties with the delegates, and the
  // delegates — inserted after the header — paint on top, letting the spot
  // cards show through the floating dropdown. Lift the header above them.
  // Harmless when the parent is a plain Column (the other tabs): only one tab
  // is visible at a time, so the extra z never reorders anything on screen.
  Component.onCompleted: if (parent) parent.z = Math.max(parent.z, 2)

  Column {
    id: fixedColumn
    width: parent.width
    spacing: Style.space(10)

    FilterBar {
      id: filterBar
      panel: filterPanel.panel
    }

    NeighborhoodChips {
      panel: filterPanel.panel
      visible: filterPanel.showNeighborhoodChips && filterPanel.panel.showNeighborhoodChips
    }
  }

  FilterDropdown {
    panel: filterPanel.panel
    y: filterBar.height + fixedColumn.spacing
    shown: filterPanel.panel.openDropdown === "city"
    items: filterPanel.panel.cityFilterItemsData
    clearLabel: "All cities"
    onPicked: function(key) { filterPanel.panel.selectCity(key) }
  }
  FilterDropdown {
    panel: filterPanel.panel
    y: filterBar.height + fixedColumn.spacing
    shown: filterPanel.panel.openDropdown === "state" && filterPanel.panel.stateFilter === ""
    items: filterPanel.panel.stateFilterItemsData
    clearLabel: "All states"
    onPicked: function(key) { filterPanel.panel.selectState(key) }
  }
  FilterDropdown {
    panel: filterPanel.panel
    y: filterBar.height + fixedColumn.spacing
    shown: filterPanel.panel.openDropdown === "country" && filterPanel.panel.countryFilter === ""
    items: filterPanel.panel.countryFilterItemsData
    clearLabel: "All countries"
    onPicked: function(key) { filterPanel.panel.selectCountry(key) }
  }
  FilterDropdown {
    panel: filterPanel.panel
    y: filterBar.height + fixedColumn.spacing
    shown: filterPanel.panel.openDropdown === "neighborhood" && filterPanel.panel.cityKey !== ""
    items: filterPanel.panel.neighborhoodFilterItemsData
    onPicked: function(key) { filterPanel.panel.selectNeighborhood(key, filterPanel.panel.cityKey) }
  }
}
