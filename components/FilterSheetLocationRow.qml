import QtQuick
import qs.Commons

// One location-filter row + its option dropdown, instantiated four times by
// FilterSheet (city/state/country/neighborhood). Owns the shared
// clear-else-toggle decision once: clicking a row with a value set clears the
// whole location scope and closes the sheet, while clicking an empty row (or a
// row marked opensOnClick, like city) toggles its dropdown. Picking a dropdown
// option forwards the key via picked(key) and closes the sheet.
Column {
  id: locRow
  property Item panel
  property string label: ""
  property string value: ""
  property string placeholder: ""
  property string dropdownName: ""
  property var items: []
  // City always opens the option list on click; the others clear a set value.
  property bool opensOnClick: false
  // Extra gate on the dropdown's visibility, per caller: state/country hide the
  // dropdown while a value is set (a click would clear instead); city leaves it
  // true. Neighborhood gates the whole component's `visible` instead.
  property bool dropdownAllowed: true
  // Space from the sheet's top to the visible bottom edge, passed to the
  // dropdown so no option row runs past it.
  property real sheetSpaceRemaining: 0
  // Offset from the sheet's top to this row's top. Walks the full parent chain
  // from this row up to the FilterSheet root (identified as the ancestor that
  // owns `popupSpaceRemaining` — the only ancestor with that property), summing
  // each hop's reactive `y`, so the dropdown cap tracks when a preceding row
  // appears or disappears AND stays correct if a wrapper is ever inserted
  // around the rows. The same full-chain idiom FilterSheet.sheetTopInBoundary
  // uses, rather than a fixed one-hop sum that under-measures past a wrapper.
  readonly property real sheetTopOffset: {
    var top = 0;
    var item = locRow;
    while (item && item.popupSpaceRemaining === undefined) {
      top += item.y;
      item = item.parent;
    }
    return top;
  }
  signal picked(string key)

  width: parent.width
  // Match the sheet column's sibling spacing, so an open dropdown keeps the same
  // 2px gap from its row that it had before the row and dropdown were wrapped.
  spacing: Style.space(2)

  HoverRow {
    panel: locRow.panel
    onClicked: {
      if (!locRow.opensOnClick && locRow.value !== "") {
        // A set value clears the whole location scope (selectLocationScope
        // also resets openDropdown) and closes the sheet.
        locRow.panel.selectLocationScope("", "");
        locRow.panel.openSheet = false;
      } else {
        locRow.panel.toggleDropdown(locRow.dropdownName);
      }
    }
    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.leftMargin: Style.space(6)
      text: locRow.label
      color: locRow.panel.secondaryColor
      font.pixelSize: Style.font.bodySmall
    }
    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      text: locRow.value !== "" ? locRow.value : locRow.placeholder
      color: locRow.value !== "" ? locRow.panel.accentColor : locRow.panel.secondaryColor
      font.pixelSize: Style.font.caption
      font.bold: locRow.value !== ""
    }
  }

  FilterDropdown {
    panel: locRow.panel
    sheetSpaceRemaining: locRow.sheetSpaceRemaining
    sheetTopOffset: locRow.sheetTopOffset
    // dropdownAllowed is stricter than opensOnClick: it also hides the dropdown
    // while state/country hold a value (a click there clears, not opens).
    visible: locRow.panel.openDropdown === locRow.dropdownName && locRow.dropdownAllowed
    items: locRow.items
    // The "All X" clear row is the row's placeholder — one literal per row.
    clearLabel: locRow.placeholder
    onPicked: function(key) {
      locRow.picked(key);
      locRow.panel.openSheet = false;
    }
  }
}
