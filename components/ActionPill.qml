import QtQuick
import qs.Commons

// Action pill in the expanded card (Yelp / Website / Maps / Call). Identical
// visuals: accent-tinted rounded rect with a leading icon (nerd-font glyph or
// svg) and a bold label. `activated` carries the pill's click side effect.
Rectangle {
  id: pill
  property Item panel
  property string icon: ""        // nerd-font glyph; empty = no glyph
  property string iconSource: ""  // svg path; empty = no image
  property string label: ""
  signal activated()

  width: Style.space(84)
  height: Style.space(28)
  radius: Style.cornerRadius
  color: panel.accentTint
  border.color: panel.accentColor
  border.width: 1

  Row {
    anchors.centerIn: parent
    spacing: Style.space(5)
    Image {
      visible: pill.iconSource !== ""
      source: pill.iconSource !== "" ? Qt.resolvedUrl(pill.iconSource) : ""
      width: 14; height: 14
      anchors.verticalCenter: parent.verticalCenter
    }
    Text {
      textFormat: Text.PlainText
      visible: pill.icon !== ""
      text: pill.icon
      color: panel.accentColor
      font.pixelSize: Style.font.caption
      anchors.verticalCenter: parent.verticalCenter
    }
    Text {
      textFormat: Text.PlainText
      text: pill.label
      color: panel.accentColor
      font.bold: true
      font.pixelSize: Style.font.caption
      anchors.verticalCenter: parent.verticalCenter
    }
  }
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: pill.activated()
  }
}
