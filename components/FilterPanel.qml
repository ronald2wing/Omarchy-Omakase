import QtQuick
import qs.Commons

// Filter stack shared by every tab and the spotlight view. Reads panel.* filter
// state directly. The primary row (FilterBar) is always visible; the
// rarely-used location scopes live in the floating FilterSheet, opened by the
// Filters button. The Journal tab and Explore's pinned header instance both
// omit the neighborhood chip strip, so `showNeighborhoodChips` gates it.
//
// The sheet floats below the primary row instead of sitting in the layout
// column. A sheet that grew the column would change the Explore ListView
// header's height, and the ListView compensates by shifting the header item up
// to keep the first delegate stable — dragging the primary row with it. The
// floating sheet leaves the header height untouched, so the row stays fixed;
// `z` lifts it above the content that follows.
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
  // cards show through the floating sheet. Lift the header above them.
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

  // Anchored under the primary row, right-aligned so it hangs off the Filters
  // button at the end of the row. z: 2 keeps it above the neighborhood chips
  // and any sibling content.
  FilterSheet {
    panel: filterPanel.panel
    z: 2
    anchors.right: parent.right
    y: filterBar.height + fixedColumn.spacing
    shown: filterPanel.panel.openSheet
    onClosed: filterPanel.panel.openSheet = false
  }
}
