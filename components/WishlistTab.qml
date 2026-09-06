import QtQuick
import "../catalog-utils.js" as CatalogUtils

// Wishlist tab: saved spot list. The shared layout lives in SpotListTab; this
// file pins the saved-spots parameters. The omitted delegate flags
// (starsInteractive true, showDateInPlaceRow false) are the SpotListTab
// defaults.
SpotListTab {
  viewName: CatalogUtils.VIEW_WISHLIST
  query: panel.wishlistQuery
  countNoun: "saved"
  listModel: panel.wishlistModel
  emptyGlyph: "\u2661"
  emptyStateHeadline: panel.saved.length === 0
    ? "No saved spots yet."
    : CatalogUtils.buildEmptyHeadline("saved", panel.wishlistQuery, "")
  emptyCaption: panel.saved.length === 0
    ? "Click the heart icon on any spot to save it."
    : CatalogUtils.EMPTY_STATE_CAPTION
  onQueryCleared: panel.wishlistQuery = ""
}
