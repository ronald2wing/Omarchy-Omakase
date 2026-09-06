import QtQuick
import QtQuick.Layouts
import qs.Commons

// Small pill label in a card's spec row (Closed / Reserve). Presentational:
// the caller supplies the label, colors, radius, and caption weight; the pill
// sizes to its label text and stays vertically centered in the surrounding
// RowLayout. The default transparent border renders it borderless (Reserve,
// matching the muted Yelp pill); pass an explicit `borderColor` for the
// bordered Closed badge.
Rectangle {
  id: badge
  property string label: ""
  property color tint: "transparent"
  property color borderColor: "transparent"
  property color textColor: "#ffffff"
  property real cornerRadius: Style.space(4)
  property real horizontalPadding: Style.space(12)
  property bool bold: true

  Layout.alignment: Qt.AlignVCenter
  implicitWidth: badgeText.implicitWidth + badge.horizontalPadding
  implicitHeight: Style.space(18)
  // Pin the pill to its content width: a fill-width sibling in the card's spec
  // row would otherwise squeeze a zero-minimum-width Rectangle below its glyphs
  // ("Clos…"). The hint reads `badgeText.implicitWidth` (the child Text), never
  // `badge.implicitWidth` — reading the item's own implicit width feeds the
  // assigned width back into the measure (the price-segment self-reference).
  Layout.minimumWidth: badgeText.implicitWidth + badge.horizontalPadding
  radius: badge.cornerRadius
  color: badge.tint
  border.color: badge.borderColor
  border.width: 1

  Text {
    id: badgeText
    textFormat: Text.PlainText
    anchors.centerIn: parent
    text: badge.label
    color: badge.textColor
    font.bold: badge.bold
    font.pixelSize: Style.font.caption
  }
}
