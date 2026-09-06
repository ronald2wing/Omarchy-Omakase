import QtQuick
import qs.Commons

// Hover tooltip pinned in place over one segment of the collapsed card's spec
// line (kind · price · courses). `x` sums the meta row's card-relative origin
// with the segment's row-relative position; `y` does the same and then centres
// vertically on the segment by half the height difference — all tracked
// properties, never `mapToItem` (see ClusterTooltip). The courses tooltip's
// full text is wider than its clipped segment, so `rightAlign` right-aligns it
// to the segment's right edge to stay inside the card; the price label is
// short and fixed, so a plain left alignment suffices.
Tooltip {
  id: metaTooltip
  property Item anchorItem
  property Item row
  property bool rightAlign: false

  x: metaTooltip.rightAlign
    ? metaTooltip.row.x + metaTooltip.anchorItem.x + metaTooltip.anchorItem.width - width
    : metaTooltip.row.x + metaTooltip.anchorItem.x
  // Vertical centre on the segment text: the segment's top edge (`row.y +
  // anchorItem.y`) plus half the height difference between the segment and this
  // tooltip. All three are tracked properties (`row.y`, `anchorItem.y`/`height`,
  // `height`), so the binding re-evaluates as the row, segment, or text change —
  // never `mapToItem`, never an anchor to a non-parent.
  y: metaTooltip.row.y + metaTooltip.anchorItem.y + (metaTooltip.anchorItem.height - metaTooltip.height) / 2
}
