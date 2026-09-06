import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../spot-utils.js" as SpotUtils
import "../catalog-utils.js" as CatalogUtils

// The right-hand score block of a collapsed spot card: the star row, the Yelp
// pill + distance line, and the five-cell action cluster, with the hover
// tooltips that belong to each. `panel` is the BarWidget root (colors, helpers,
// actions); `spot` is the resolved spot (or null for an unresolved wishlist
// name). The block is fixed-width and anchored right by the caller's
// `width`, so stars / rating / distance / actions form one vertical scan line
// down the list and never shift between cards.
Item {
  id: block

  property Item panel
  property var spot                 // resolved spot object, or null
  property string spotName          // display + journal identity name
  property string cityKey           // city key for rate/save actions ("nyc")
  property bool starsInteractive    // permit a star click — the caller ORs the tab's collapsed quick-rate flag with the expanded state
  property real starValue           // user rating 0-5, 0 when unrated

  // Three stacked rows: stars, Yelp/distance, then the 5x24 action cluster.
  // Height is clusterTop (the cluster's top offset) plus the 24px cell, so the
  // cluster bottom sits flush with the block bottom; the 4px top margin leaves
  // 4px under the block inside the 76px collapsed card.
  readonly property real clusterTop: Style.space(44)
  height: clusterTop + Style.space(24)
  // The tooltips are children of this item, so they inherit its stacking among
  // the card's children; 3 clears the card's expand chevron (z:2) so a tooltip
  // pinned over the rightmost cluster icons is never painted beneath the
  // chevron's hover background. This matches the old tooltips (card children at
  // z:5) without changing any content ordering: the block's own glyphs never
  // overlap the chevron.
  z: 3
  anchors.right: parent.right
  anchors.rightMargin: Style.space(22)
  anchors.top: parent.top; anchors.topMargin: Style.space(4)

  // ---- Derived (bound from inputs) ----
  readonly property real yelpRating: block.spot ? block.spot._yelpRating : 0
  readonly property int yelpReviewCount: block.spot ? block.spot._yelpReviewCount : 0
  readonly property bool hasYelpUrl: !!(block.spot && block.spot.yelp_url)
  readonly property bool hasWebsite: !!(block.spot && block.spot.website)
  readonly property bool hasMaps: !!(block.spot && block.spot._mapsUrl)
  readonly property bool hasPhone: !!(block.spot && block.spot.phone)
  // Yelp's stars stand in for an unrated spot's rating; the user's rating wins
  // the moment one exists. The star row reads the committed rating (`starValue`)
  // directly — a star click commits through `rateSpot` at once, so there is no
  // staged value to mirror.
  readonly property bool usingYelpStars: !block.starValue && block.yelpRating > 0
  // Numeric user rating, always one decimal so a whole rating matches Yelp's
  // convention ("4.0", not "4").
  readonly property string starValueLabel: block.starValue.toFixed(1)
  readonly property string yelpRatingLabel: block.yelpRating.toFixed(1)
  readonly property bool isSpotSaved: { block.panel.saved; block.panel.savedByCitySet; block.panel.savedNameOnlySet; block.panel.cityAliases; return block.panel.isSaved(block.spotName, block.cityKey); }
  // Numeric home distance (km) for the display gate. `undefined` (geo-less spot
  // or no home) folds to Infinity, so the single `<= distanceDisplayMaxKm` gate
  // below hides a geo-less/no-home spot. The label is derived separately by the
  // panel, so its emptiness is not what this gate relies on.
  readonly property real spotDistanceKm: {
    var km = block.spot ? block.panel.distanceKmOrUndefined(block.spot) : undefined;
    return km === undefined ? Infinity : km;
  }
  // Distance only informs locally: a four- or five-digit figure for a spot on
  // another continent is noise in a worldwide list, so the label is suppressed
  // beyond this many kilometres. Display rule only — the distance sort and the
  // distance build are untouched.
  readonly property real distanceDisplayMaxKm: 100
  readonly property string distanceLabel: block.panel.spotDistanceLabel(block.spot)

  // Row 1 — stars + numeric value. The single star control in both card
  // states: a click commits the rating immediately via `rateSpot`, whether the
  // card is collapsed (when the tab allows it, via `starsInteractive`) or
  // expanded (the caller folds the expanded state into `starsInteractive`).
  // Unrated spots show the Yelp stars muted, no number. Hovering the muted
  // stars brightens them to full opacity and scales them up, so the row reads
  // unmistakably as "yours to set" (the pointer cursor signals the same); the
  // resting 55% still says "this is Yelp's rating, not yours yet".
  Row {
    id: starsRow
    anchors.left: parent.left
    anchors.top: parent.top; anchors.topMargin: Style.space(4)
    spacing: Style.space(4)
    StarRating {
      id: stars
      panel: block.panel
      value: Math.round(block.usingYelpStars ? block.yelpRating : (block.starValue || 0))
      interactive: block.starsInteractive
      opacity: block.usingYelpStars ? (stars.hovered ? 1.0 : 0.55) : 1.0
      // The 55% → 100% brightening alone is subtle at this size, so hover
      // adds a small scale to make the "yours to set" cue unmistakable. The
      // resting appearance (55% opacity, unscaled) is untouched, and the scale
      // is gated to the unrated case — a user rating already reads as
      // interactive at full opacity.
      scale: block.usingYelpStars && stars.hovered ? 1.12 : 1.0
      // A star click is a commit now (no Save), so it sends the rating plus the
      // spot's current journal notes — the IPC `rate` call needs both. Read the
      // notes at click time from the journal, never a captured value.
      onPicked: (stars) => {
        var e = block.panel.latestJournalFor(block.spotName);
        var notes = (e && e.notes) || "";
        block.panel.rateSpot(block.spotName, String(stars), notes, block.cityKey);
      }
    }
    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      visible: block.starValue > 0
      text: block.starValueLabel
      color: panel.foregroundColor
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  // Row 2 — Yelp pill + distance.
  Row {
    id: yelpRow
    anchors.left: parent.left
    anchors.top: parent.top; anchors.topMargin: Style.space(22)
    spacing: Style.space(6)
    // Yelp rating is plain data, not a filter chip, so it renders as a quiet
    // inline badge: muted text on a faint neutral background. The accent is
    // reserved for controls (active chips, links, action pills). It is also
    // the card's single Yelp affordance — clicking it opens the spot's Yelp
    // page (the expanded card no longer repeats the action), so the pill
    // gains a pointer cursor and a click only when a `yelp_url` exists, plus
    // an accent hover tint so it reads as a link rather than static data.
    Rectangle {
      id: yelpPill
      visible: block.yelpRating > 0
      width: yelpRateRow.implicitWidth + Style.space(10)
      height: Style.space(18)
      radius: Style.space(9)
      // Accent tint on hover marks the pill as clickable; gated on a real
      // `yelp_url` so a non-link pill never advertises a hover it cannot
      // honour, and the fixed size means the colour swap cannot shift the card.
      color: (yelpHover.hovered && block.hasYelpUrl) ? panel.accentTint : panel.foregroundAlpha(0.08)
      Row {
        id: yelpRateRow
        anchors.centerIn: parent
        spacing: Style.space(3)
        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: block.yelpRatingLabel
          color: panel.secondaryColor; font.pixelSize: Style.font.caption
        }
        // Review count is a subordinate detail: a size step down and the
        // muted secondary color, so "4.4 (2746)" does not read as one number.
        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          visible: block.yelpReviewCount > 0
          text: "(" + block.yelpReviewCount + ")"
          color: panel.foregroundAlpha(0.55)
          font.pixelSize: Style.font.caption - 1
        }
      }
      HoverHandler { id: yelpHover }
      MouseArea {
        anchors.fill: parent
        cursorShape: block.hasYelpUrl ? Qt.PointingHandCursor : Qt.ArrowCursor
        enabled: block.hasYelpUrl
        onClicked: { if (block.spot && block.spot.yelp_url) panel.openUrl(block.spot.yelp_url) }
      }
    }
    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      visible: block.spotDistanceKm <= block.distanceDisplayMaxKm
      text: block.distanceLabel
      color: panel.secondaryColor
      font.pixelSize: Style.font.caption
    }
  }

  // Row 3 — action cluster: five 24px touch targets (save heart / external
  // link / Maps / Copy / phone) with no gap. The glyphs are centered in each
  // cell, so the glyph-to-glyph rhythm stays 24px while every target clears
  // the 24x24 minimum. Five cells total exactly the score-block width, so the
  // cluster spans the block and the heart keeps the same left edge as the
  // stars and Yelp rows above it.
  RowLayout {
    id: actionCluster
    z: 2
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top; anchors.topMargin: block.clusterTop
    spacing: 0

    // Heart — save toggle. Accent marks the saved (active) state. It is the
    // one cell whose glyph swaps shape, so it uses ClusterCell (a child glyph)
    // rather than ActionIcon (a fixed Image).
    ClusterCell {
      id: heartItem
      onActivated: panel.toggleSaved(block.spotName, block.cityKey)
      Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: block.isSpotSaved ? "\u2665" : "\u2661"
        color: block.isSpotSaved ? panel.accentColor : panel.secondaryColor
        font.pixelSize: Style.font.iconLarge
      }
    }

    // External link — opens the spot's website.
    ActionIcon {
      id: websiteItem
      iconSource: "../icons/external-link.svg"
      available: block.hasWebsite
      onActivated: { if (block.spot) panel.openUrl(block.spot.website) }
    }
    // Maps — opens the spot in Google Maps.
    ActionIcon {
      id: mapsItem
      iconSource: "../icons/map-pin.svg"
      available: block.hasMaps
      onActivated: { if (block.spot && block.spot._mapsUrl) panel.openUrl(block.spot._mapsUrl) }
    }
    // Copy — copies the formatted spot text to the clipboard, with a brief
    // "Copied" confirmation. The transient feedback state lives in
    // CopyFeedback (shared with the phone action below); this cell keeps only
    // its glyph and the copy action.
    ClusterCell {
      id: copyItem
      onActivated: {
        copyFeedback.flash()
        var clipboardText = SpotUtils.buildSpotClipboardText(block.spot, block.spotName, panel.cityLabel(block.cityKey)) + "\n\nvia Omakase — " + panel.repoUrl
        panel.copyToClipboard(clipboardText)
      }
      CopyFeedback { id: copyFeedback; panel: block.panel; restingLabel: "Copy" }
      CopyGlyph {
        panel: block.panel
        feedback: copyFeedback
        restingGlyph: "\uf0c5"
      }
    }

    // Phone — the cluster's fifth action. Dials the spot's number when a
    // `tel:` handler is registered, copies it when not. The glyph stays the
    // phone glyph either way (the action concerns the phone number); only the
    // tooltip label switches on `telHandlerAvailable` ("Call" vs "Copy
    // number" — a binding, so it tracks the probe), while the dial-vs-copy
    // branch below reads the probe at click time, never a captured value.
    // Sharing the Copy glyph made the two cells look identical while doing
    // different things, so the phone keeps its own glyph. The copy branch
    // shares CopyFeedback with the Copy icon so both signal a successful copy
    // the same way. Inert (glyph hidden, no click/hover) when the spot has no
    // phone, so the five-cell layout stays stable.
    ClusterCell {
      id: phoneItem
      available: block.hasPhone
      onActivated: {
        if (!(block.spot && block.spot.phone)) return;
        // Read the stored probe result at click time (never a captured
        // closure): with a tel: handler, dial (openUrl guards the scheme);
        // without one, copy the number and flash the confirmation.
        if (panel.telHandlerAvailable) {
          panel.openUrl("tel:" + block.spot.phone);
        } else {
          phoneFeedback.flash()
          panel.copyToClipboard(String(block.spot.phone));
        }
      }
      CopyFeedback { id: phoneFeedback; panel: block.panel; restingLabel: CatalogUtils.phoneActionLabel(panel.telHandlerAvailable) }
      CopyGlyph {
        panel: block.panel
        feedback: phoneFeedback
        restingGlyph: "\uf095"
        visible: block.hasPhone
      }
    }
  }

  // Yelp-vs-user tooltip; must sit beside the star row (the block's top row, so
  // above clips past the card and below sits under the pointer).
  Tooltip {
    id: starsTooltip
    // Both a user and a Yelp rating must exist to compare; `!usingYelpStars`
    // also holds for a user rating with no Yelp rating, so it is not equivalent.
    visible: stars.hovered && block.starValue > 0 && block.yelpRating > 0
    x: -width - Style.space(6)
    y: starsRow.y
    panel: block.panel
    text: "Yelp " + block.yelpRatingLabel + SpotUtils.SEP + "Your rating " + block.starValueLabel
  }

  // Hover tooltip for the Yelp rating pill: names the rating and gives the bare
  // review count an explicit unit. The count suffix mirrors the pill's own
  // label (`(288)` only when the count is present) and handles the singular, so
  // the two can never disagree. Pinned above the pill, centred on it, via the
  // same tracked-property sums as the cluster tooltips.
  Tooltip {
    id: yelpTooltip
    visible: yelpHover.hovered && block.yelpRating > 0
    x: yelpPill.x + (yelpPill.width - width) / 2
    y: yelpRow.y - height - Style.space(4)
    panel: block.panel
    text: "Yelp " + block.yelpRatingLabel +
          (block.yelpReviewCount > 0
            ? SpotUtils.SEP + block.yelpReviewCount + (block.yelpReviewCount === 1 ? " review" : " reviews")
            : "")
  }

  // Hover tooltips for the collapsed-card action cluster. Each is a
  // ClusterTooltip pinned above its own icon; the positioning math and the
  // mapToItem-avoidance rationale live there, once, not per tooltip.
  ClusterTooltip {
    id: saveTooltip
    panel: block.panel
    scoreBlock: block
    actionCluster: actionCluster
    anchorItem: heartItem
    text: block.isSpotSaved ? "Saved" : "Save"
    visible: heartItem.hovered
  }
  ClusterTooltip {
    id: websiteTooltip
    panel: block.panel
    scoreBlock: block
    actionCluster: actionCluster
    anchorItem: websiteItem
    text: "Open website"
    visible: websiteItem.hovered
  }
  ClusterTooltip {
    id: mapsTooltip
    panel: block.panel
    scoreBlock: block
    actionCluster: actionCluster
    anchorItem: mapsItem
    text: "Open in Maps"
    visible: mapsItem.hovered
  }
  ClusterTooltip {
    id: copyTooltip
    panel: block.panel
    scoreBlock: block
    actionCluster: actionCluster
    anchorItem: copyItem
    text: copyFeedback.label
    visible: copyItem.hovered
  }
  ClusterTooltip {
    id: phoneTooltip
    panel: block.panel
    scoreBlock: block
    actionCluster: actionCluster
    anchorItem: phoneItem
    text: phoneFeedback.label
    visible: phoneItem.hovered
  }
}
