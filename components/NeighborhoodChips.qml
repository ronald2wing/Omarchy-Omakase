import QtQuick
import qs.Commons

// Neighborhood chip strip — shown once a city is selected.
Item {
  id: chips
  property Item panel
  // Chip strip only for short lists; the FilterBar's neighborhood dropdown
  // is the fallback when the list is too long (see showNeighborhoodChips).
  visible: panel.showNeighborhoodChips
  width: parent.width
  height: nbFlow.implicitHeight
  Flow {
    id: nbFlow
    width: parent.width
    spacing: Style.space(4)
    // Leading "All" chip clears the neighborhood filter; the list below carries
    // real neighborhoods only (the "" sentinel was removed from the options).
    PillButton {
      panel: chips.panel
      active: chips.panel.neighborhood === ""
      label: "All"
      cornerRadius: Style.cornerRadius
      padding: Style.space(10)
      fontSize: Style.font.caption
      onToggled: chips.panel.neighborhood = ""
    }
    Repeater {
      model: chips.panel.neighborhoodOptions
      delegate: PillButton {
        panel: chips.panel
        active: chips.panel.neighborhood === modelData
        label: modelData
        cornerRadius: Style.cornerRadius
        padding: Style.space(10)
        fontSize: Style.font.caption
        onToggled: chips.panel.neighborhood = modelData
      }
    }
  }
}
