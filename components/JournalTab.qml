import QtQuick
import qs.Commons

// Journal tab: rated-entry search + filter panel + rated spot list. `panel` is
// the BarWidget root; `scrollView` is the outer Flickable the root passes in for
// image gating.
Column {
  id: journalTab
  property Item panel
  property var scrollView

  visible: panel.tab === "journal"
  width: parent.width - Style.space(32)
  spacing: Style.space(10)

  // Tab chips: this view's own copy (the Explore copy scrolls away with its
  // list). Only one tab component is visible at a time, so no duplicates show.
  TabChips {
    panel: journalTab.panel
    currentTab: journalTab.panel.tab
    width: parent.width
    onPicked: function(tab) { journalTab.panel.tab = tab; journalTab.panel.collapseRow() }
  }

  Text {
    textFormat: Text.PlainText
    width: parent.width
    text: "Journal"
    color: panel.secondaryColor
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1
    font.capitalization: Font.AllUppercase
  }

  SearchField {
    id: journalInput
    panel: journalTab.panel
    placeholder: "Search name or city..."
    text: journalTab.panel.journalQuery
    height: Style.space(36)
    leftInset: Style.space(8)
    rightInset: Style.space(8)
    clearSize: 16
    onEdited: function(v) { journalTab.panel.journalQuery = v }
  }

  CityHeader {
    panel: journalTab.panel
    visible: journalTab.panel.cityKey !== ""
    count: journalTab.panel.sortedJournalData.length
    label: "rated"
    onBack: {
      journalTab.panel.applyLocationScope("", "");
      journalTab.panel.journalQuery = "";
    }
  }

  FilterPanel { panel: journalTab.panel; showNeighborhoodChips: false }

  Column {
    width: parent.width
    spacing: Style.space(8)
    ListView {
      cacheBuffer: Style.space(500)
      reuseItems: true
      width: parent.width
      height: contentHeight
      interactive: false
      model: journalTab.panel.journalModel
      delegate: SpotCard {
        panel: journalTab.panel
        scrollView: journalTab.scrollView
        readonly property var resolved: journalTab.panel.resolveSavedEntry(modelData.name, modelData.city)
        spot: resolved.spot
        cityKey: modelData.city
        fallbackName: modelData.name
        journalEntry: modelData
        starsInteractive: false
        showCity: !!modelData.city
        useHoverBg: true
        zebraStripe: 0
      }
    }
  }
  Column {
    width: parent.width
    spacing: Style.space(8)
    topPadding: Style.space(24)
    visible: journalTab.panel.sortedJournalData.length === 0
    Text {
      textFormat: Text.PlainText
      anchors.horizontalCenter: parent.horizontalCenter
      text: "\u2606"
      color: journalTab.panel.secondaryColor
      font.pixelSize: Style.fontPx(2.2)
    }
    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: journalTab.panel.ratedEntries.length > 0 ? "No entries match your filters." : "No rated spots yet."
      color: journalTab.panel.foregroundColor
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      horizontalAlignment: Text.AlignHCenter
    }
    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: "Rate a spot to see it here."
      color: journalTab.panel.secondaryColor
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
      visible: journalTab.panel.ratedEntries.length === 0
    }
  }
}
