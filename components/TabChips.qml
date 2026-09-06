import QtQuick
import qs.Commons
import "../catalog-utils.js" as CatalogUtils

// Explore / Wishlist / Journal tab chip row, mounted once in the pinned header
// (shared by every view, including Spotlight via `chromeView`). `activeTab`
// marks the active chip; `picked` lets the call site apply its own side-effects.
Row {
  id: tabs
  property Item panel
  property string activeTab: ""
  signal picked(string tab)
  width: parent.width
  spacing: Style.space(8)
  PillButton {
    panel: tabs.panel
    label: "Explore"
    active: tabs.activeTab === CatalogUtils.VIEW_EXPLORE
    onToggled: tabs.picked(CatalogUtils.VIEW_EXPLORE)
  }
  PillButton {
    panel: tabs.panel
    label: "Wishlist (" + tabs.panel.savedCount + ")"
    active: tabs.activeTab === CatalogUtils.VIEW_WISHLIST
    onToggled: tabs.picked(CatalogUtils.VIEW_WISHLIST)
  }
  PillButton {
    panel: tabs.panel
    label: "Journal (" + tabs.panel.ratedCount + ")"
    active: tabs.activeTab === CatalogUtils.VIEW_JOURNAL
    onToggled: tabs.picked(CatalogUtils.VIEW_JOURNAL)
  }
}
