import QtQuick
import qs.Commons

// Shared empty-state column: glyph + bold headline + caption, centered and
// padded, collapsing to 0 height when hidden. Callers set `visible` to the
// "no data" condition; the height collapse lives here so every tab collapses
// identically.
//
// An optional action pill renders below the caption when `actionLabel` is set.
// `action` is a closure carrying the exact side effect (the same clearAction
// idiom FilterBar's activeTokens use), so the empty state never reaches into
// panel state itself. Both default off, so the single-cause states keep their
// current look and behaviour exactly.
Column {
  id: emptyState
  property Item panel
  property string glyph: ""
  property string headline: ""
  property string caption: ""
  property string actionLabel: ""
  property var action: null

  width: parent.width
  spacing: Style.space(8)
  topPadding: Style.space(24)
  bottomPadding: Style.space(24)
  height: visible ? implicitHeight : 0

  Text {
    textFormat: Text.PlainText
    anchors.horizontalCenter: parent.horizontalCenter
    text: emptyState.glyph
    color: panel.secondaryColor
    font.pixelSize: Style.fontPx(2.2)
  }
  Text {
    textFormat: Text.PlainText
    width: parent.width
    text: emptyState.headline
    color: panel.foregroundColor
    font.pixelSize: Style.font.bodySmall
    font.bold: true
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
  }
  Text {
    textFormat: Text.PlainText
    width: parent.width
    text: emptyState.caption
    color: panel.secondaryColor
    font.pixelSize: Style.font.caption
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
  }
  PillButton {
    panel: emptyState.panel
    visible: emptyState.actionLabel !== ""
    anchors.horizontalCenter: parent.horizontalCenter
    label: emptyState.actionLabel
    onToggled: { if (emptyState.action) emptyState.action(); }
  }
}
