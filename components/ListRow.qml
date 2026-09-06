import QtQuick
import qs.Commons

// Hover-highlight row shared by the filter dropdown and the search results
// dropdown. `text` is the leading label; `active` bolds it. An optional
// `secondaryText` renders a muted caption to its right (the search hit's count
// label); `leftMargin` matches each caller's inset. `muted` renders the leading
// label in the panel's secondary color (the dropdown clear row). An optional
// `iconSource` renders a leading icon before the label (the search query row's
// magnifier). clicked() is the only interaction — callers decide what to do.
HoverRow {
  id: row
  property string text: ""
  property bool active: false
  property bool muted: false
  property string secondaryText: ""
  property real leftMargin: 0
  property string iconSource: ""

  Row {
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    anchors.leftMargin: row.leftMargin
    spacing: Style.space(6)
    Image {
      visible: row.iconSource !== ""
      source: Qt.resolvedUrl(row.iconSource)
      width: 14
      height: 14
      anchors.verticalCenter: parent.verticalCenter
    }
    Text {
      textFormat: Text.PlainText
      text: row.text
      color: row.muted ? row.panel.secondaryColor : row.panel.foregroundColor
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
}
