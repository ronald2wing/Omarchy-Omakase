import QtQuick
import qs.Commons

// Generic filter dropdown panel. `items` is a list of { key, label } pairs;
// `shown` toggles visibility; picking a row emits picked(key). When
// `clearLabel` is non-empty a clear row is rendered above the options and
// emits picked("") — the caller's select*("") clears the scope.
Column {
  id: dropdown
  property Item panel
  property var items: []
  property string clearLabel: ""
  property bool shown: false
  signal picked(string key)
  visible: shown
  width: parent.width
  spacing: 0
  Rectangle {
    id: ddSurface
    width: parent.width
    // Cover the full option column plus its top/bottom insets. Bound to the
    // column's implicitHeight (not a fixed value) so every row is occluded
    // regardless of how many items the filter yields.
    height: ddCol.implicitHeight + Style.space(8)
    radius: Style.cornerRadius
    // Force alpha 1.0: Color.popups.background is composed from the theme's
    // `popups.background-alpha`, which a theme may set below 1.0. Rebuilding
    // the color from its RGB components guarantees an opaque surface so the
    // card list can never show through the option rows.
    color: Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, 1.0)
    border.color: Color.popups.border
    border.width: Style.normalBorderWidth
    Column {
      id: ddCol
      anchors.left: parent.left; anchors.leftMargin: Style.space(8)
      anchors.right: parent.right; anchors.rightMargin: Style.space(8)
      anchors.top: parent.top; anchors.topMargin: Style.space(4)
      spacing: Style.space(2)
      // Clear row: always first, above the options. Emits the empty key so the
      // caller's select*("") clears the scope (same path as the old pill click).
      Rectangle {
        visible: dropdown.clearLabel !== ""
        width: parent.width; height: Style.space(28); radius: Style.cornerRadius
        color: clearHover ? dropdown.panel.cardHoverBackground : "transparent"
        property bool clearHover: false
        HoverHandler { onHoveredChanged: parent.clearHover = hovered }
        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: dropdown.clearLabel
          color: dropdown.panel.secondaryColor
          font.pixelSize: Style.font.bodySmall
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: dropdown.picked("")
        }
      }
      Repeater {
        model: items
        delegate: Rectangle {
          width: parent.width; height: Style.space(28); radius: Style.cornerRadius
          color: hover ? dropdown.panel.cardHoverBackground : "transparent"
          property bool hover: false
          HoverHandler { onHoveredChanged: parent.hover = hovered }
          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.label
            color: dropdown.panel.foregroundColor
            font.pixelSize: Style.font.bodySmall
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: dropdown.picked(modelData.key)
          }
        }
      }
    }
  }
}
