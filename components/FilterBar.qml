import QtQuick
import qs.Commons
import "../catalog-utils.js" as CatalogUtils

// Primary filter row: kind segment, sort control, Unrated toggle, the Nearby
// radius cycle, and the Filters button that opens the location sheet. The
// rarely-used location scopes live in FilterSheet; the active ones surface here
// as a wrapped line of clickable tokens that remove their filter. Reads panel.*
// filter state directly; the neighborhood chip strip stays per-tab.
Item {
  id: filterBar
  property Item panel
  width: parent.width
  height: barColumn.implicitHeight

  Column {
    id: barColumn
    width: parent.width
    spacing: Style.space(6)

    Flow {
      width: parent.width
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
          Repeater {
            model: [
              { key: "all", label: "All" },
              { key: "omakase", label: "Omakase" },
              { key: "discount", label: "Discount" }
            ]
            delegate: Row {
              spacing: 0
              // Hairline between segments; the first has no leading divider.
              Rectangle {
                width: 1
                height: Style.space(24)
                color: filterBar.panel.accentColor
                visible: index > 0
              }
              Rectangle {
                width: segmentText.implicitWidth + Style.space(8)
                height: Style.space(24)
                color: filterBar.panel.kindFilter === modelData.key ? filterBar.panel.accentColor : "transparent"
                Text {
                  textFormat: Text.PlainText
                  id: segmentText
                  anchors.centerIn: parent
                  text: modelData.label
                  color: filterBar.panel.kindFilter === modelData.key ? filterBar.panel.accentTextColor : filterBar.panel.secondaryColor
                  font.pixelSize: Style.font.caption
                  font.bold: filterBar.panel.kindFilter === modelData.key
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: filterBar.panel.kindFilter = modelData.key
                }
              }
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
        // The Journal tab already lists only rated spots, so the toggle is
        // meaningless there — hide it rather than show a contradictory label.
        visible: filterBar.panel.tab !== "journal"
        label: "Unrated"
        active: filterBar.panel.unratedOnly
        onToggled: filterBar.panel.unratedOnly = !filterBar.panel.unratedOnly
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
            text: CatalogUtils.sortLabelFor(filterBar.panel.sortBy)
            color: filterBar.panel.sortReversed ? filterBar.panel.accentColor : filterBar.panel.secondaryColor
            font.pixelSize: Style.font.caption
          }
          Text {
            textFormat: Text.PlainText
            id: sortArrow
            anchors.verticalCenter: parent.verticalCenter
            text: CatalogUtils.sortDescending(filterBar.panel.sortBy, filterBar.panel.sortReversed) ? "\u2193" : "\u2191"
            color: filterBar.panel.sortReversed ? filterBar.panel.accentColor : filterBar.panel.secondaryColor
            font.pixelSize: Style.font.bodySmall
          }
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            var idx = CatalogUtils.SORT_KEYS.indexOf(filterBar.panel.sortBy)
            if (idx < 0) idx = 0
            filterBar.panel.sortBy = CatalogUtils.SORT_KEYS[(idx + 1) % CatalogUtils.SORT_KEYS.length]
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

      // Nearby radius cycle (off -> 5 -> 10 -> 20 km). Lives in the primary row
      // so the radius is always reachable; the label carries the current value
      // and the pill fills when a radius is set. Radius is authoritative: setting
      // one clears the other location scopes but keeps the radius just set.
      PillButton {
        panel: filterBar.panel
        cornerRadius: Style.cornerRadius
        padding: Style.space(8)
        fontSize: Style.font.caption
        label: filterBar.panel.radius > 0 ? CatalogUtils.formatRadius(filterBar.panel.radius) : "Nearby"
        active: filterBar.panel.radius > 0
        onToggled: {
          filterBar.panel.radius = CatalogUtils.nextRadiusStep(filterBar.panel.radius);
          if (filterBar.panel.radius > 0) filterBar.panel.clearLocationScopes();
        }
      }

      // Filters button — opens the location sheet. Active when any sheet filter
      // is set, so the primary row still signals hidden state.
      PillButton {
        panel: filterBar.panel
        cornerRadius: Style.cornerRadius
        padding: Style.space(8)
        fontSize: Style.font.caption
        label: "Filters \u25be"
        active: filterBar.panel.hasSheetFilters
        onToggled: filterBar.panel.openSheet = !filterBar.panel.openSheet
      }
    }

    // Active-filters summary: one wrapped line of clickable tokens, each
    // removing its own filter, plus a Clear action. Hidden when nothing is set.
    Flow {
      width: parent.width
      spacing: Style.space(4)
      visible: filterBar.panel.hasActiveFilters || filterBar.panel.kindFilter !== "all" || filterBar.panel.unratedOnly

      // City token — clears every location scope (neighborhood rides on city).
      FilterToken {
        visible: filterBar.panel.cityKey !== ""
        panel: filterBar.panel
        text: filterBar.panel.cityLabel(filterBar.panel.cityKey)
        onCleared: filterBar.panel.applyLocationScope("", "")
      }

      FilterToken {
        visible: filterBar.panel.stateFilter !== ""
        panel: filterBar.panel
        text: filterBar.panel.stateFilter
        onCleared: filterBar.panel.applyLocationScope("", "")
      }

      FilterToken {
        visible: filterBar.panel.countryFilter !== ""
        panel: filterBar.panel
        text: filterBar.panel.countryFilter
        onCleared: filterBar.panel.applyLocationScope("", "")
      }

      FilterToken {
        visible: filterBar.panel.neighborhood !== ""
        panel: filterBar.panel
        text: filterBar.panel.neighborhood
        onCleared: filterBar.panel.applyLocationScope("", "")
      }

      FilterToken {
        visible: filterBar.panel.kindFilter !== "all"
        panel: filterBar.panel
        text: CatalogUtils.capitalize(filterBar.panel.kindFilter)
        onCleared: filterBar.panel.kindFilter = "all"
      }

      FilterToken {
        visible: filterBar.panel.radius > 0
        panel: filterBar.panel
        text: CatalogUtils.formatRadius(filterBar.panel.radius)
        onCleared: filterBar.panel.radius = 0
      }

      FilterToken {
        visible: filterBar.panel.unratedOnly
        panel: filterBar.panel
        text: "Unrated"
        onCleared: filterBar.panel.unratedOnly = false
      }

      // Clear — resets every filter (kind, sort, unratedOnly, location, radius).
      Rectangle {
        width: clearTokenText.implicitWidth + Style.space(10)
        height: Style.space(20)
        radius: Style.space(10)
        color: "transparent"
        border.color: filterBar.panel.dangerBorder
        border.width: 1
        Text {
          textFormat: Text.PlainText
          id: clearTokenText
          anchors.centerIn: parent
          text: "Clear all"
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
  }
}
