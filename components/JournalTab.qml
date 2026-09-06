import QtQuick
import qs.Commons

// Journal tab: rated-entry search + filter panel + rated spot list. `panel` is
// the BarWidget root; `scrollView` is the outer Flickable the root passes in for
// image gating.
Column {
  id: journalTab
  property Item panel
  property var scrollView
  // Exposed for the panel's PanelKeyCatcher to `block` while typing in search.
  readonly property bool searchFieldHasFocus: searchHeader.hasFocus

  visible: panel.tab === "journal"
  width: parent.width - Style.space(32)
  spacing: Style.space(10)

  TabSearchHeader {
    id: searchHeader
    panel: journalTab.panel
    query: journalTab.panel.journalQuery
    placeholder: "Search rated spots…"
    fieldHeight: Style.space(36)
    clearSize: 16
    onEdited: function(v) { journalTab.panel.journalQuery = v }
    onDismissed: journalTab.panel.close()
  }

  CityHeader {
    panel: journalTab.panel
    visible: journalTab.panel.cityKey !== ""
    // A Column measures hidden children too, so collapse the height to 0 when
    // hidden — otherwise the panel reserves space for a header that isn't shown.
    height: visible ? implicitHeight : 0
    count: journalTab.panel.sortedJournal.length
    label: "rated"
    plural: false
    // The query sortedJournal actually filtered by.
    query: journalTab.panel.journalQuery
    onBack: {
      journalTab.panel.applyLocationScope("", "");
      journalTab.panel.journalQuery = "";
    }
    onClearQuery: journalTab.panel.journalQuery = ""
  }

  FilterPanel { panel: journalTab.panel; showNeighborhoodChips: false }

  Column {
    width: parent.width
    spacing: Style.space(8)
    ListView {
      cacheBuffer: Style.space(500)
      width: parent.width
      height: contentHeight
      interactive: false
      model: journalTab.panel.journalModel
      delegate: SpotCard {
        panel: journalTab.panel
        scrollView: journalTab.scrollView
        spot: modelData.spot
        cityKey: modelData.city
        fallbackName: modelData.name
        journalEntry: modelData.entry
        starsInteractive: false
        showCity: !!modelData.city
        useHoverBg: true
        zebraStripe: 0
      }
    }
  }
  // Empty state — "nothing rated" vs "rated but filtered to none".
  EmptyState {
    panel: journalTab.panel
    visible: journalTab.panel.sortedJournal.length === 0
    glyph: "\u2606"
    headline: journalTab.panel.ratedEntries.length > 0 ? "No entries match your filters." : "No rated spots yet."
    caption: journalTab.panel.ratedEntries.length > 0
      ? "Try a different search or clear your filters."
      : "Rate a spot to see it here."
  }
}
