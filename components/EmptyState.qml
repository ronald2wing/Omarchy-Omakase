import QtQuick
import qs.Commons

// Shared empty-state column: glyph + bold headline + caption, centered and
// padded, collapsing to 0 height when hidden. Callers set `visible` to the
// "no data" condition; the height collapse lives here so every tab collapses
// identically.
Column {
  id: emptyState
  property Item panel
  property string glyph: ""
  property string headline: ""
  property string caption: ""

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
}
