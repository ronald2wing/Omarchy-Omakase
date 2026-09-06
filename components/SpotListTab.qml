import QtQuick
import qs.Commons
import "../catalog-utils.js" as CatalogUtils

// Shared scaffold for the Wishlist and Journal tabs: CityHeader back-row and a
// SpotCard list + empty state. The search header and filter panel live in
// BarWidget's pinned header (outside the scroller), so they are not repeated
// here. `panel` is the BarWidget root; `scrollView` is the outer Flickable for
// image gating. One layout and one delegate serve both views via the
// parameters below.
Column {
  id: spotListTab
  property Item panel
  property var scrollView
  property string viewName: ""         // CatalogUtils.VIEW_WISHLIST | VIEW_JOURNAL; drives visible
  property string query: ""            // panel.wishlistQuery / panel.journalQuery
  property string countNoun: ""       // CityHeader count noun: "saved" | "rated"
  // Snapshot array (root.wishlistModel / journalModel) — never a reactive
  // property var whose compute can bump a tracked dependency mid-evaluation.
  // Its length drives both the CityHeader count and the empty-state visibility.
  property var listModel: []
  property string emptyGlyph: ""
  property string emptyStateHeadline: ""
  property string emptyCaption: ""
  // Both model items carry the city key as `cityKey` (wishlist: { name, spot,
  // cityKey }; journal: { name, cityKey, spot, entry }).
  property bool starsInteractive: true
  property bool showDateInPlaceRow: false

  signal queryCleared()

  readonly property bool isEmpty: spotListTab.listModel.length === 0

  // True when the collection itself has no entries (the caller's "No saved
  // spots yet." / "No rated spots yet." branch). The caller owns that string —
  // no filter or query can be the cause, so the both-active headline below must
  // never fire over it.
  readonly property bool collectionEmpty: {
    if (spotListTab.viewName === CatalogUtils.VIEW_WISHLIST) {
      spotListTab.panel.saved;
      return spotListTab.panel.saved.length === 0;
    }
    spotListTab.panel.ratedEntries;
    return spotListTab.panel.ratedEntries.length === 0;
  }

  // The empty-state headline: the caller's single-cause string (including its
  // collection-empty branch) by default, replaced with a both-causes form only
  // when a query AND a city scope are both active — the same buildEmptyHeadline
  // output, but with the real city label instead of the "" the tab files pass.
  // cityLabel is a panel function call (untracked), so cityLabelMap is listed
  // explicitly; the direct reads (query, cityKey, collectionEmpty, emptyStateHeadline)
  // are tracked on their own.
  readonly property string resolvedHeadline: {
    spotListTab.panel.cityLabelMap;
    if (!spotListTab.collectionEmpty && spotListTab.query !== "" && spotListTab.panel.cityKey !== "") {
      return CatalogUtils.buildEmptyHeadline(spotListTab.countNoun, spotListTab.query, spotListTab.panel.cityLabel(spotListTab.panel.cityKey));
    }
    return spotListTab.emptyStateHeadline;
  }

  visible: spotListTab.panel.tab === spotListTab.viewName
  width: parent.width - panel.contentInset
  spacing: Style.space(10)

  CityHeader {
    panel: spotListTab.panel
    visible: spotListTab.panel.cityKey !== ""
    // Collapse the hidden header to an explicit 0; a hidden child is not measured.
    height: visible ? implicitHeight : 0
    count: spotListTab.listModel.length
    countNoun: spotListTab.countNoun
    plural: false
    query: spotListTab.query
    onBack: {
      spotListTab.panel.selectLocationScope("", "");
      spotListTab.queryCleared();
    }
    onClearQuery: spotListTab.queryCleared()
  }

  Column {
    width: parent.width
    spacing: Style.space(8)
    ListView {
      cacheBuffer: Style.space(500)
      width: parent.width
      height: contentHeight
      interactive: false
      model: spotListTab.listModel
      delegate: SpotCard {
        panel: spotListTab.panel
        scrollView: spotListTab.scrollView
        spot: modelData.spot
        cityKey: modelData.cityKey
        fallbackName: modelData.name
        starsInteractive: spotListTab.starsInteractive
        showCity: !!modelData.cityKey
        showDateInPlaceRow: spotListTab.showDateInPlaceRow
        useHoverBg: true
        zebraStripeIndex: 0
      }
    }
  }

  EmptyState {
    panel: spotListTab.panel
    visible: spotListTab.isEmpty
    glyph: spotListTab.emptyGlyph
    headline: spotListTab.resolvedHeadline
    caption: spotListTab.emptyCaption
    // Both a query and any filter are active: clearing only one changes
    // nothing, so the action clears both in one click. The single-cause states
    // leave actionLabel empty and keep their current look.
    actionLabel: (spotListTab.query !== "" && spotListTab.panel.hasActiveFilters)
      ? CatalogUtils.EMPTY_STATE_CLEAR_ACTION_LABEL : ""
    action: function () {
      spotListTab.queryCleared();
      spotListTab.panel.clearAllFilters();
    }
  }
}
