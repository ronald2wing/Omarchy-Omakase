import QtQuick
import qs.Commons

// Shared hover-row chrome: a full-width 28px rounded Rectangle that fills with
// the panel's card-hover background under the cursor and emits clicked() on
// press. ListRow and FilterSheetLocationRow both wrap this and inject their own body
// through the `content` default-property alias, so the hover/click surface is
// defined in one place.
Rectangle {
  id: hoverRow
  property var panel
  signal clicked()
  // Raw row height (pre-Style.space). SearchSuggestionsDropdown reads this to
  // compute its row cap, so the metric lives here once instead of being
  // restated as a literal beside the surface metrics.
  readonly property int rowHeight: 28

  width: parent.width
  height: Style.space(hoverRow.rowHeight)
  radius: Style.cornerRadius
  color: hoverHandler.hovered ? hoverRow.panel.cardHoverBackground : "transparent"

  HoverHandler { id: hoverHandler }

  Item {
    id: body
    anchors.fill: parent
  }

  default property alias content: body.data

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: hoverRow.clicked()
  }
}
