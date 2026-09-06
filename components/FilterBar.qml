import QtQuick
import qs.Commons
import "../catalog-utils.js" as CatalogUtils
import "../spot-utils.js" as SpotUtils

// Primary filter row: kind segment, sort control, Unrated-only toggle, the
// Radius cycle, and the Location button that opens the location
// sheet. The rarely-used location scopes live in FilterSheet; the active ones
// surface here as a wrapped line of clickable tokens that remove their filter.
// Reads panel.* filter state directly; the neighborhood chip strip stays
// per-tab.
Item {
  id: filterBar
  property Item panel
  width: parent.width
  height: barColumn.implicitHeight

  // The kind segment's options, one named definition so the segmented control's
  // divider/active-cell boundary tests derive from the list length instead of a
  // literal count — adding a kind cannot silently break the divider logic.
  // Order is the render order. The kind keys live in one list and are mapped to
  // their labels, so a key can't drift from the kindLabelFor argument it names.
  readonly property var kindKeys: ["ayce", "discount", "omakase"]
  readonly property var kindOptions: [
    { key: CatalogUtils.KIND_FILTER_ALL, label: "All" }
  ].concat(filterBar.kindKeys.map(function (kind) {
    return { key: kind, label: CatalogUtils.kindLabelFor(kind) };
  }))

  // Active-filter tokens, one per currently-set filter, in a fixed order
  // (city, state, country, neighborhood, kind, radius, unrated). Rebuilt as a
  // plain snapshot array whenever any filter input changes — the list-model
  // snapshot pattern, never a reactive `property var` binding whose compute
  // could re-enter. Each entry is { text, clearAction }; `clearAction` carries the exact
  // removal action, so a location token clears the whole location scope
  // (neighborhood rides on city, so dropping the city must also drop its
  // neighborhoods) while the radius token clears radius alone.
  property var activeTokens: []

  // The one location-scope removal shared by the four location tokens: dropping
  // any of city/state/country/neighborhood clears the whole scope (neighborhood
  // rides on city), so the four clearActions point at this single function
  // instead of four identical closures. The body delegates to the root's
  // clearLocationScopeFilters — the same setLocationScopes("", "") seam every
  // clear entry point routes through — so the scope set lives in one place.
  // (A location scope and the radius are mutually exclusive, so the radius is
  // already 0 here and the keep-radius seam is equivalent.)
  function clearLocationScope() { filterBar.panel.clearLocationScopeFilters(); }

  function rebuildActiveTokens() {
    var tokens = [];
    var p = filterBar.panel;
    function pushToken(text, action) {
      tokens.push({ text: text, clearAction: action });
    }
    if (p.cityKey !== "") {
      pushToken(p.cityLabel(p.cityKey), filterBar.clearLocationScope);
    }
    if (p.stateFilter !== "") {
      pushToken(CatalogUtils.stateNameFor(p.stateFilter), filterBar.clearLocationScope);
    }
    if (p.countryFilter !== "") {
      pushToken(p.countryFilter, filterBar.clearLocationScope);
    }
    if (p.neighborhood !== "") {
      pushToken(p.neighborhood, filterBar.clearLocationScope);
    }
    if (p.kindFilter !== CatalogUtils.KIND_FILTER_ALL) {
      pushToken(CatalogUtils.kindLabelFor(p.kindFilter), function () { filterBar.panel.kindFilter = CatalogUtils.KIND_FILTER_ALL; });
    }
    if (p.radius > 0) {
      pushToken(CatalogUtils.radiusLabel(p.radius), function () { filterBar.panel.radius = 0; });
    }
    if (p.unratedOnly) {
      pushToken("Unrated", function () { filterBar.panel.unratedOnly = false; });
    }
    filterBar.activeTokens = tokens;
  }

  Component.onCompleted: filterBar.rebuildActiveTokens()

  // Every filter-state change rebuilds the token summary. QML's Connections has
  // no wildcard handler, so each of the seven filters names one line routing to
  // the single shared `rebuildActiveTokens`; an eighth filter input adds one
  // line here (plus its token branch above). cityLabelMap is deliberately
  // absent: it is a derived memo cache for cityLabel, not a filter, and the
  // city token's label is a pure function of cityKey (cityLabelFor), so a cache
  // rebuild can never change it.
  Connections {
    target: filterBar.panel
    function onCityKeyChanged() { filterBar.rebuildActiveTokens() }
    function onStateFilterChanged() { filterBar.rebuildActiveTokens() }
    function onCountryFilterChanged() { filterBar.rebuildActiveTokens() }
    function onNeighborhoodChanged() { filterBar.rebuildActiveTokens() }
    function onKindFilterChanged() { filterBar.rebuildActiveTokens() }
    function onRadiusChanged() { filterBar.rebuildActiveTokens() }
    function onUnratedOnlyChanged() { filterBar.rebuildActiveTokens() }
  }

  // The Location chip's right/bottom edge in FilterBar coordinates, so
  // FilterPanel can anchor the floating sheet to the chip that opens it. The
  // chip's x/y are relative to its Flow, the Flow's x/y to barColumn, and
  // barColumn's x/y to FilterBar — all reactive properties, so summing them
  // tracks the chip's true position without mapToItem (which QML never tracks).
  readonly property real filtersChipRight: barColumn.x + primaryChipsFlow.x + filtersChip.x + filtersChip.width
  readonly property real filtersChipBottom: barColumn.y + primaryChipsFlow.y + filtersChip.y + filtersChip.height

  Column {
    id: barColumn
    width: parent.width
    spacing: Style.space(6)

    Flow {
      id: primaryChipsFlow
      width: parent.width
      spacing: Style.space(4)

      KindSegment {
        panel: filterBar.panel
        options: filterBar.kindOptions
      }

      // Hairline separating the type segment from the toggles/sort group.
      Rectangle {
        width: 1
        height: Style.space(16)
        color: filterBar.panel.foregroundAlpha(0.2)
      }

      FilterPill {
        panel: filterBar.panel
        // The Journal tab holds only rated entries, so the unrated predicate can
        // never be meaningful there — and a stale `unratedOnly` left over from
        // another view must not blank it (passesFilters ignores unratedOnly on
        // Journal). Hide the toggle rather than show a dead control.
        visible: filterBar.panel.tab !== CatalogUtils.VIEW_JOURNAL
        label: "Unrated"
        active: filterBar.panel.unratedOnly
        onToggled: {
          filterBar.panel.unratedOnly = !filterBar.panel.unratedOnly;
          filterBar.panel.openSheet = false;
        }
      }

      SortChip {
        panel: filterBar.panel
      }

      // Radius cycle (off -> 5 -> 10 -> 20 km). Lives in the primary row so the
      // radius is always reachable; the label carries the current value and the
      // pill fills when a radius is set. Radius is authoritative: setting one
      // clears the other location scopes but keeps the radius just set. The
      // short "5 km" form keeps the row on one line — the old "Within 5 km"
      // pushed "Location" onto a second line.
      FilterPill {
        panel: filterBar.panel
        label: filterBar.panel.radius > 0 ? filterBar.panel.radius + SpotUtils.KM_SUFFIX : "Radius"
        active: filterBar.panel.radius > 0
        onToggled: {
          filterBar.panel.radius = CatalogUtils.nextRadiusStep(filterBar.panel.radius);
          if (filterBar.panel.radius > 0) filterBar.panel.clearLocationScopeFilters();
          filterBar.panel.openSheet = false;
        }
      }

      // Location button — opens the location sheet. Active when any sheet
      // filter is set, so the primary row still signals hidden state.
      FilterPill {
        id: filtersChip
        panel: filterBar.panel
        label: "Location"
        active: filterBar.panel.hasSheetFilters
        onToggled: filterBar.panel.openSheet = !filterBar.panel.openSheet
      }
    }

    // Active-filters summary: one wrapped line of clickable tokens, each
    // removing its own filter, plus a Clear action. Hidden when nothing is set.
    Flow {
      width: parent.width
      spacing: Style.space(4)
      visible: filterBar.activeTokens.length > 0

      Repeater {
        model: filterBar.activeTokens
        delegate: FilterToken {
          panel: filterBar.panel
          text: modelData.text
          onCleared: modelData.clearAction()
        }
      }

      // Clear — clears every filter (kind, unratedOnly, location, radius) via
      // the shared clearAllFilters. Sort is a view preference, not a filter, so
      // it stays put. A plain text button, not a token: clearing is fully
      // reversible, so it reads as a secondary action, not a destructive one,
      // and dropping the chip outline keeps it visually distinct from the
      // active-filter tokens.
      Text {
        textFormat: Text.PlainText
        height: Style.space(20)
        verticalAlignment: Text.AlignVCenter
        text: "Clear all filters"
        color: filterBar.panel.secondaryColor
        font.pixelSize: Style.font.caption
        font.bold: true
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: filterBar.panel.clearAllFilters()
        }
      }
    }
  }
}
