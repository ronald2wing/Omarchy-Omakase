import QtQuick
import QtQuick.Layouts
import qs.Commons

// One 24px slot of the collapsed-card action cluster: the reserved geometry,
// the pointer-cursor click surface, and the hover tracking. A cell drops its
// glyph in as a centered child and supplies the click side effect through
// `activated`; `available` gates click and hover together, so an absent action
// keeps its slot (the five columns stay stable) but is inert. The Image-glyph
// cells (website / Maps) use ActionIcon instead — it owns the same slot for an
// `iconSource` image plus the glyph-visibility half of `available`; the Text
// cells here manage their own glyph visibility.
Item {
  id: clusterCell
  property bool available: true
  signal activated()
  readonly property alias hovered: cellHover.hovered

  Layout.alignment: Qt.AlignVCenter
  Layout.preferredWidth: Style.space(24)
  Layout.preferredHeight: Style.space(24)

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    enabled: clusterCell.available
    onClicked: clusterCell.activated()
  }
  HoverHandler { id: cellHover; enabled: clusterCell.available }
}
