import QtQuick
import qs.Commons
import "../catalog-utils.js" as CatalogUtils
import "../spot-utils.js" as SpotUtils

// "Back to All locations" header row. The title (city name or "Within N km")
// is derived from root state; `countNoun`/`count` complete the trailing count
// text ("42 spots" / "7 saved" / "3 rated") which differs per tab. Explore
// sets `plural` so the count takes the "N spots" form; the Wishlist/Journal
// tabs pass an invariant noun via `countNoun` ("saved"/"rated"). `back` lets
// each call site reset its own query/state.
//
// `query` is the exact value the tab's list filtered by (Explore's
// debouncedSearchText, Wishlist's wishlistQuery, Journal's journalQuery). When it is
// non-blank the count line appends ` matching "…"` so a scoped search never
// reads as a broken count, and the hint is clickable to clear it via
// `clearQuery` (the call site owns the target property).
Row {
  id: header
  property Item panel
  property string countNoun: ""
  property bool plural: false
  property int count: 0
  property string query: ""
  signal back()
  signal clearQuery()
  width: parent.width
  spacing: Style.space(8)

  // The query as shown in the hint: trimmed, capped, ellipsized via
  // CatalogUtils.displayQueryCapped (the shared transform the search dropdown's
  // query row also uses), so a long query can't push the title out of alignment
  // in this narrow row. Blank when the query is blank (whitespace-only folds to
  // no filter, so no hint). A readonly binding (not a function) so the call
  // sites below track `query` changes.
  readonly property string displayQuery: CatalogUtils.displayQueryCapped(header.query)
  // The ` matching "…"` suffix, derived once so the title and the hint metrics
  // share a single build.
  readonly property string queryHint: header.displayQuery ? " matching \"" + header.displayQuery + "\"" : ""

  BackLink {
    id: headerBack
    panel: header.panel
    label: "All locations"
    onClicked: header.back()
  }
  Text {
    id: headerText
    textFormat: Text.PlainText
    anchors.verticalCenter: parent.verticalCenter
    width: header.width - headerBack.width - header.spacing
    horizontalAlignment: Text.AlignRight
    text: {
      var title = header.panel.radius > 0 ? CatalogUtils.radiusLabel(header.panel.radius) : header.panel.cityLabel(header.panel.cityKey);
      // The caller owns pluralization: `plural` renders "N spots"; otherwise
      // `countNoun` is appended verbatim ("saved"/"rated").
      var trailing = header.plural ? CatalogUtils.spotCountLabel(header.count) : CatalogUtils.unpluralizedCountLabel(header.count, header.countNoun);
      // No query -> byte-identical to the pre-hint output.
      if (!header.displayQuery) return title + SpotUtils.SEP + trailing;
      return title + SpotUtils.SEP + trailing + header.queryHint;
    }
    color: header.panel.secondaryColor
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideLeft

    // Painted width of the hint suffix, so the click target covers only the
    // hint (not the city title) and stays right-aligned with the elided text.
    TextMetrics {
      id: hintMetrics
      font: headerText.font
      text: header.queryHint
    }
    // Child of the Text, not the Row: a MouseArea as a direct Row child
    // triggers "Row will not function" polish loops.
    MouseArea {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      // The Text elides from the left, so on a narrow row only the right-hand
      // glyphs are visible. Cap by the Text's allotted width too: the smaller
      // of the two keeps the target inside the visible hint and off the title.
      width: Math.min(hintMetrics.advanceWidth, headerText.width)
      height: headerText.height
      enabled: header.displayQuery !== ""
      cursorShape: Qt.PointingHandCursor
      onClicked: header.clearQuery()
    }
  }
}
