import QtQuick
import qs.Commons

// Pill-shaped toggle chip. `cornerRadius`/`extraWidth`/`fontSize` reproduce both
// looks from one component: the tab-chip pill (height/2 radius, bodySmall,
// generous extra width) and the filter pill (cornerRadius, caption, tight
// extra width). `extraWidth` is the TOTAL width added around the label — half
// per side — so it is not a per-side inset. `active` fills with the accent;
// `toggled()` fires on click.
Rectangle {
  id: pillButton
  property Item panel
  property bool active: false
  property string label: ""
  property real cornerRadius: pillButton.height / 2
  property real extraWidth: Style.space(18)
  property real fontSize: Style.font.bodySmall
  signal toggled()

  implicitWidth: pillText.implicitWidth + pillButton.extraWidth
  height: Style.space(24)
  radius: pillButton.cornerRadius
  color: pillButton.active ? panel.accentColor : "transparent"
  border.color: pillButton.active ? panel.accentColor : panel.secondaryColor
  border.width: 1
  Text {
    textFormat: Text.PlainText
    id: pillText
    anchors.centerIn: parent
    text: pillButton.label
    color: pillButton.active ? panel.accentTextColor : panel.secondaryColor
    font.pixelSize: pillButton.fontSize
    font.bold: pillButton.active
  }
  MouseArea {
    anchors.fill: parent
    cursorShape: pillButton.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: pillButton.toggled()
  }
}
