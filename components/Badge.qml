import QtQuick
import QtQuick.Layouts
import qs.Commons

// Small pill label in the card title row (closed / reserve). Presentational:
// the caller supplies the label and the three colors; the pill sizes to its
// label text and stays vertically centered in the surrounding RowLayout.
Rectangle {
  id: badge
  property string label: ""
  property color tint: "transparent"
  property color borderColor: "transparent"
  property color textColor: "#ffffff"

  Layout.alignment: Qt.AlignVCenter
  implicitWidth: badgeText.implicitWidth + Style.space(12)
  implicitHeight: Style.space(18)
  radius: Style.space(4)
  color: badge.tint
  border.color: badge.borderColor
  border.width: 1

  Text {
    id: badgeText
    textFormat: Text.PlainText
    anchors.centerIn: parent
    text: badge.label
    color: badge.textColor
    font.bold: true
    font.pixelSize: Style.font.caption
  }
}
