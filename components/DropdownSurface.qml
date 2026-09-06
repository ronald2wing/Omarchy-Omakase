import QtQuick
import qs.Commons

// Shared scroll-capped dropdown chrome: a rounded surface Rectangle around a
// Flickable that scrolls the rows when they overflow the caller's height cap,
// with an inset Column holding the caller's rows (declared as children of this
// component). Extracted once so FilterDropdown and SearchSuggestionsDropdown
// share the clip/interactive/StopAtBounds idiom and the inset Column geometry
// in exactly one place.
//
// `maxHeight` caps the surface to the vertical space the caller has left; 0
// means uncapped. The surface color/border are overridable because the two
// callers surface differently: the filter dropdown uses the opaque popup
// surface + border, while the suggestions dropdown sits inside an already-
// filled card and passes transparent chrome.
Rectangle {
  id: surface
  // Vertical cap for the surface: the content height (plus its top/bottom
  // inset) is clamped to this when > 0, so a long list scrolls internally.
  property real maxHeight: 0
  property color surfaceColor: "transparent"
  property color surfaceBorderColor: "transparent"
  property real surfaceBorderWidth: 0
  // Raw metrics (pre-Style.space) that SearchSuggestionsDropdown reads to
  // compute its row cap: the inter-row spacing, and the surface's 8px inset
  // (used for both the horizontal x/width pad and the total vertical top+bottom
  // pad). Named here once so a metric change cannot silently mis-size the cap.
  readonly property int rowSpacing: 2
  readonly property int surfaceInset: 8
  // Caller rows land in the inset Column.
  default property alias contentData: rowColumn.data

  width: parent.width
  height: surface.maxHeight > 0
    ? Math.min(rowColumn.implicitHeight + Style.space(surface.surfaceInset), surface.maxHeight)
    : rowColumn.implicitHeight + Style.space(surface.surfaceInset)
  radius: Style.cornerRadius
  color: surface.surfaceColor
  border.color: surface.surfaceBorderColor
  border.width: surface.surfaceBorderWidth

  // `clip` keeps the rows inside the rounded surface; `interactive` is true
  // only when the content overflows so a short list never captures a drag;
  // StopAtBounds stops the scroll at the list edges.
  Flickable {
    id: flick
    anchors.fill: parent
    clip: true
    contentWidth: width
    contentHeight: rowColumn.implicitHeight
    interactive: contentHeight > height
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: rowColumn
      x: Style.space(surface.surfaceInset)
      y: Style.space(surface.surfaceInset / 2)
      width: flick.width - Style.space(surface.surfaceInset * 2)
      spacing: Style.space(surface.rowSpacing)
    }
  }
}
