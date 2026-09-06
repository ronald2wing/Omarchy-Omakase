import QtQuick
import qs.Commons
import "../catalog-utils.js" as CatalogUtils
// This file never references SpotUtils itself, but CatalogUtils.searchHitLabel
// (called below) reaches SpotUtils.SEP/SEP_LEAD lazily in its own body, and
// that body resolves the bare SpotUtils identifier through THIS document's
// `import ... as SpotUtils` qualifier (the shared cross-module read rule). The
// import is required by the callee's body, not by this file's code — do not
// delete it just because this file has no direct SpotUtils read.
import "../spot-utils.js" as SpotUtils

// City/neighborhood/state search dropdown, floating under a search field. One
// instance per view (Explore, Wishlist, Journal, Spotlight); `active` — set by
// the caller from panel.activeSearchView — gates which instance is live, so
// only the active view's dropdown is ever visible. `panel` is the BarWidget
// root.
Column {
  id: dropdown
  property Item panel
  property bool active: false

  // Rows shown before the place list scrolls internally. A long hit list
  // scrolls instead of growing the pinned region unbounded and shrinking the
  // card list below it.
  readonly property int maxVisibleRows: 6
  // Pinned-drop height cap in px: maxVisibleRows rows plus inter-row spacing
  // and the surface inset, read back from their owners (queryRow.rowHeight,
  // pinnedDrop.rowSpacing/surfaceInset) and scaled once.
  readonly property real rowCap: Style.space(dropdown.maxVisibleRows * queryRow.rowHeight + (dropdown.maxVisibleRows - 1) * pinnedDrop.rowSpacing + pinnedDrop.surfaceInset)

  width: parent.width
  spacing: 0
  // `searchSuggestionsDismissed` (a plain bool on the panel root) lets a
  // deliberate user action — Escape, the query row, a card click, a place-row
  // pick, or a tab switch — hide the suggestions without clearing the query.
  // One flag gates all four views' dropdowns (Explore, Wishlist, Journal,
  // Spotlight). It resets to false on a search/query change (typing), so typing
  // re-opens them.
  visible: dropdown.active && dropdown.panel.searchSuggestionsVisible

  // The query as shown by the query row, capped via CatalogUtils.displayQueryCapped
  // (the shared transform CityHeader's hint also uses) so a long query cannot
  // break the row. Reads the panel's activeViewQuery directly (tracked) so
  // the label re-evaluates on every keystroke in the active view.
  readonly property string queryLabel: CatalogUtils.displayQueryCapped(panel.activeViewQuery)

  Rectangle {
    width: parent.width
    // The query row (28px + its 4px top inset) sits pinned above the capped
    // place list, so it never scrolls out of reach.
    height: Style.space(4) + queryRow.height + pinnedDrop.height
    radius: Style.cornerRadius
    color: panel.cardBackground
    border.color: panel.foregroundAlpha(0.1)

    // Query row — represents the query itself (magnifier + `Search "…"`).
    // Visually distinct from the place rows (`Name · N spots`): muted caption
    // color, leading magnifier glyph. Picking it only dismisses — the query is
    // already applied to the list. A ListRow (shared with the place rows) with
    // the leading-icon slot.
    ListRow {
      id: queryRow
      anchors.top: parent.top
      anchors.topMargin: Style.space(4)
      panel: dropdown.panel
      text: "Search \"" + dropdown.queryLabel + "\""
      muted: true
      iconSource: "../icons/search.svg"
      leftMargin: Style.space(14)
      onClicked: dropdown.panel.searchSuggestionsDismissed = true
    }

    // Scroll-capped place list. DropdownSurface owns the Flickable + inset
    // Column idiom (clip, `interactive` only when overflowing, StopAtBounds);
    // transparent chrome because the card above already fills the surface. The
    // cap is the pinned row budget (dropdown.rowCap), so a long hit list
    // scrolls internally instead of growing the pinned area unbounded.
    DropdownSurface {
      id: pinnedDrop
      anchors.top: queryRow.bottom
      maxHeight: dropdown.rowCap

      Repeater {
        model: dropdown.active ? panel.activeSearchHits : []
        delegate: ListRow {
          panel: dropdown.panel
          text: modelData.name
          active: modelData.type === "city"
          secondaryText: CatalogUtils.searchHitLabel(modelData)
          leftMargin: Style.space(6)
          onClicked: {
            // Dismiss before applying the scope: a state pick leaves cityKey
            // empty, so the `!panel.cityKey` visibility gate alone would not
            // hide the dropdown.
            dropdown.panel.searchSuggestionsDismissed = true
            if (modelData.type === "neighborhood") {
              dropdown.panel.selectNeighborhood(modelData.key, modelData.cityKey)
            } else if (modelData.type === "state") {
              dropdown.panel.selectState(modelData.key)
            } else {
              dropdown.panel.selectCity(modelData.key)
            }
          }
        }
      }
    }
  }
}
