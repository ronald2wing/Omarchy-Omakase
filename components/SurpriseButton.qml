import QtQuick
import qs.Commons

// "Surprise me" pill: dice glyph + label, hover-highlighted, with a tooltip
// spelling out the action — or why it is disabled when the filter/search pool
// is empty. Sized to its content so the tab chips take the remainder of the
// pinned header row.
Rectangle {
  id: surpriseButton
  property Item panel

  width: surpriseRow.implicitWidth + Style.space(16)
  height: Style.space(28)
  radius: Style.cornerRadius
  color: surpriseHover.hovered ? panel.cardHoverBackground : panel.cardBackground
  border.color: panel.foregroundAlpha(0.1)
  border.width: 1

  Row {
    id: surpriseRow
    anchors.centerIn: parent
    spacing: Style.space(5)
    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      text: "\u2684"
      color: panel.foregroundColor
      font.pixelSize: Style.font.bodySmall
    }
    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      text: "Surprise me"
      color: panel.foregroundColor
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }
  HoverHandler { id: surpriseHover }
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: panel.surpriseMe()
  }
  Tooltip {
    // Shown in both states: enabled spells out the action, disabled explains
    // why there is nothing to draw from. Parented directly — the pill does not
    // dim itself when disabled (no opacity/enabled treatment here or in
    // PillButton), so the tooltip never inherits a disabled dim.
    // Placed below-right, into the panel body: the trigger sits at the top of
    // the pinned header, where a tooltip above it would be clipped.
    visible: surpriseHover.hovered
    anchors.top: parent.bottom; anchors.topMargin: Style.space(4)
    anchors.right: parent.right
    panel: surpriseButton.panel
    text: surpriseButton.enabled ? "Open a random spot" : "No spots match your filters"
  }
}
