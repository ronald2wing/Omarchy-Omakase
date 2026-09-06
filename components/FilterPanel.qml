import QtQuick
import qs.Commons

// Filter stack shared by every tab and the spotlight view. Reads panel.* filter
// state directly. The primary row (FilterBar) is always visible; the
// rarely-used location scopes live in the floating FilterSheet, opened by the
// Filters button. The Journal tab and Explore's pinned header instance both
// omit the neighborhood chip strip, so `allowNeighborhoodChips` gates it.
//
// The sheet floats below the primary row instead of sitting in the layout
// column: a sheet that grew the column would grow pinnedColumn /
// pinnedHeaderHeight and push the card list down. Floating leaves the pinned
// header height untouched, so the primary row stays fixed; `z` lifts the sheet
// above the content that follows.
Item {
  id: filterPanel
  property Item panel
  property bool allowNeighborhoodChips: true
  width: parent.width
  height: fixedColumn.implicitHeight
  // The list's delegates carry a default z of 1, so this panel must sit above
  // them (self-z) and above its own siblings in the pinned column (the parent
  // lift below).
  z: 2

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
      visible: filterPanel.allowNeighborhoodChips && filterPanel.panel.neighborhoodChipsVisible
    }
  }

  // Anchored to the Filters chip that opens it: a small popover offset below
  // the chip's bottom edge, right edges aligned so the wide sheet extends left
  // from the trigger instead of overhanging it. The chip's geometry is exposed
  // by FilterBar (filtersChipRight/filtersChipBottom) in FilterBar coordinates;
  // adding filterBar.y maps it into this panel's coordinates. z: 2 keeps it
  // above the neighborhood chips and any sibling content.
  //
  // The right-edge alignment is expressed as an explicit x rather than
  // anchors.right + rightMargin because the chip wraps: when the Flow pushes
  // "Location" onto a second line at the left, filtersChipRight is small
  // and a right-aligned 260px sheet would span a negative x, overflowing the
  // panel's left edge and clipping its left-anchored labels. Clamping x to the
  // panel margin keeps the sheet on-screen; when the chip is at the far right
  // the clamp is inactive and the right edge still lands exactly on the chip.
  FilterSheet {
    panel: filterPanel.panel
    z: 2
    x: Math.max(Style.space(8), filterBar.x + filterBar.filtersChipRight - width)
    y: filterBar.y + filterBar.filtersChipBottom + Style.space(4)
    visible: filterPanel.panel.openSheet
  }
}
