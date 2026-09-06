import QtQuick
import qs.Commons

// Active-filter token: a pill showing the filter's current value. Clicking
// emits cleared() so the caller removes its own filter. Purely presentational —
// it reads panel colors only, never writes filter state, and its width tracks
// the label so a Flow lays it out like an inline chip.
//
// Deliberately subordinate to the chip row above: outline-only (no fill), the
// neutral secondary color, and a size step down, so the same filter never reads
// as two peer controls ~30px apart. It stays clickable — the outline is the
// affordance, not a fill.
Rectangle {
  id: token
  property Item panel
  property string text: ""
  signal cleared()

  width: tokenText.implicitWidth + Style.space(10)
  height: Style.space(20)
  radius: Style.space(10)
  color: "transparent"
  border.color: token.panel.secondaryColor
  border.width: 1

  Text {
    id: tokenText
    textFormat: Text.PlainText
    anchors.centerIn: parent
    text: token.text
    color: token.panel.secondaryColor
    font.pixelSize: Style.font.caption - 1
  }
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: token.cleared()
  }
}
