import QtQuick
import qs.Commons
import "../catalog-utils.js" as CatalogUtils

// City/neighborhood/state search dropdown, floating under the Explore search
// field in the pinned header. It grows the pinned region (shrinking the list)
// rather than overlapping the FilterBar. `panel` is the BarWidget root.
Column {
  id: dropdown
  property Item panel

  width: parent.width
  spacing: 0
  // `searchSuggestionsDismissed` (a plain bool on the panel root) lets a
  // deliberate user action — Escape, the query row, or a card click — hide
  // the suggestions without clearing the query. It resets to false on the
  // next searchText change (BarWidget), so typing re-opens them.
  visible: panel.tab === "explore" && dropdown.pinnedSearchHits.length > 0 && !panel.cityKey && !panel.searchSuggestionsDismissed
  // The search index is built asynchronously (rebuildCatalogIndex) and republished
  // whole; searchMatches() is a function call, so its searchIndex /
  // states reads are not tracked. List them explicitly so the hits re-evaluate
  // when a catalog rebuild lands instead of staying stale.
  readonly property var pinnedSearchHits: {
    panel.searchText;
    panel.searchIndex;
    panel.states;
    return panel.searchMatches(panel.searchText);
  }

  // The query as shown by the query row, capped like CityHeader's hint so a
  // long query cannot break the row. Reads searchText directly (tracked) so
  // the label re-evaluates on every keystroke.
  readonly property int queryDisplayCap: 24
  readonly property string queryLabel: {
    var q = (panel.searchText || "").trim();
    return q.length > queryDisplayCap ? q.slice(0, queryDisplayCap) + "…" : q;
  }

  // Count label for a search hit, varying by type: a neighborhood hit shows its
  // parent city, a state hit is prefixed "all of", and a plain city hit only
  // leads with the folded separator.
  function hitLabel(hit) {
    if (hit.type === "neighborhood") {
      return hit.cityName + CatalogUtils.SEP + CatalogUtils.spotCountLabel(hit.count);
    }
    if (hit.type === "state") {
      return "all of " + hit.name + CatalogUtils.SEP + CatalogUtils.spotCountLabel(hit.count);
    }
    return CatalogUtils.SEP_LEAD + CatalogUtils.spotCountLabel(hit.count);
  }

  Rectangle {
    width: parent.width
    // The query row (28px + its 4px top inset) sits pinned above the capped
    // place list, so it never scrolls out of reach.
    height: Style.space(4) + queryRow.height + pinnedDropFlick.height
    radius: Style.cornerRadius
    color: panel.cardBackground
    border.color: panel.foregroundAlpha(0.1)

    // Query row — represents the query itself (magnifier + `Search "…"`).
    // Visually distinct from the place rows (`Name · N spots`): muted caption
    // color, leading magnifier glyph. Picking it only dismisses — the query is
    // already applied to the list. Mirrors ListRow's 28px height + hover.
    Rectangle {
      id: queryRow
      anchors.top: parent.top
      anchors.topMargin: Style.space(4)
      width: parent.width
      height: Style.space(28)
      radius: Style.cornerRadius
      color: queryHover ? dropdown.panel.cardHoverBackground : "transparent"
      property bool queryHover: false
      HoverHandler { onHoveredChanged: parent.queryHover = hovered }
      Row {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: Style.space(14)
        spacing: Style.space(6)
        Image {
          source: Qt.resolvedUrl("../icons/search.svg")
          width: 14
          height: 14
          anchors.verticalCenter: parent.verticalCenter
        }
        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: "Search \"" + dropdown.queryLabel + "\""
          color: dropdown.panel.secondaryColor
          font.pixelSize: Style.font.bodySmall
        }
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: dropdown.panel.searchSuggestionsDismissed = true
      }
    }

    // Scrolls the rows when the list exceeds the cap (mirrors FilterDropdown).
    // `clip` keeps them inside the rounded surface; `interactive` is off when
    // everything fits so a short list never captures a drag.
    Flickable {
      id: pinnedDropFlick
      anchors.top: queryRow.bottom
      width: parent.width
      // Cap at 6 rows (6 x 28px rows + 5 x 2px gaps + 8px inset) so a long hit
      // list scrolls internally instead of growing the pinned area unbounded.
      height: Math.min(pinnedDropList.implicitHeight + Style.space(8), Style.space(6 * 28 + 5 * 2 + 8))
      clip: true
      contentWidth: width
      contentHeight: pinnedDropList.implicitHeight
      interactive: contentHeight > height
      boundsBehavior: Flickable.StopAtBounds
      Column {
        id: pinnedDropList
        x: Style.space(8)
        y: Style.space(4)
        width: pinnedDropFlick.width - Style.space(16)
        spacing: Style.space(2)
        Repeater {
          model: dropdown.pinnedSearchHits
          delegate: ListRow {
            panel: dropdown.panel
            text: modelData.name
            active: modelData.type === "city"
            secondaryText: dropdown.hitLabel(modelData)
            leftMargin: Style.space(6)
            onClicked: {
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
}
