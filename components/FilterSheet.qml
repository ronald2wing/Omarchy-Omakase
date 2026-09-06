import QtQuick
import qs.Commons

// Floating filter sheet anchored under the Filters button. Holds the rarely-used
// location scopes (city/state/country/neighborhood) plus a Clear all action. The
// Nearby radius cycle lives in the primary FilterBar row. Floats like
// FilterDropdown so it never changes the
// ListView header height (see FilterPanel) — the header stays fixed and the
// sheet paints over the cards below it.
//
// Each location row toggles the shared `panel.openDropdown`; the matching
// FilterDropdown renders directly beneath its row, inside the sheet, so the
// option list grows the floating surface instead of the layout column.
Rectangle {
  id: sheet
  property Item panel
  property bool shown: false
  signal closed()

  visible: shown
  width: Style.space(260)
  height: sheetCol.implicitHeight + Style.space(16)
  radius: Style.cornerRadius
  // Opaque popup surface, shared via panel.popupBackground.
  color: panel.popupBackground
  border.color: Color.popups.border
  border.width: Style.normalBorderWidth

  // Close the sheet and any open option list. Picking a location routes through
  // the panel's select* helpers, which already clear openDropdown; this also
  // collapses the sheet so the summary line is immediately visible.
  function close() {
    sheet.panel.openDropdown = "";
    sheet.closed();
  }

  // The popup card is the topmost item in the sheet's parent chain (its parent
  // is the window's content item). `panel` is the bar-widget root, whose height
  // is the bar icon — not the popup — so the card is the only ancestor that
  // carries the popup's real height.
  readonly property Item popupCard: {
    var item = sheet;
    while (item.parent && item.parent.parent) item = item.parent;
    return item;
  }
  // The sheet's top relative to the popup card, summed from the reactive `y` of
  // each ancestor. mapToItem is not a tracked dependency, so a binding built on
  // it would go stale when the FilterBar's height changes (the active-filter
  // summary line appearing or disappearing).
  readonly property real sheetTopInCard: {
    var top = 0;
    var item = sheet;
    while (item && item !== sheet.popupCard) {
      top += item.y;
      item = item.parent;
    }
    return top;
  }
  // Vertical space between the sheet's top and the popup's bottom edge, minus a
  // small margin. Each FilterDropdown caps its option list to this minus its own
  // offset within the sheet, so no option row can run past the popup edge.
  readonly property real availableHeight: sheet.popupCard
    ? Math.max(Style.space(120), sheet.popupCard.height - sheet.sheetTopInCard - Style.space(8))
    : 0

  Column {
    id: sheetCol
    anchors.left: parent.left; anchors.leftMargin: Style.space(8)
    anchors.right: parent.right; anchors.rightMargin: Style.space(8)
    anchors.top: parent.top; anchors.topMargin: Style.space(8)
    spacing: Style.space(2)

    // City — always opens the option list; clearing is the "All cities" row.
    FilterSheetRow {
      panel: sheet.panel
      label: "City"
      value: sheet.panel.cityLabel(sheet.panel.cityKey)
      placeholder: "Any city"
      active: sheet.panel.cityKey !== ""
      onClicked: sheet.panel.toggleDropdown("city")
    }
    FilterDropdown {
      panel: sheet.panel
      maxHeight: sheet.availableHeight
      shown: sheet.panel.openDropdown === "city"
      items: sheet.panel.cityFilterItems
      clearLabel: "All cities"
      onPicked: function(key) { sheet.panel.selectCity(key); sheet.close() }
    }

    // State — a selected state clears on click; an empty state opens the option
    // list.
    FilterSheetRow {
      panel: sheet.panel
      label: "State"
      value: sheet.panel.stateFilter
      placeholder: "Any state"
      active: sheet.panel.stateFilter !== ""
      onClicked: {
        if (sheet.panel.stateFilter !== "") {
          sheet.panel.applyLocationScope("", "");
          sheet.close();
        } else {
          sheet.panel.toggleDropdown("state");
        }
      }
    }
    FilterDropdown {
      panel: sheet.panel
      maxHeight: sheet.availableHeight
      shown: sheet.panel.openDropdown === "state" && sheet.panel.stateFilter === ""
      items: sheet.panel.stateFilterItems
      clearLabel: "All states"
      onPicked: function(key) { sheet.panel.selectState(key); sheet.close() }
    }

    // Country — same clear-on-click behavior as State.
    FilterSheetRow {
      panel: sheet.panel
      label: "Country"
      value: sheet.panel.countryFilter
      placeholder: "Any country"
      active: sheet.panel.countryFilter !== ""
      onClicked: {
        if (sheet.panel.countryFilter !== "") {
          sheet.panel.applyLocationScope("", "");
          sheet.close();
        } else {
          sheet.panel.toggleDropdown("country");
        }
      }
    }
    FilterDropdown {
      panel: sheet.panel
      maxHeight: sheet.availableHeight
      shown: sheet.panel.openDropdown === "country" && sheet.panel.countryFilter === ""
      items: sheet.panel.countryFilterItems
      clearLabel: "All countries"
      onPicked: function(key) { sheet.panel.selectCountry(key); sheet.close() }
    }

    // Neighborhood — only when the selected city has neighborhoods worth
    // filtering by.
    FilterSheetRow {
      visible: sheet.panel.hasNeighborhoods
      panel: sheet.panel
      label: "Neighborhood"
      value: sheet.panel.neighborhood
      placeholder: "Any neighborhood"
      active: sheet.panel.neighborhood !== ""
      onClicked: {
        if (sheet.panel.neighborhood !== "") {
          sheet.panel.applyLocationScope("", "");
          sheet.close();
        } else {
          sheet.panel.toggleDropdown("neighborhood");
        }
      }
    }
    FilterDropdown {
      panel: sheet.panel
      maxHeight: sheet.availableHeight
      shown: sheet.panel.openDropdown === "neighborhood" && sheet.panel.hasNeighborhoods
      items: sheet.panel.neighborhoodFilterItems
      clearLabel: "All neighborhoods"
      onPicked: function(key) { sheet.panel.selectNeighborhood(key, sheet.panel.cityKey); sheet.close() }
    }

    // Hairline separating the location scopes from the Clear all action.
    Rectangle {
      width: parent.width
      height: 1
      color: sheet.panel.foregroundAlpha(0.15)
    }

    // Clear all — resets every Explore filter and collapses the sheet.
    Rectangle {
      width: parent.width; height: Style.space(28); radius: Style.cornerRadius
      color: clearHover ? sheet.panel.dangerFaint : "transparent"
      property bool clearHover: false
      HoverHandler { onHoveredChanged: parent.clearHover = hovered }
      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left; anchors.leftMargin: Style.space(6)
        text: "Clear all"
        color: sheet.panel.dangerColor
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          sheet.panel.resetFilters();
          sheet.close();
        }
      }
    }
  }
}
