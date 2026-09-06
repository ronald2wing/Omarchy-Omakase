import QtQuick
import qs.Commons
import "../catalog-utils.js" as CatalogUtils
import "../spot-utils.js" as SpotUtils

// Spotlight view: full-panel single-spot view opened by Surprise Me. `panel` is
// the BarWidget root; `scrollView` is the outer Flickable the root passes in for
// image gating. Search/filter/chips live in the pinned header (shared with the
// tabs); this view keeps only the back row and the card.
Column {
  id: spotlightView
  property Item panel
  property var scrollView

  // Place label for the surprise-pool breadcrumb: the active place scope's
  // display name (city → cityLabel, else state → stateNameFor, else country →
  // raw code, else ""). The city label is resolved by the panel (cityLabel)
  // because it honours a catalog-derived alias map a pure helper cannot see;
  // placeLabelFor then applies the city-beats-state-beats-country precedence.
  // Declarative so the binding engine owns the recompute; the dependency list
  // is explicit because reads inside the compute function (cityLabel) are not
  // tracked. cityLabelMap is listed because cityLabel() reads it directly.
  property string placeLabel: {
    spotlightView.panel.cityKey;
    spotlightView.panel.stateFilter;
    spotlightView.panel.countryFilter;
    spotlightView.panel.cityLabelMap;
    return CatalogUtils.placeLabelFor(
      spotlightView.panel.cityKey,
      spotlightView.panel.cityKey ? spotlightView.panel.cityLabel(spotlightView.panel.cityKey) : "",
      spotlightView.panel.stateFilter,
      spotlightView.panel.countryFilter
    );
  }

  visible: panel.spotlight
  width: parent.width
  spacing: Style.space(10)
  padding: Style.space(16)

  // Back link + pick criteria breadcrumb
  Row {
    id: backRow
    width: parent.width - panel.contentInset
    spacing: Style.space(8)
    // Width of the fixed chrome flanking the criteria summary — the Back link
    // and its hairline separator, plus the two Row gaps — so the summary width
    // is a single subtraction that cannot drift when a flanking child is added
    // or resized.
    readonly property real backRowChromeWidth: spotlightBack.width
        + backSeparator.width + 2 * spacing
    BackLink {
      id: spotlightBack
      panel: spotlightView.panel
      label: "Back to results"
      anchors.verticalCenter: parent.verticalCenter
      // Shared teardown with the Escape spotlight branch: drops the rating
      // hold, dismisses popovers, and closes the card via the notes-flush net.
      onClicked: spotlightView.panel.leaveSpotlight()
    }
    // Vertical hairline separating the Back link from the "N spots in …"
    // breadcrumb, so the link and the breadcrumb don't read as one sentence.
    Rectangle {
      id: backSeparator
      width: 1
      height: Style.space(16)
      color: spotlightView.panel.foregroundAlpha(0.2)
      anchors.verticalCenter: parent.verticalCenter
    }
    Text {
      textFormat: Text.PlainText
      // Bounded to the space left of the fixed flanks so `elide` actually
      // fires and a long place label elides instead of overflowing the
      // clipped Flickable.
      width: Math.max(0, parent.width - backRow.backRowChromeWidth)
      text: CatalogUtils.surpriseSummary(
              spotlightView.panel.surprisePoolSize,
              spotlightView.placeLabel,
              spotlightView.panel.debouncedSearchText)
      color: spotlightView.panel.secondaryColor
      font.pixelSize: Style.font.caption
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
    }
  }

  // Spot card — centered within the full-width column. A Column is a
  // positioner that manages only Y, so a fixed-width child cannot be
  // horizontally centered directly; a full-width wrapper Item (a plain
  // Item, not a positioner) is required for anchors to take effect.
  Item {
    width: parent.width - panel.contentInset
    height: spotlightCard.height

    SpotCard {
      id: spotlightCard
      panel: spotlightView.panel
      scrollView: spotlightView.scrollView
      width: Math.min(parent.width, Style.space(450))
      anchors.horizontalCenter: parent.horizontalCenter
      spot: spotlightView.panel.spotlightSpot
      cityKey: spotlightView.panel.spotlightSpot ? (spotlightView.panel.spotlightSpot._cityKey || "") : ""
      fallbackName: spotlightView.panel.spotlightSpot ? spotlightView.panel.spotlightSpot.name : ""
      starsInteractive: true
      showCity: spotlightView.panel.showsCityLabels && !!(spotlightView.panel.spotlightSpot && spotlightView.panel.spotlightSpot._cityKey)
      useHoverBg: false
      zebraStripeIndex: 0
    }
  }
}
