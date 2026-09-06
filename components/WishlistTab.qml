import QtQuick
import qs.Commons

// Wishlist tab: saved-spot search + filter panel + saved spot list. `panel` is
// the BarWidget root; `scrollView` is the outer Flickable the root passes in for
// image gating.
Column {
  id: wishlistTab
  property Item panel
  property var scrollView
  // Exposed for the panel's PanelKeyCatcher to `block` while typing in search.
  readonly property bool searchFieldHasFocus: searchHeader.hasFocus

  visible: panel.tab === "wishlist"
  width: parent.width - Style.space(32)
  spacing: Style.space(10)

  TabSearchHeader {
    id: searchHeader
    panel: wishlistTab.panel
    query: wishlistTab.panel.wishlistQuery
    placeholder: "Search saved spots…"
    onEdited: function(v) { wishlistTab.panel.wishlistQuery = v }
    onDismissed: wishlistTab.panel.close()
  }

  CityHeader {
    panel: wishlistTab.panel
    visible: wishlistTab.panel.cityKey !== ""
    // A Column measures hidden children too, so collapse the height to 0 when
    // hidden — otherwise the panel reserves space for a header that isn't shown.
    height: visible ? implicitHeight : 0
    count: wishlistTab.panel.filteredWishlist.length
    label: "saved"
    plural: false
    // The query filteredWishlist actually filtered by.
    query: wishlistTab.panel.wishlistQuery
    onBack: {
      wishlistTab.panel.applyLocationScope("", "");
      wishlistTab.panel.wishlistQuery = "";
    }
    onClearQuery: wishlistTab.panel.wishlistQuery = ""
  }

  FilterPanel { panel: wishlistTab.panel }

  // Empty state — "nothing saved" vs "saved but filtered to none".
  EmptyState {
    panel: wishlistTab.panel
    visible: wishlistTab.panel.filteredWishlist.length === 0
    glyph: "\u2661"
    headline: wishlistTab.panel.saved.length === 0
      ? "No saved spots yet."
      : (wishlistTab.panel.wishlistQuery ? "No saved spots match your search." : "No saved spots match your filters.")
    caption: wishlistTab.panel.saved.length === 0
      ? "Tap the heart icon on any spot to save it."
      : "Try a different search or clear your filters."
  }
  Column {
    width: parent.width
    spacing: Style.space(8)
    ListView {
      cacheBuffer: Style.space(500)
      width: parent.width
      height: contentHeight
      interactive: false
      model: wishlistTab.panel.wishlistModel
      delegate: SpotCard {
        panel: wishlistTab.panel
        scrollView: wishlistTab.scrollView
        spot: modelData.spot
        cityKey: modelData.cityKey
        fallbackName: modelData.name
        journalEntry: wishlistTab.panel.latestJournalFor(modelData.name)
        starsInteractive: true
        showCity: !!modelData.cityKey
        useHoverBg: true
        zebraStripe: 0
      }
    }
  }
}
