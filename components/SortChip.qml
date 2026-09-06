import QtQuick
import qs.Commons
import "../catalog-utils.js" as CatalogUtils

// Sort chip: the label cycles the sort key, the trailing arrow toggles
// direction. One control instead of a separate key chip + arrow chip.
Rectangle {
  id: sortChip
  property Item panel

  width: sortLabel.implicitWidth + sortArrow.implicitWidth + Style.space(12)
  height: Style.space(24)
  radius: Style.cornerRadius
  color: sortChip.panel.sortReversed ? sortChip.panel.accentTint : "transparent"
  border.color: sortChip.panel.sortReversed ? sortChip.panel.accentColor : sortChip.panel.secondaryColor
  border.width: 1
  Row {
    anchors.centerIn: parent
    spacing: Style.space(4)
    Text {
      textFormat: Text.PlainText
      id: sortLabel
      anchors.verticalCenter: parent.verticalCenter
      text: CatalogUtils.capitalizeFirst(sortChip.panel.sortBy)
      color: sortChip.panel.sortReversed ? sortChip.panel.accentColor : sortChip.panel.secondaryColor
      font.pixelSize: Style.font.caption
    }
    Text {
      textFormat: Text.PlainText
      id: sortArrow
      anchors.verticalCenter: parent.verticalCenter
      text: CatalogUtils.isSortDescending(sortChip.panel.sortBy, sortChip.panel.sortReversed) ? "\u2193" : "\u2191"
      color: sortChip.panel.sortReversed ? sortChip.panel.accentColor : sortChip.panel.secondaryColor
      font.pixelSize: Style.font.bodySmall
    }
  }
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      var idx = CatalogUtils.SORT_KEYS.indexOf(sortChip.panel.sortBy)
      if (idx < 0) idx = 0
      sortChip.panel.sortBy = CatalogUtils.SORT_KEYS[(idx + 1) % CatalogUtils.SORT_KEYS.length]
      sortChip.panel.openSheet = false
    }
  }
  // Arrow hit zone sits on top of the label zone; clickable overlays last.
  MouseArea {
    width: sortArrow.implicitWidth + Style.space(8)
    height: parent.height
    anchors.right: parent.right
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      sortChip.panel.sortReversed = !sortChip.panel.sortReversed
      sortChip.panel.openSheet = false
    }
  }
}
