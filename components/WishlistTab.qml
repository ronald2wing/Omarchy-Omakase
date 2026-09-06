import QtQuick
import qs.Commons

// Wishlist tab: saved-spot search + filter panel + saved spot list. `panel` is
// the BarWidget root; `scrollView` is the outer Flickable the root passes in for
// image gating.
Column {
  id: wishlistTab
  property Item panel
  property var scrollView

  visible: panel.tab === "wishlist"
  width: parent.width - Style.space(32)
  spacing: Style.space(10)

  // Tab chips: this view's own copy (the Explore copy scrolls away with its
  // list). Only one tab component is visible at a time, so no duplicates show.
  TabChips {
    panel: wishlistTab.panel
    currentTab: wishlistTab.panel.tab
    width: parent.width
    onPicked: function(tab) { wishlistTab.panel.tab = tab; wishlistTab.panel.collapseRow() }
  }

  Text {
    textFormat: Text.PlainText
    width: parent.width
    text: "Wishlist"
    color: panel.secondaryColor
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1
    font.capitalization: Font.AllUppercase
  }

  SearchField {
    id: wishlistInput
    panel: wishlistTab.panel
    placeholder: "Search saved spots..."
    text: wishlistTab.panel.wishlistQuery
    leftInset: Style.space(8)
    rightInset: Style.space(8)
    onEdited: function(v) { wishlistTab.panel.wishlistQuery = v }
  }

  CityHeader {
    panel: wishlistTab.panel
    visible: wishlistTab.panel.cityKey !== ""
    count: wishlistTab.panel.filteredWishlist.length
    label: "saved"
    onBack: {
      wishlistTab.panel.applyLocationScope("", "");
      wishlistTab.panel.wishlistQuery = "";
    }
  }

  FilterPanel { panel: wishlistTab.panel }

  Column {
    width: parent.width
    spacing: Style.space(8)
    topPadding: Style.space(24)
    bottomPadding: Style.space(24)
    visible: wishlistTab.panel.saved.length === 0
    Text {
      textFormat: Text.PlainText
      anchors.horizontalCenter: parent.horizontalCenter
      text: "\u2661"
      color: wishlistTab.panel.secondaryColor
      font.pixelSize: Style.fontPx(2.2)
    }
    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: "No saved spots yet."
      color: wishlistTab.panel.foregroundColor
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      horizontalAlignment: Text.AlignHCenter
    }
    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: "Tap the heart icon on any spot to save it."
      color: wishlistTab.panel.secondaryColor
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
    }
  }
  Column {
    width: parent.width
    spacing: Style.space(8)
    ListView {
      cacheBuffer: Style.space(500)
      reuseItems: true
      width: parent.width
      height: contentHeight
      interactive: false
      model: wishlistTab.panel.wishlistModel
      delegate: SpotCard {
        panel: wishlistTab.panel
        scrollView: wishlistTab.scrollView
        readonly property var resolved: wishlistTab.panel.resolveSavedEntry(modelData, "")
        spot: resolved.spot
        cityKey: resolved.cityKey
        fallbackName: modelData
        journalEntry: wishlistTab.panel.latestJournalFor(modelData)
        starsInteractive: true
        showCity: !!resolved.cityKey
        useHoverBg: true
        zebraStripe: 0
      }
    }
  }
  Text {
    textFormat: Text.PlainText
    width: parent.width
    horizontalAlignment: Text.AlignHCenter
    text: wishlistTab.panel.wishlistQuery ? "No saved spots match your search" : "No saved spots match your filters"
    color: wishlistTab.panel.secondaryColor
    font.pixelSize: Style.font.bodySmall
    visible: wishlistTab.panel.saved.length > 0 && wishlistTab.panel.filteredWishlist.length === 0
    topPadding: Style.space(20)
  }
}
