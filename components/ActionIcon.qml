import QtQuick

// One 24px cell of the collapsed-card action cluster (external link / Maps).
// Composes ClusterCell — the reserved 24px slot, the pointer-cursor click
// surface, and the hover tracking — and adds only the Image glyph plus the
// glyph-visibility half of `available` (ClusterCell already gates click and
// hover on it). The slot is always reserved at its full 24px size so the five
// action icons form stable columns down the list instead of packing left; when
// the action is absent (`available` false) the glyph hides and the cell is
// inert. `activated` carries the click side effect, so the availability gate
// lives in exactly one place.
ClusterCell {
  id: actionIcon
  property string iconSource: ""
  // ClusterCell defaults `available` true (its Text-glyph cells stay active
  // unless told otherwise); an ActionIcon is opt-in, so it overrides the
  // default to false — an `iconSource` with no `available` set renders inert.
  // A plain value assignment (not a `property` redeclaration) so the base
  // cell's MouseArea/HoverHandler read this value rather than a shadowing copy.
  available: false

  Image {
    anchors.centerIn: parent
    source: Qt.resolvedUrl(actionIcon.iconSource)
    width: 13; height: 13
    visible: actionIcon.available
  }
}
