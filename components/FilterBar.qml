import QtQuick
import qs.Commons

// Filter chip row: kind segment, visited toggle, sort chip, and the
// location-scope pills. Reads panel.* filter state directly; the neighborhood
// row stays per-tab.
Item {
  id: filterBar
  property Item panel
  width: parent.width
  height: filterFlow.implicitHeight
  Flow {
    id: filterFlow
    anchors.left: parent.left
    anchors.right: clearButton.left
    anchors.rightMargin: Style.space(4)
    spacing: Style.space(3)

    Rectangle {
      radius: Style.cornerRadius
      color: "transparent"
      border.color: filterBar.panel.accentColor
      border.width: 1
      width: segGroupFlow.implicitWidth
      height: segGroupFlow.implicitHeight
      Flow {
        id: segGroupFlow
        spacing: 0
        Rectangle {
          width: allSegmentText.implicitWidth + Style.space(8)
          height: Style.space(24)
          color: filterBar.panel.kindFilter === "all" ? filterBar.panel.accentColor : "transparent"
          Text {
            textFormat: Text.PlainText
            id: allSegmentText
            anchors.centerIn: parent
            text: "All"
            color: filterBar.panel.kindFilter === "all" ? filterBar.panel.accentTextColor : filterBar.panel.secondaryColor
            font.pixelSize: Style.font.caption
            font.bold: filterBar.panel.kindFilter === "all"
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: filterBar.panel.kindFilter = "all"
          }
        }
        Rectangle { width: 1; height: Style.space(24); color: filterBar.panel.accentColor }
        Rectangle {
          width: omakaseSegmentText.implicitWidth + Style.space(8)
          height: Style.space(24)
          color: filterBar.panel.kindFilter === "omakase" ? filterBar.panel.accentColor : "transparent"
          Text {
            textFormat: Text.PlainText
            id: omakaseSegmentText
            anchors.centerIn: parent
            text: "Omakase"
            color: filterBar.panel.kindFilter === "omakase" ? filterBar.panel.accentTextColor : filterBar.panel.secondaryColor
            font.pixelSize: Style.font.caption
            font.bold: filterBar.panel.kindFilter === "omakase"
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: filterBar.panel.kindFilter = "omakase"
          }
        }
        Rectangle { width: 1; height: Style.space(24); color: filterBar.panel.accentColor }
        Rectangle {
          width: discountSegmentText.implicitWidth + Style.space(8)
          height: Style.space(24)
          color: filterBar.panel.kindFilter === "discount" ? filterBar.panel.accentColor : "transparent"
          Text {
            textFormat: Text.PlainText
            id: discountSegmentText
            anchors.centerIn: parent
            text: "Discount"
            color: filterBar.panel.kindFilter === "discount" ? filterBar.panel.accentTextColor : filterBar.panel.secondaryColor
            font.pixelSize: Style.font.caption
            font.bold: filterBar.panel.kindFilter === "discount"
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: filterBar.panel.kindFilter = "discount"
          }
        }
      }
    }

    // Hairline separating the type segment from the toggles/sort group.
    Rectangle {
      width: 1
      height: Style.space(16)
      color: filterBar.panel.foregroundAlpha(0.2)
    }

    PillButton {
      panel: filterBar.panel
      cornerRadius: Style.cornerRadius
      padding: Style.space(8)
      fontSize: Style.font.caption
      label: filterBar.panel.tab === "journal" ? "Visited" : "Unvisited"
      active: filterBar.panel.unvisited || filterBar.panel.tab === "journal"
      enabled: filterBar.panel.tab !== "journal"
      onToggled: filterBar.panel.unvisited = !filterBar.panel.unvisited
    }

    // Sort chip: label cycles the sort key, the trailing arrow toggles
    // direction. One control instead of a separate key chip + arrow chip.
    Rectangle {
      width: sortLabel.implicitWidth + sortArrow.implicitWidth + Style.space(12)
      height: Style.space(24)
      radius: Style.cornerRadius
      color: filterBar.panel.sortReversed ? filterBar.panel.accentTint : "transparent"
      border.color: filterBar.panel.sortReversed ? filterBar.panel.accentColor : filterBar.panel.secondaryColor
      border.width: 1
      Row {
        anchors.centerIn: parent
        spacing: Style.space(4)
        Text {
          textFormat: Text.PlainText
          id: sortLabel
          anchors.verticalCenter: parent.verticalCenter
          readonly property var sortKeys: ["distance","rating","price","date"]
          readonly property var sortLabels: ["Distance","Rating","Price","Date"]
          text: {
            var idx = sortKeys.indexOf(filterBar.panel.sortBy)
            return sortLabels[idx < 0 ? 0 : idx]
          }
          color: filterBar.panel.sortReversed ? filterBar.panel.accentColor : filterBar.panel.secondaryColor
          font.pixelSize: Style.font.caption
          font.bold: true
        }
        Text {
          textFormat: Text.PlainText
          id: sortArrow
          anchors.verticalCenter: parent.verticalCenter
          text: filterBar.panel.sortReversed ? "\u2193" : "\u2191"
          color: filterBar.panel.sortReversed ? filterBar.panel.accentColor : filterBar.panel.secondaryColor
          font.pixelSize: Style.font.bodySmall
        }
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          var idx = sortLabel.sortKeys.indexOf(filterBar.panel.sortBy)
          if (idx < 0) idx = 0
          filterBar.panel.sortBy = sortLabel.sortKeys[(idx + 1) % sortLabel.sortKeys.length]
        }
      }
      // Arrow hit zone sits on top of the label zone; clickable overlays last.
      MouseArea {
        width: sortArrow.implicitWidth + Style.space(8)
        height: parent.height
        anchors.right: parent.right
        cursorShape: Qt.PointingHandCursor
        onClicked: filterBar.panel.sortReversed = !filterBar.panel.sortReversed
      }
    }

    // Nearby radius cycle (off -> 5 -> 10 -> 20 km).
    PillButton {
      panel: filterBar.panel
      cornerRadius: Style.cornerRadius
      padding: Style.space(8)
      fontSize: Style.font.caption
      label: filterBar.panel.radius > 0 ? (filterBar.panel.radius + " km") : "Nearby"
      active: filterBar.panel.radius > 0
      onToggled: {
        if (filterBar.panel.radius === 0) filterBar.panel.radius = 5
        else if (filterBar.panel.radius === 5) filterBar.panel.radius = 10
        else if (filterBar.panel.radius === 10) filterBar.panel.radius = 20
        else filterBar.panel.radius = 0
        // Radius is authoritative: clear the other location scopes but keep the
        // radius we just set (applyLocationScope would zero it).
        if (filterBar.panel.radius > 0) filterBar.panel.clearLocationScopes()
      }
    }

    PillButton {
      panel: filterBar.panel
      cornerRadius: Style.cornerRadius
      padding: Style.space(8)
      fontSize: Style.font.caption
      label: filterBar.panel.cityKey !== "" ? filterBar.panel.displayCity(filterBar.panel.cityKey) : "City"
      active: filterBar.panel.cityKey !== ""
      // Always open the dropdown; clearing is the "All cities" row inside it.
      onToggled: filterBar.panel.toggleDropdown("city")
    }

    // State filter button (Yelp state, e.g. "NY"). Selecting a state clears
    // the other location scopes so the whole directory filters by state.
    PillButton {
      panel: filterBar.panel
      cornerRadius: Style.cornerRadius
      padding: Style.space(8)
      fontSize: Style.font.caption
      label: filterBar.panel.stateFilter !== "" ? filterBar.panel.stateFilter : "State"
      active: filterBar.panel.stateFilter !== ""
      onToggled: {
        if (filterBar.panel.stateFilter !== "") {
          filterBar.panel.applyLocationScope("", "")
        } else {
          filterBar.panel.toggleDropdown("state")
        }
      }
    }

    // Country filter button. Selecting a country clears city/state/neighborhood.
    PillButton {
      panel: filterBar.panel
      cornerRadius: Style.cornerRadius
      padding: Style.space(8)
      fontSize: Style.font.caption
      label: filterBar.panel.countryFilter !== "" ? filterBar.panel.countryFilter : "Country"
      active: filterBar.panel.countryFilter !== ""
      onToggled: {
        if (filterBar.panel.countryFilter !== "") {
          filterBar.panel.applyLocationScope("", "")
        } else {
          filterBar.panel.toggleDropdown("country")
        }
      }
    }

    // Neighborhood filter button — only when a city is selected.
    PillButton {
      panel: filterBar.panel
      cornerRadius: Style.cornerRadius
      padding: Style.space(8)
      fontSize: Style.font.caption
      visible: filterBar.panel.cityKey !== ""
      label: filterBar.panel.neighborhood !== "" ? filterBar.panel.neighborhood : "Neighborhood"
      active: filterBar.panel.neighborhood !== ""
      onToggled: {
        if (filterBar.panel.neighborhood !== "") {
          filterBar.panel.applyLocationScope("", "")
        } else {
          filterBar.panel.toggleDropdown("neighborhood")
        }
      }
    }
  }

  // Clear-filters ✕ pinned to the top-right of the filter bar.
  Rectangle {
    id: clearButton
    width: Style.space(22); height: Style.space(22)
    radius: Style.space(11)
    anchors.top: parent.top
    anchors.right: parent.right
    color: filterBar.panel.dangerFaint
    border.color: filterBar.panel.dangerBorder
    border.width: 1
    visible: {
      var dirty = filterBar.panel.kindFilter !== "all" || filterBar.panel.sortBy !== "distance";
      dirty = dirty || filterBar.panel.sortReversed || filterBar.panel.unvisited || !!filterBar.panel.cityKey;
      return dirty || filterBar.panel.radius > 0 || !!filterBar.panel.neighborhood || !!filterBar.panel.stateFilter || !!filterBar.panel.countryFilter;
    }
    Text {
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: "\u2715"
      color: filterBar.panel.dangerColor
      font.pixelSize: Style.font.caption
      font.bold: true
    }
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: filterBar.panel.resetFilters()
    }
  }
}
