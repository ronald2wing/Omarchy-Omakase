import QtQuick
import qs.Commons
import "../catalog-utils.js" as CatalogUtils

// "Back to All cities" header row. The title (city name or "Within N km")
// is derived from root state; `label`/`count` complete the trailing count
// text ("42 spots" / "7 saved" / "3 rated") which differs per tab. Explore
// sets `plural` so the count takes the "N spots" form; the Wishlist/Journal
// tabs pass an invariant noun via `label` ("saved"/"rated"). `back` lets
// each call site reset its own query/state.
//
// `query` is the exact value the tab's list filtered by (Explore's debounced
// searchQuery, Wishlist's wishlistQuery, Journal's journalQuery). When it is
// non-blank the count line appends ` matching "…"` so a scoped search never
// reads as a broken count, and the hint is clickable to clear it via
// `clearQuery` (the call site owns the target property).
Row {
  id: header
  property Item panel
  property string label: ""
  property bool plural: false
  property int count: 0
  property string query: ""
  signal back()
  signal clearQuery()
  width: parent.width
  spacing: Style.space(8)

  // Longest query shown verbatim before the display cap kicks in. The hint
  // sits in a narrow row, so an unbounded query would push the title out of
  // alignment; the cap keeps the row's elision/layout intact.
  readonly property int queryDisplayCap: 24

  // The query as shown in the hint: trimmed, capped, ellipsized. Blank when
  // the query is blank (whitespace-only folds to no filter, so no hint).
  function displayQuery() {
    var trimmed = (header.query || "").trim();
    if (trimmed.length <= header.queryDisplayCap) return trimmed;
    return trimmed.slice(0, header.queryDisplayCap) + "…";
  }

  BackLink {
    id: headerBack
    panel: header.panel
    label: "All cities"
    onClicked: header.back()
  }
  Text {
    id: headerText
    textFormat: Text.PlainText
    anchors.verticalCenter: parent.verticalCenter
    width: header.width - headerBack.width - header.spacing
    horizontalAlignment: Text.AlignRight
    text: {
      var title = header.panel.radius > 0 ? CatalogUtils.formatRadius(header.panel.radius) : header.panel.cityLabel(header.panel.cityKey);
      // The caller owns pluralization: `plural` renders "N spots"; otherwise
      // `label` is appended verbatim ("saved"/"rated").
      var trailing = header.plural ? CatalogUtils.spotCountLabel(header.count) : CatalogUtils.countLabel(header.count, header.label);
      var shown = header.displayQuery();
      // No query -> byte-identical to the pre-hint output.
      if (!shown) return title + CatalogUtils.SEP + trailing;
      return title + CatalogUtils.SEP + trailing + " matching \"" + shown + "\"";
    }
    color: header.panel.secondaryColor
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideLeft

    // Painted width of the hint suffix, so the click target covers only the
    // hint (not the city title) and stays right-aligned with the elided text.
    TextMetrics {
      id: hintMetrics
      font: headerText.font
      text: header.displayQuery() ? " matching \"" + header.displayQuery() + "\"" : ""
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
      enabled: header.displayQuery() !== ""
      cursorShape: Qt.PointingHandCursor
      onClicked: header.clearQuery()
    }
  }
}
