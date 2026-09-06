import QtQuick
import qs.Commons

// Shared search header for the Explore, Wishlist, and Journal tabs, mounted in
// the pinned header column above the scroller (BarWidget). The tab chips live
// in that same pinned header, so they are not repeated here.
Column {
  id: header
  property Item panel
  property string query: ""
  property string placeholder: ""
  // Which view this header's search field belongs to ("explore" | "wishlist" |
  // "journal"), compared against the panel's activeSearchView (or chromeView,
  // see useChromeView) to gate its dropdown.
  property string viewName: ""
  // Dropdown activation mode: false (default) gates the dropdown on
  // activeSearchView === viewName (the on-screen tab); true gates it on
  // chromeView === viewName. Explore sets true because Spotlight reuses
  // Explore's chrome, so the field/dropdown stay live while Spotlight is open
  // (and activeSearchView would have switched to "spotlight").
  property bool useChromeView: false
  // Per-tab search field sizing; the insets default to the tabs' tighter 8px,
  // while Explore overrides them with SearchField's own defaults (10/6).
  property real fieldHeight: Style.space(32)
  property real leftInset: Style.space(8)
  property real rightInset: Style.space(8)
  property real clearSize: 18
  signal edited(string value)
  signal dismissed()
  signal fieldClicked()
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
    leftInset: header.leftInset
    rightInset: header.rightInset
    clearSize: header.clearSize
    onEdited: function(v) { header.edited(v) }
    onDismissed: header.dismissed()
    onFieldClicked: header.fieldClicked()
  }

  // City/neighborhood/state match dropdown under this tab's search field. No
  // width override needed — this Column is `width: parent.width`, so the
  // dropdown's own `width: parent.width` matches the field.
  SearchSuggestionsDropdown {
    panel: header.panel
    active: header.useChromeView
      ? header.panel.chromeView === header.viewName
      : header.panel.activeSearchView === header.viewName
  }
}
