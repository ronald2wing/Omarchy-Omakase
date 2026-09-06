import QtQuick
import qs.Commons

// One location-filter row in the sheet: a fixed label on the left, the current
// value on the right. `active` swaps the value's accent style in for the muted
// `placeholder` ("Any …") shown when nothing is set. Hover/click chrome only —
// the caller wires clicked() to its clear-if-set-else-toggle-dropdown branch.
Rectangle {
  id: row
  property Item panel
  property string label: ""
  property string value: ""
  property string placeholder: ""
  property bool active: false
  signal clicked()

  width: parent.width
  height: Style.space(28)
  radius: Style.cornerRadius
  color: rowHover ? row.panel.cardHoverBackground : "transparent"
  property bool rowHover: false
  HoverHandler { onHoveredChanged: parent.rowHover = hovered }

  Text {
    textFormat: Text.PlainText
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    anchors.leftMargin: Style.space(6)
    text: row.label
    color: row.panel.secondaryColor
    font.pixelSize: Style.font.bodySmall
  }
  Text {
    textFormat: Text.PlainText
    anchors.verticalCenter: parent.verticalCenter
    anchors.right: parent.right
    anchors.rightMargin: Style.space(6)
    text: row.active ? row.value : row.placeholder
    color: row.active ? row.panel.accentColor : row.panel.secondaryColor
    font.pixelSize: Style.font.caption
    font.bold: row.active
  }
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: row.clicked()
  }
}
