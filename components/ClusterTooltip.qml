import QtQuick
import qs.Commons

// Hover tooltip for one cell of the collapsed-card action cluster. Pinned
// directly above its anchor icon and centred on it: `x` is the icon's left
// edge (`scoreBlock.x + anchorItem.x`) plus half the difference between the
// icon's and the tooltip's widths, and `y` is one 4px gap above the cluster
// top (`scoreBlock.y + actionCluster.y - height - Style.space(4)`).
//
// The card-relative position is a sum over tracked properties (`scoreBlock.x/y`,
// `actionCluster.y`, and the icon's own `x`/`width`), NOT `mapToItem`:
// mapToItem is a C++ method call, so QML's dependency capture never tracks it,
// and the binding would freeze at its first (pre-layout) value, leaving the
// tooltip a row too high.
Tooltip {
  id: clusterTooltip
  property Item anchorItem
  property Item scoreBlock
  property Item actionCluster

  x: scoreBlock.x + anchorItem.x + (anchorItem.width - width) / 2
  y: scoreBlock.y + actionCluster.y - height - Style.space(4)
}
