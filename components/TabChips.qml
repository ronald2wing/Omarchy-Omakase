import QtQuick
import qs.Commons

// Explore / Wishlist / Journal tab chip row. Shared by the main column and
// the spotlight view. `currentTab` marks the active chip; `picked` lets each
// call site apply its own side-effects (the spotlight view also closes).
Row {
  id: tabs
  property Item panel
  property string currentTab: ""
  signal picked(string tab)
  width: parent.width - Style.space(32)
  spacing: Style.space(8)
  PillButton {
    panel: tabs.panel
    label: "Explore"
    active: tabs.currentTab === "explore"
    onToggled: tabs.picked("explore")
  }
  PillButton {
    panel: tabs.panel
    label: "Wishlist (" + tabs.panel.saved.length + ")"
    active: tabs.currentTab === "wishlist"
    onToggled: tabs.picked("wishlist")
  }
  PillButton {
    panel: tabs.panel
    label: "Journal (" + tabs.panel.journalCount + ")"
    active: tabs.currentTab === "journal"
    onToggled: tabs.picked("journal")
  }
}
