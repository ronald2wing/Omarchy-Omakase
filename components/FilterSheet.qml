import QtQuick
import qs.Commons
import "../catalog-utils.js" as CatalogUtils

// Floating filter sheet anchored under the Filters button. Holds the rarely-used
// location scopes (city/state/country/neighborhood). The Radius pill lives in
// the primary FilterBar row, and the Clear all filters action lives in the
// active-filter token row there. Floats like FilterDropdown so it never grows
// the pinned header (see FilterPanel) — the header stays fixed and the sheet
// paints over the cards below it.
//
// Each location row toggles the shared `panel.openDropdown`; the matching
// FilterDropdown renders directly beneath its row, inside the sheet, so the
// option list grows the floating surface instead of the layout column.
Rectangle {
  id: sheet
  property Item panel

  width: Style.space(260)
  height: sheetCol.implicitHeight + Style.space(16)
  radius: Style.cornerRadius
  // Opaque popup surface, shared via panel.popupBackground.
  color: panel.popupBackground
  border.color: Color.popups.border
  border.width: Style.normalBorderWidth

  // One upward walk of the sheet's ancestor chain, captured as an array from
  // the sheet to the topmost item (the popup card — the only ancestor whose
  // parent is the window's content item and which carries the popup's real
  // height; `panel` is the bar-widget root whose height is just the bar icon).
  // The three boundary consumers derive from this single record instead of each
  // re-walking `parent`: `popupCard` is the last element, `clipBoundary` the
  // nearest clipping ancestor below it, `sheetTopInBoundary` the summed `y` up
  // to that boundary.
  readonly property var ancestorChain: {
    var chain = [];
    var popupCard = sheet;
    while (popupCard.parent && popupCard.parent.parent) popupCard = popupCard.parent;
    var item = sheet;
    while (item) {
      chain.push(item);
      if (item === popupCard) break;
      item = item.parent;
    }
    return chain;
  }
  readonly property Item popupCard: sheet.ancestorChain[sheet.ancestorChain.length - 1]
  // The nearest ancestor that clips its content. In the Spotlight mount the
  // sheet hangs inside the outer Flickable (clip: true), whose viewport bottom
  // is the real visible boundary — shorter than the card whenever the tab
  // scrolls or a short tab hugs the panel. In Explore, Wishlist, and Journal
  // the sheet hangs off the pinned header, a sibling of that Flickable, so
  // nothing clips between the sheet and the popup card and this stays null.
  readonly property Item clipBoundary: {
    for (var index = 1; index < sheet.ancestorChain.length - 1; index++) {
      if (sheet.ancestorChain[index].clip === true) return sheet.ancestorChain[index];
    }
    return null;
  }
  // The sheet's top relative to the clipping boundary (or the popup card when
  // there is none), summed from the reactive `y` of each ancestor. mapToItem is
  // not a tracked dependency, so a binding built on it would go stale when the
  // FilterBar's height changes (the active-filter summary line appearing or
  // disappearing). Walking through the Flickable's contentItem includes its
  // -contentY offset, so a scrolled tab still measures the true space.
  readonly property real sheetTopInBoundary: {
    var boundary = sheet.clipBoundary || sheet.popupCard;
    if (!boundary) return 0;
    var top = 0;
    for (var index = 0; index < sheet.ancestorChain.length; index++) {
      if (sheet.ancestorChain[index] === boundary) break;
      top += sheet.ancestorChain[index].y;
    }
    return top;
  }
  // Vertical space between the sheet's top and the visible bottom edge (the
  // clipping boundary, or the popup card's bottom when nothing clips), minus a
  // small margin. Each FilterDropdown caps its option list to this minus its own
  // offset within the sheet, so no option row can run past the visible edge.
  // 0 means uncapped (no boundary). Deliberately no floor: the old 120px minimum
  // pushed the cap past a clipped Flickable's viewport and truncated the list
  // mid-row — against a short tab the list scrolls internally instead
  // (DropdownSurface).
  readonly property real popupSpaceRemaining: {
    var boundary = sheet.clipBoundary || sheet.popupCard;
    if (!boundary) return 0;
    return Math.max(0, boundary.height - sheet.sheetTopInBoundary - Style.space(8));
  }

  // The four location rows, as a spec array the Repeater below instantiates.
  // Each entry carries only the per-row static config (label/placeholder/name);
  // the reactive value/items/visibility are computed in the delegate from the
  // `dropdownName`, and `pickLocation` dispatches the pick on it too — so adding
  // a row means one spec entry plus one branch in pickLocation, never a fifth
  // copy of the whole prop block.
  readonly property var locationRowSpecs: [
    { label: "City",         placeholder: "All cities",        dropdownName: "city" },
    { label: "State",        placeholder: "All states",        dropdownName: "state" },
    { label: "Country",      placeholder: "All countries",     dropdownName: "country" },
    { label: "Neighborhood", placeholder: "All neighborhoods", dropdownName: "neighborhood" }
  ]

  // Dispatch a dropdown pick to the panel selector named by `dropdownName`.
  // The neighborhood pick passes the selected city key so the two scopes stay
  // together (a neighborhood always belongs to its city).
  function pickLocation(dropdownName, key) {
    if (dropdownName === "city") sheet.panel.selectCity(key);
    else if (dropdownName === "state") sheet.panel.selectState(key);
    else if (dropdownName === "country") sheet.panel.selectCountry(key);
    else if (dropdownName === "neighborhood") sheet.panel.selectNeighborhood(key, sheet.panel.cityKey);
  }

  Column {
    id: sheetCol
    anchors.left: parent.left; anchors.leftMargin: Style.space(8)
    anchors.right: parent.right; anchors.rightMargin: Style.space(8)
    anchors.top: parent.top; anchors.topMargin: Style.space(8)
    spacing: Style.space(2)

    Repeater {
      model: sheet.locationRowSpecs
      delegate: FilterSheetLocationRow {
        panel: sheet.panel
        label: modelData.label
        // The reactive fields read the panel's tracked filter state directly in
        // this binding body (never through a helper, whose reads QML would not
        // track), dispatching on the row's dropdownName.
        value: {
          var name = modelData.dropdownName;
          if (name === "city") return sheet.panel.cityLabel(sheet.panel.cityKey);
          if (name === "state") return sheet.panel.stateFilter !== "" ? CatalogUtils.stateNameFor(sheet.panel.stateFilter) : "";
          if (name === "country") return sheet.panel.countryFilter;
          return sheet.panel.neighborhood;
        }
        placeholder: modelData.placeholder
        dropdownName: modelData.dropdownName
        items: {
          var name = modelData.dropdownName;
          if (name === "city") return sheet.panel.cityFilterItems;
          if (name === "state") return sheet.panel.stateFilterItems;
          if (name === "country") return sheet.panel.countryFilterItems;
          return sheet.panel.neighborhoodFilterItems;
        }
        // City always opens the option list on click; the others clear a set
        // value, so state/country also hide the dropdown while a value is set.
        opensOnClick: modelData.dropdownName === "city"
        dropdownAllowed: {
          var name = modelData.dropdownName;
          if (name === "state") return sheet.panel.stateFilter === "";
          if (name === "country") return sheet.panel.countryFilter === "";
          return true;
        }
        // Neighborhood only when the selected city has neighborhoods worth
        // filtering by.
        visible: modelData.dropdownName !== "neighborhood" || sheet.panel.hasNeighborhoodFilter
        sheetSpaceRemaining: sheet.popupSpaceRemaining
        onPicked: function(key) { sheet.pickLocation(modelData.dropdownName, key) }
      }
    }
  }
}
