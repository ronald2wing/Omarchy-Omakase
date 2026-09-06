import QtQuick
import qs.Commons

// Generic filter dropdown panel. `items` is a list of { key, label } pairs;
// `shown` toggles visibility; picking a row emits picked(key). When
// `clearLabel` is non-empty a clear row is rendered above the options and
// emits picked("") — the caller's select*("") clears the scope.
//
// `maxHeight` is the vertical space between the sheet's top and the popup's
// bottom edge (passed down by FilterSheet). The option list is capped to that
// minus this dropdown's own offset within the sheet, so a long list scrolls
// internally instead of running past the popup and getting clipped mid-row.
Column {
  id: dropdown
  property Item panel
  property var items: []
  property string clearLabel: ""
  property bool shown: false
  // Space from the sheet's top to the popup's bottom edge. 0 = uncapped.
  property real maxHeight: 0
  signal picked(string key)
  visible: shown
  width: parent.width
  spacing: 0

  // Space from this dropdown's top to the popup's bottom edge. The dropdown's
  // own offset within the sheet is read reactively (its y plus the sheet
  // column's top margin) so the cap follows the row layout when a preceding
  // row appears or disappears.
  readonly property real availableHeight: {
    if (dropdown.maxHeight <= 0) return 0;
    var offset = dropdown.y + (dropdown.parent ? dropdown.parent.y : 0);
    return Math.max(Style.space(80), dropdown.maxHeight - offset);
  }

  Rectangle {
    width: parent.width
    // Cover the full option column plus its top/bottom insets, capped to the
    // space actually left in the popup. Bound to the column's implicitHeight
    // (not a fixed value) so every row is occluded regardless of how many
    // items the filter yields.
    height: dropdown.maxHeight > 0
      ? Math.min(ddCol.implicitHeight + Style.space(8), dropdown.availableHeight)
      : ddCol.implicitHeight + Style.space(8)
    radius: Style.cornerRadius
    // Opaque popup surface, shared via panel.popupBackground.
    color: dropdown.panel.popupBackground
    border.color: Color.popups.border
    border.width: Style.normalBorderWidth

    // Scrolls the option rows when the list is taller than the cap. `clip`
    // keeps the rows inside the rounded surface; `interactive` is off when
    // everything fits so a short list never captures a drag.
    Flickable {
      id: ddFlick
      anchors.fill: parent
      clip: true
      contentWidth: width
      contentHeight: ddCol.implicitHeight
      interactive: contentHeight > height
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: ddCol
        x: Style.space(8)
        y: Style.space(4)
        width: ddFlick.width - Style.space(16)
        spacing: Style.space(2)
        // Clear row: always first, above the options. Emits the empty key so the
        // caller's select*("") clears the scope.
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
          delegate: ListRow {
            panel: dropdown.panel
            text: modelData.label
            onClicked: dropdown.picked(modelData.key)
          }
        }
      }
    }
  }
}
