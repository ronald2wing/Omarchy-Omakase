import QtQuick
import "../catalog-utils.js" as CatalogUtils

// Journal tab: rated spot list. The shared layout lives in SpotListTab; this
// file pins the rated-spots parameters (delegate flags that differ from the
// SpotListTab defaults are set here).
SpotListTab {
  viewName: CatalogUtils.VIEW_JOURNAL
  query: panel.journalQuery
  countNoun: "rated"
  listModel: panel.journalModel
  emptyGlyph: "\u2606"
  emptyStateHeadline: panel.ratedEntries.length > 0
    ? CatalogUtils.buildEmptyHeadline("rated", panel.journalQuery, "")
    : "No rated spots yet."
  emptyCaption: panel.ratedEntries.length > 0
    ? CatalogUtils.EMPTY_STATE_CAPTION
    : "Rate a spot to see it here."
  starsInteractive: false
  showDateInPlaceRow: true
  onQueryCleared: panel.journalQuery = ""
}
