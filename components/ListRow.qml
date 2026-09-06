import QtQuick
import qs.Commons

// Hover-highlight row shared by the filter dropdown and the search results
// dropdown. `text` is the leading label; `active` bolds it. An optional
// `secondaryText` renders a muted caption to its right (the search hit's count
// label); `leftMargin` matches each caller's inset. clicked() is the only
// interaction — callers decide what to do.
Rectangle {
  id: row
  property Item panel
  property string text: ""
  property bool active: false
  property string secondaryText: ""
  property real leftMargin: 0
  signal clicked()

  width: parent.width
  height: Style.space(28)
  radius: Style.cornerRadius
  color: rowHover ? row.panel.cardHoverBackground : "transparent"
  property bool rowHover: false
  HoverHandler { onHoveredChanged: parent.rowHover = hovered }

  Row {
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    anchors.leftMargin: row.leftMargin
    spacing: row.secondaryText !== "" ? Style.space(6) : 0
    Text {
      textFormat: Text.PlainText
      text: row.text
      color: row.panel.foregroundColor
      font.pixelSize: Style.font.bodySmall
      font.bold: row.active
    }
    Text {
      textFormat: Text.PlainText
      visible: row.secondaryText !== ""
      text: row.secondaryText
      color: row.panel.secondaryColor
      font.pixelSize: Style.font.caption
    }
  }
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: row.clicked()
  }
}
