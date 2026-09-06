import QtQuick
import qs.Commons

// Active-filter token: a pill showing the filter's current value. Clicking
// emits cleared() so the caller removes its own filter. Purely presentational —
// it reads panel colors only, never writes filter state, and its width tracks
// the label so a Flow lays it out like an inline chip.
Rectangle {
  id: token
  property Item panel
  property string text: ""
  signal cleared()

  width: tokenText.implicitWidth + Style.space(10)
  height: Style.space(20)
  radius: Style.space(10)
  color: token.panel.accentTint

  Text {
    id: tokenText
    textFormat: Text.PlainText
    anchors.centerIn: parent
    text: token.text
    color: token.panel.accentColor
    font.pixelSize: Style.font.caption
  }
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: token.cleared()
  }
}
