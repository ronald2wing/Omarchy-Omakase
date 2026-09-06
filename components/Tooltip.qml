import QtQuick
import qs.Commons

// Hover tooltip with the shared chrome: opaque popup surface, 2px radius,
// faint foreground border, centered caption. Callers position it via anchors
// (top/left or top/right) and gate `visible` on their hover handler.
Rectangle {
  id: tooltip
  property Item panel
  property string text: ""

  width: tooltipText.implicitWidth + Style.space(8)
  height: tooltipText.implicitHeight + Style.space(4)
  radius: 2
  // Opaque popup surface, shared via panel.popupBackground.
  color: panel.popupBackground
  border.color: panel.foregroundAlpha(0.1)
  z: 5

  Text {
    textFormat: Text.PlainText
    id: tooltipText
    anchors.centerIn: parent
    text: tooltip.text
    color: panel.secondaryColor
    font.pixelSize: Style.font.caption
  }
}
