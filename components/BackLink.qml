import QtQuick
import qs.Commons

// Shared "back" link: a clickable back.svg + accent label row. The MouseArea
// lives on the wrapping Item, never as a direct child of the Row (that triggers
// "Row will not function" polish loops). `label` completes the trailing text
// ("All Cities" / "Back").
Item {
  id: backLink
  property Item panel
  property string label: ""
  signal clicked()
  implicitWidth: innerRow.implicitWidth
  implicitHeight: innerRow.implicitHeight
  Row {
    id: innerRow
    spacing: Style.space(8)
    Image { source: Qt.resolvedUrl("../icons/back.svg"); width: 14; height: 14; anchors.verticalCenter: parent.verticalCenter }
    Text { textFormat: Text.PlainText; text: backLink.label; color: panel.accentColor; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter }
  }
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: backLink.clicked()
  }
}
