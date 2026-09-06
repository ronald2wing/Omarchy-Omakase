import QtQuick
import qs.Commons

// Generic filter dropdown panel. `items` is a list of { key, label } pairs;
// the caller controls visibility via `visible`; picking a row emits picked(key).
// When `clearLabel` is non-empty a clear row is rendered above the options and
// emits picked("") — the caller's select*("") clears the scope.
//
// `sheetSpaceRemaining` is the vertical space between the sheet's top and the visible
// bottom edge (passed down by FilterSheet). The option list is capped to that
// minus this dropdown's own offset within the sheet, so a long list scrolls
// internally instead of running past the edge and getting clipped mid-row.
Column {
  id: dropdown
  property Item panel
  property var items: []
  property string clearLabel: ""
  // Space from the sheet's top to the visible bottom edge. 0 = uncapped.
  property real sheetSpaceRemaining: 0
  // Offset from the sheet's top to this dropdown's parent's top, passed down by
  // the row so the dropdown's own y within the row completes the full offset.
  property real sheetTopOffset: 0
  signal picked(string key)
  width: parent.width
  spacing: 0

  // Space from this dropdown's top to the visible bottom edge. The dropdown's
  // offset within the sheet is its own y within the row plus the row's offset
  // from the sheet's top (`sheetTopOffset`), both read reactively so the cap
  // follows the row layout when a preceding row appears or disappears.
  // Returns 0 when uncapped (the sheet reported no cap). Deliberately no floor
  // above the true space: the old 80px minimum pushed the cap past a clipped
  // Flickable's viewport and truncated the list mid-row — the list scrolls
  // internally instead. The 1px floor only keeps a row at/below the visible edge
  // from collapsing to the 0 "uncapped" sentinel (which would render the whole
  // list past the clip).
  readonly property real dropdownSpaceRemaining: {
    if (dropdown.sheetSpaceRemaining <= 0) return 0;
    var offset = dropdown.sheetTopOffset + dropdown.y;
    var space = dropdown.sheetSpaceRemaining - offset;
    return space > 0 ? space : Style.space(1);
  }

  // Opaque popup surface, shared via panel.popupBackground. DropdownSurface
  // owns the scroll-capped Rectangle/Flickable/Column idiom (clip, `interactive`
  // only when overflowing, StopAtBounds, and the inset Column geometry), capped
  // to the space actually left in the popup. The clear row + option rows are
  // declared as its children.
  DropdownSurface {
    maxHeight: dropdown.dropdownSpaceRemaining
    surfaceColor: dropdown.panel.popupBackground
    surfaceBorderColor: Color.popups.border
    surfaceBorderWidth: Style.normalBorderWidth

    // Clear row: always first, above the options. Emits the empty key so the
    // caller's select*("") clears the scope. A muted ListRow, gated by the
    // base `visible` property.
    ListRow {
      panel: dropdown.panel
      text: dropdown.clearLabel
      muted: true
      visible: dropdown.clearLabel !== ""
      onClicked: dropdown.picked("")
    }
    Repeater {
      model: items
      delegate: ListRow {
        panel: dropdown.panel
        text: modelData.label
        onClicked: dropdown.picked(modelData.key)
      }
    }
  }
}
