import QtQuick
import qs.Commons

// Shared search header for the Wishlist and Journal tabs. The tab chips live in
// the pinned header above the scroller (BarWidget), so they are not repeated
// here.
Column {
  id: header
  property Item panel
  property string query: ""
  property string placeholder: ""
  // Per-tab search field sizing; defaults match SearchField's own defaults.
  property real fieldHeight: Style.space(32)
  property real clearSize: 18
  signal edited(string value)
  signal dismissed()
  // Mirrors SearchField.hasFocus so the panel's PanelKeyCatcher can `block`
  // key interception while this tab's search field is being typed into.
  readonly property bool hasFocus: searchField.hasFocus

  width: parent.width
  spacing: Style.space(10)

  SearchField {
    id: searchField
    panel: header.panel
    placeholder: header.placeholder
    text: header.query
    height: header.fieldHeight
    leftInset: Style.space(8)
    rightInset: Style.space(8)
    clearSize: header.clearSize
    onEdited: function(v) { header.edited(v) }
    onDismissed: header.dismissed()
  }
}
