import QtQuick
import qs.Commons

// Neighborhood chip strip — shown once a city is selected.
Item {
  id: chips
  property Item panel
  // Chip strip only for short lists; the FilterBar's neighborhood dropdown
  // is the fallback when the list is too long (see showNeighborhoodChips).
  visible: panel.showNeighborhoodChips
  width: parent.width
  height: nbFlow.implicitHeight
  Flow {
    id: nbFlow
    width: parent.width
    spacing: Style.space(4)
    Repeater {
      model: chips.panel.neighborhoodOptions
      delegate: Rectangle {
        width: nbRowText.implicitWidth + Style.space(10)
        height: Style.space(24)
        radius: Style.cornerRadius
        color: chips.panel.neighborhood === modelData ? chips.panel.accentColor : "transparent"
        border.color: chips.panel.neighborhood === modelData ? chips.panel.accentColor : chips.panel.secondaryColor
        border.width: 1
        Text {
          textFormat: Text.PlainText
          id: nbRowText
          anchors.centerIn: parent
          text: modelData === "" ? "All" : modelData
          color: chips.panel.neighborhood === modelData ? chips.panel.accentTextColor : chips.panel.secondaryColor
          font.pixelSize: Style.font.caption
          font.bold: chips.panel.neighborhood === modelData
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: chips.panel.neighborhood = modelData
        }
      }
    }
  }
}
