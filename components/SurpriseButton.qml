import QtQuick
import qs.Commons

// "Surprise me" pill: five-pip die face + label, hover-highlighted, with a tooltip
// spelling out the action — or why it is disabled when the filter/search pool
// is empty. Sized to its content so the tab chips take the remainder of the
// pinned header row.
Rectangle {
  id: surpriseButton
  property Item panel
  // While the spotlight is open this pill is the page's active element, so it
  // takes the active tab chip's accent treatment (see PillButton.qml) and the
  // re-roll glyph.
  property bool active: false

  width: surpriseRow.implicitWidth + Style.space(16)
  height: Style.space(28)
  radius: Style.cornerRadius
  color: surpriseButton.active ? panel.accentColor
       : (surpriseHover.hovered ? panel.cardHoverBackground : panel.cardBackground)
  border.color: surpriseButton.active ? panel.accentColor : panel.foregroundAlpha(0.1)
  border.width: 1

  Row {
    id: surpriseRow
    anchors.centerIn: parent
    spacing: Style.space(5)
    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      // The five-pip die face when offering a surprise; the re-roll arrow while
      // the spotlight is open and the pill means "shuffle again".
      text: surpriseButton.active ? "\u21bb" : "\u2684"
      color: surpriseButton.active ? panel.accentTextColor : panel.foregroundColor
      font.pixelSize: Style.font.bodySmall
    }
    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      text: "Surprise me"
      color: surpriseButton.active ? panel.accentTextColor : panel.foregroundColor
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
    // why there is nothing to draw from. The enabled/disabled split keys off the
    // built-in Item.enabled, which this component never declares — the caller
    // sets it (BarWidget: `enabled: surprisePoolSize > 0`), so the first branch
    // below is the empty-pool case. Parented directly — the pill does not dim
    // itself when disabled (no opacity/enabled treatment here or in PillButton),
    // so the tooltip never inherits a disabled dim.
    // Placed below-right, into the panel body: the trigger sits at the top of
    // the pinned header, where a tooltip above it would be clipped.
    visible: surpriseHover.hovered
    anchors.top: parent.bottom; anchors.topMargin: Style.space(4)
    anchors.right: parent.right
    panel: surpriseButton.panel
    // A one-spot pool still re-rolls to that spot (pool > 0 keeps the pill
    // enabled), so the active case explains what the click will show.
    text: !surpriseButton.enabled ? "No open spots match your search or filters"
        : (surpriseButton.active && panel.surprisePoolSize <= 1
           ? "Only one open spot matches your search or filters"
           : "Open a random spot from the current results")
  }
}
