import QtQuick
import qs.Commons

// PillButton with the filter-pill look baked in: the FilterBar's primary-row
// chips (Unrated/Radius/Location) and the NeighborhoodChips strip share the
// same corner radius and caption sizing, so those five sites stop restating
// the trio. `extraWidth` stays a property — the FilterBar keeps the tight 8px
// default, while the neighborhood chip strip widens it to 10px for its longer
// labels, so the difference is stated at the two sites that actually want it.
PillButton {
  id: filterPill
  cornerRadius: Style.cornerRadius
  extraWidth: Style.space(8)
  fontSize: Style.font.caption
}
