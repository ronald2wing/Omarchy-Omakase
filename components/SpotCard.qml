import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import "../spot-utils.js" as SpotUtils

// One spot row: cover photo, a two-column body (identity left, score block
// right), and the expandable rating editor. `panel` is the BarWidget root
// (colors, helpers, actions); `scrollView` is the outer Flickable used to gate
// the remote image fetch on proximity to the visible area.
//
// The collapsed card is deliberately two columns so ratings/price/distance
// form a vertical scan line down the list: the left column carries identity
// (name, kind/price/courses, place) and the right column is a fixed-width
// score block (stars, Yelp badge, distance, actions) that never shifts between
// cards. All actions (save heart / link / Maps / Copy) live in one cluster in
// the score block, beneath the Yelp/distance line.
Rectangle {
  id: card

  property Item panel
  property var scrollView

  // ---- Inputs (set by delegate) ----
  property var spot                 // resolved spot object, or null (unresolved wishlist name)
  property string cityKey           // city key for filtering ("nyc")
  property string fallbackName      // display name when spot is null
  property var journalEntry         // { rating, notes, timestamp } or null
  property bool starsInteractive    // click stars to quick-rate?
  property bool showCity            // show city label?
  property bool useHoverBg          // use hover bg instead of zebra
  property int zebraStripe          // 0 or 1 for zebra striping (ignored when hover)
  property bool hover: false

  // ---- Derived (bound from inputs) ----
  readonly property string name: spot && spot.name ? spot.name : fallbackName
  readonly property string cityLabel: panel.cityLabel(cityKey)
  readonly property string spotState: spot ? (spot.state || "") : ""
  readonly property string spotNeighborhood: spot ? (spot.neighborhood || "") : ""
  // Street line for the place row (`address`, else display_address[0], else "").
  readonly property string spotAddress: spot ? SpotUtils.streetAddress(spot) : ""
  readonly property string spotDistanceLabel: panel.spotDistanceLabel(spot)
  // "City, ST" for the hover tooltip. City is omitted when the list is already
  // scoped to one city (showCity false), leaving just the state.
  readonly property string placeCityState: {
    var parts = [];
    if (card.showCity && card.cityKey) parts.push(card.cityLabel);
    if (card.spotState) parts.push(card.spotState);
    return parts.join(", ");
  }
  // Place-row city segment: the city name alone (no ", ST"). When the list is
  // already scoped to one city (showCity false) the city is redundant, so the
  // state stands in for it — the row never loses its trailing segment.
  readonly property string placeCitySegment: (card.showCity && card.cityKey) ? card.cityLabel : card.spotState
  // Street address is shown only when the state stands in for the city (scoped
  // list). In the unscoped case the city label's 60px floor squeezes the
  // address to an unreadable stub, so the segment is hidden and the line reads
  // "neighborhood · City"; the full address stays in the hover tooltip. The
  // gate mirrors `placeCitySegment`'s so the two can never disagree.
  readonly property bool scopedToCity: !(card.showCity && card.cityKey)
  readonly property real yelpRating: spot ? spot._yelpRating : 0
  readonly property int yelpReviewCount: spot ? spot._yelpReviewCount : 0
  readonly property string yelpPrice: spot ? spot._yelpPrice : ""
  readonly property bool isClosed: spot ? spot._isClosed : false
  readonly property bool canBook: spot ? spot._canBook : false
  readonly property string imageUrl: spot ? spot._imageUrl : ""
  readonly property string kind: spot ? spot._spotKind : ""
  readonly property string kindLabel: card.kind === "discount" ? "Discount" : (card.kind === "omakase" ? "Omakase" : "")
  readonly property real starValue: journalEntry && journalEntry.rating ? journalEntry.rating : 0
  readonly property bool expanded: panel.expandedSpotName === card.name
  readonly property bool hasWebsite: !!(spot && spot.website)
  readonly property bool hasMaps: !!(spot && spot._mapsUrl)
  readonly property bool hasNeighborhood: !!(spot && spot.neighborhood)
  readonly property string courses: spot ? spot._courses : ""
  readonly property string priceLabel: spot ? spot._priceLabel : ""
  readonly property bool saved: { panel.saved; return panel.isSaved(name); }
  readonly property string visitDate: journalEntry ? SpotUtils.formatDate(journalEntry.timestamp) : ""
  readonly property bool showYelpStars: !card.starValue && card.yelpRating > 0
  // Numeric user rating for the score block, always one decimal so a whole
  // rating matches Yelp's convention ("4.0", not "4").
  readonly property string starValueLabel: card.starValue.toFixed(1)
  // Segment visibility gates for the place row. Each is the exact condition a
  // segment renders under and drives `visible` only — a hidden item in a
  // RowLayout contributes no width or spacing, so gating Layout.* hints on the
  // same flag is dead code. `scopedToCity` (above) is the scoped-list
  // eligibility gate; these are the concrete render gates.
  readonly property bool showVisitDate: card.visitDate !== ""
  readonly property bool showNeighborhood: card.visitDate === "" && card.hasNeighborhood
  readonly property bool showStreetAddress: card.visitDate === "" && card.scopedToCity && card.spotAddress !== ""
  readonly property bool showMetaCity: card.placeCitySegment !== ""
  // Price shown on line 2: the curated price, else the Yelp price bucket.
  readonly property string line2Price: card.priceLabel || card.yelpPrice

  // Left inset for the identity column. Always reserves the photo slot so
  // cards with and without images align their text identically.
  readonly property real titleLeft: Style.space(14) + Style.space(48) + Style.space(10)
  // Fixed score-block width — identical on every card so the scan line holds.
  readonly property real scoreBlockWidth: Style.space(96)
  // Bounded width for the identity lines. RowLayout does not clip, so a line
  // anchored only on the right would let its non-fillWidth children overflow
  // under the score block (declared later, so it paints on top). The two rows
  // carry `clip: true` as a backstop; the name line just elides. The place
  // row owns the full left width now that the action cluster lives in the
  // score block.
  readonly property real leftWidth: card.width - card.titleLeft - card.scoreBlockWidth - Style.space(22) - Style.space(8)

  // Viewport-gated remote image. The list IS virtualized — ExploreTab is a
  // ListView with reuseItems and a 500px cacheBuffer, so only ~20 delegates
  // instantiate at once, not the ~88-176 a non-virtualized list would. The
  // gate still pays off: those delegates (plus the buffer's) would each fire a
  // Yelp CDN fetch as they enter the buffer, and a model reset re-instantiates
  // the whole window. The model is a plain JS-array snapshot (`exploreModel`,
  // reassigned via onPagedSpotsChanged), and a plain-array model resets every
  // delegate on reassignment — which is why it is snapshotted so reassignment
  // happens only on a real filter/search/window change.
  // `imageNearViewport` is true while the card is within `imagePreloadMargin`
  // of the outer Flickable's viewport, so the fetch is deferred until the card
  // approaches the viewport and the monogram placeholder shows otherwise.
  //
  // The card's position in the Flickable is `parentOffsetY + card.y`, where
  // `parentOffsetY` is the parent's origin in Flickable coordinates. The
  // parent does not move during scroll, so `parentOffsetY` is computed once
  // per card instead of walking the parent chain with `mapToItem` on every
  // scroll frame.
  //
  // The binding reads `scrollView.imageWindowStart` (a coarse scroll bucket)
  // rather than `scrollView.contentY`, so it re-evaluates only when the bucket
  // changes — not on every scroll frame. Reading `contentY` here made every
  // live card re-evaluate its binding per frame, which was the dominant scroll
  // cost. The bucket is a few card heights wide, so the window still advances
  // smoothly enough that images load before they scroll into view.
  readonly property real imagePreloadMargin: Style.space(300)
  readonly property real parentOffsetY: card.parent ? card.parent.mapToItem(scrollView, 0, 0).y : 0
  readonly property bool imageNearViewport: {
    var bucketStart = scrollView.imageWindowStart * card.panel.imageBucketHeight;
    var scrollViewY = card.parentOffsetY + card.y - bucketStart;
    return scrollViewY + card.height > -card.imagePreloadMargin && scrollViewY < scrollView.height + card.imagePreloadMargin;
  }
  readonly property bool imageActive: card.imageUrl !== "" && card.imageNearViewport
  // True while any hover tooltip is shown. The card's z rides on this so the
  // active card stays above its neighbours. Tooltip ids resolve lazily, so
  // reading their `visible` here is safe even though they are declared below.
  readonly property bool anyTooltipVisible:
    placeTooltip.visible || starsTooltip.visible || yelpTooltip.visible ||
    coursesTooltip.visible || priceTooltip.visible || saveTooltip.visible ||
    websiteTooltip.visible || mapsTooltip.visible || copyTooltip.visible

  // ---- Layout ----
  width: ListView.view ? ListView.view.width : parent.width
  height: expanded ? panel.collapsedCardHeight + (expandLoader.item ? expandLoader.item.implicitHeight : panel.expandedFallbackHeight) + Style.space(8) : panel.collapsedCardHeight
  radius: Style.cornerRadius
  color: card.useHoverBg ? (card.hover ? panel.cardHoverBackground : panel.cardBackground) : (card.zebraStripe ? panel.cardBackground : panel.foregroundAlpha(0.03))
  border.color: panel.foregroundAlpha(0.14)
  border.width: 1
  // Keep the active card above its neighbours while a tooltip is shown. No
  // tooltip escapes the card now (all are positioned inside it), so this lift
  // is inert defensive insurance rather than a requirement. 1 is the ListView
  // delegate default; 3 clears the pinned header's z:2 lift in case a future
  // tooltip does overhang.
  z: anyTooltipVisible ? 3 : 1
  HoverHandler { onHoveredChanged: card.hover = hovered }

  // Accent stripe
  Rectangle {
    anchors.left: parent.left
    anchors.top: parent.top; anchors.topMargin: Style.space(6)
    anchors.bottom: parent.bottom; anchors.bottomMargin: Style.space(6)
    width: 4; radius: 2
    color: panel.accentTint
  }

  // Collapsed-row hover tint. Cards that already swap their whole background on
  // hover (useHoverBg) get this from the root color; zebra cards (Explore) do
  // not, so this overlay advertises tappability there without double-tinting.
  Rectangle {
    anchors.left: parent.left; anchors.right: parent.right
    anchors.top: parent.top
    height: panel.collapsedCardHeight
    radius: Style.cornerRadius
    color: (!card.useHoverBg && card.hover) ? panel.foregroundAlpha(0.04) : "transparent"
  }

  // Cover photo (remote Yelp image, lazily loaded async like the media plugin).
  // Wrapped in a rounded clip so it reads as a deliberate thumbnail. The
  // source is gated on `imageActive` so a card only fetches once it nears the
  // viewport; when no image exists or the card is off-screen, a monogram
  // placeholder keeps cards aligned.
  Rectangle {
    width: Style.space(48); height: Style.space(48)
    radius: Style.space(8)
    // Slightly stronger than the image slot's inputBackground so a card with no
    // photo reads as a deliberate monogram tile, not an empty/broken image box.
    color: panel.foregroundAlpha(0.10)
    border.color: panel.foregroundAlpha(0.14)
    border.width: 1
    clip: true
    anchors.left: parent.left; anchors.leftMargin: Style.space(14)
    anchors.top: parent.top; anchors.topMargin: Style.space(14)
    Image {
      id: coverImage
      anchors.fill: parent
      source: card.imageActive ? card.imageUrl : ""
      asynchronous: true
      // Decode at 2x the 48px box so the full-resolution remote image is not
      // decoded per card.
      sourceSize.width: 96
      sourceSize.height: 96
      fillMode: Image.PreserveAspectCrop
      visible: card.imageActive
    }
    Text {
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: card.name.charAt(0)
      // Foreground at 0.75 alpha: the avatar sits on a faint inputBackground
      // (0.08 alpha), so secondaryColor washes out; a brighter initial stays
      // subtle but keeps every monogram legible.
      color: panel.foregroundAlpha(0.75)
      font.pixelSize: Style.fontPx(1.4)
      font.bold: true
      // Keep the monogram until the image is actually decoded (Ready), not just
      // while it is fetching: hiding the instant imageActive flips leaves an
      // empty avatar box for the duration of the async decode.
      visible: !card.imageActive || coverImage.status !== Image.Ready
    }
  }

  // ---- Left column: identity ----
  // Line 1 — name across the full left width. The icon cluster and badges no
  // longer share this row, so the name stops truncating early.
  Text {
    textFormat: Text.PlainText
    anchors.left: parent.left; anchors.leftMargin: titleLeft
    anchors.top: parent.top; anchors.topMargin: Style.space(10)
    width: card.leftWidth
    text: card.name
    color: panel.foregroundColor
    font.bold: true; font.pixelSize: Style.font.heading
    elide: Text.ElideRight
    maximumLineCount: 1
    z: 1
  }

  // Line 2 — kind · price · courses, with the Closed/Reserve badges. Each segment
  // renders only when present and the "·" separators render only between two
  // present segments.
  RowLayout {
    z: 1
    anchors.left: parent.left; anchors.leftMargin: titleLeft
    anchors.top: parent.top; anchors.topMargin: Style.space(32)
    width: card.leftWidth
    clip: true
    spacing: Style.space(6)

    Text {
      textFormat: Text.PlainText
      visible: card.kindLabel !== ""
      Layout.alignment: Qt.AlignVCenter
      Layout.maximumWidth: Style.space(70)
      text: card.kindLabel
      color: panel.secondaryColor
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
    Text {
      textFormat: Text.PlainText
      id: priceText
      visible: card.line2Price !== ""
      Layout.alignment: Qt.AlignVCenter
      // Price must never truncate (a range like "$110 – 125" is the whole
      // point of the segment), so it is pinned to its content width and the
      // courses segment — which follows and fills — elides first instead. The
      // "·" separator is folded into the leading text (not a standalone item)
      // so it never renders when the price is absent.
      // Hints must not read `priceText.implicitWidth`: that self-reference feeds
      // the assigned width back into the measured width, so the segment can
      // settle wider than its glyphs and leave a gap before the separator. The
      // plain `-1` form pins to the implicit width with no feedback.
      Layout.preferredWidth: -1
      Layout.maximumWidth: -1
      text: (card.kindLabel !== "" ? SpotUtils.SEP_LEAD : "") + card.line2Price
      color: panel.secondaryColor
      font.pixelSize: Style.font.caption
      font.bold: true
      elide: Text.ElideRight
      HoverHandler { id: priceHover }
    }
    // Courses is the flexible segment: preferredWidth 0 + fillWidth means it
    // takes only the space left after the pinned price and the badges, so on a
    // tight spec line it shrinks and elides before the price ever truncates.
    // The full value is surfaced by the courses tooltip below when clipped.
    Text {
      textFormat: Text.PlainText
      id: coursesText
      visible: card.courses !== ""
      Layout.alignment: Qt.AlignVCenter
      Layout.fillWidth: true
      Layout.preferredWidth: 0
      text: ((card.kindLabel !== "" || card.line2Price !== "") ? SpotUtils.SEP_LEAD : "") + card.courses
      color: panel.secondaryColor
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
      HoverHandler { id: coursesHover }
    }
    Badge {
      visible: card.isClosed
      label: "Closed"
      tint: Qt.rgba(panel.dangerColor.r, panel.dangerColor.g, panel.dangerColor.b, 0.15)
      borderColor: panel.dangerBorder
      textColor: panel.dangerColor
    }
    // "Reserve" is a property of the spot (plain data), not a control, so it
    // uses the muted data treatment rather than the accent reserved for
    // interactive elements.
    Badge {
      visible: card.canBook
      label: "Reserve"
      tint: panel.foregroundAlpha(0.06)
      borderColor: panel.foregroundAlpha(0.2)
      textColor: panel.secondaryColor
    }
  }

  // Line 3 — place. The visit date leads the row once the spot is rated, and
  // the city/state always follows so a rated spot still names its city in an
  // unscoped list. The neighborhood and address hide while the date is shown:
  // the ~188px left column has no room for date + neighborhood + city without
  // clipping the city. Every segment is content-sized (no fillWidth), so any
  // slack sits at the row's right end and no segment can displace a later one.
  // The state is tooltip-only here. In the unscoped (city-label) case the
  // address segment is hidden — `scopedToCity`.
  RowLayout {
    z: 1
    anchors.left: parent.left; anchors.leftMargin: titleLeft
    anchors.top: parent.top; anchors.topMargin: Style.space(52)
    width: card.leftWidth
    clip: true
    // Zero spacing: the " · " separator is folded into each later segment's
    // leading text (gated on a preceding segment rendering), so the row adds no
    // gap of its own.
    spacing: 0

    // Visit date — leads the place line once the spot has a journal entry.
    // Content-sized (no fillWidth), so it renders at its own width and the city
    // follows immediately instead of being pushed to the row's right edge.
    Text {
      textFormat: Text.PlainText
      id: visitText
      visible: card.showVisitDate
      Layout.alignment: Qt.AlignVCenter
      text: "rated " + card.visitDate
      color: panel.secondaryColor
      font.pixelSize: Style.font.caption
      elide: Text.ElideMiddle
      maximumLineCount: 1
    }
    // Neighborhood (clickable) — filters to this neighborhood. Sized to its own
    // content with a 90px cap so it never stretches the underline in a wide
    // panel. The separator lives in the next segment's leading text, gated on
    // this segment rendering. The hints must NOT read `metaNbText.implicitWidth`:
    // that self-reference feeds the width being assigned back into the width
    // being measured, so the segment can settle wider than its glyphs and leave
    // a gap before the city.
    Text {
      textFormat: Text.PlainText
      id: metaNbText
      visible: card.showNeighborhood
      Layout.alignment: Qt.AlignVCenter
      Layout.maximumWidth: Style.space(90)
      text: card.spotNeighborhood; color: panel.secondaryColor
      font.pixelSize: Style.font.caption; font.underline: true
      elide: Text.ElideRight
      MouseArea {
        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
        onClicked: panel.selectNeighborhood(card.spotNeighborhood, card.cityKey)
      }
    }
    // Street address (plain, not clickable). Content-sized (no fillWidth), so it
    // renders at its own width up to a 180 cap and shrinks to a 60 floor before
    // eliding — it never absorbs slack. The " · " separator is folded into the
    // leading text and gated on the neighborhood actually rendering, so it
    // vanishes when the neighborhood is absent and never leaves a dangling "·".
    // Hidden when the city label is shown (unscoped) via `scopedToCity`.
    Text {
      textFormat: Text.PlainText
      id: metaAddressText
      visible: card.showStreetAddress
      Layout.alignment: Qt.AlignVCenter
      Layout.maximumWidth: Style.space(180)
      Layout.minimumWidth: Style.space(60)
      text: (metaNbText.visible ? SpotUtils.SEP : "") + card.spotAddress; color: panel.secondaryColor
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
    // City (clickable) — filters to this city. Shows the city name alone; the
    // state lives in the hover tooltip. Keeps a readable floor (min 60) and
    // middle-elides. The " · " separator is folded into the leading text and
    // gated on any preceding segment (date, neighborhood, or address) actually
    // rendering, so it never leads the row and never dangles over an empty
    // segment.
    Text {
      textFormat: Text.PlainText
      id: metaCityText
      visible: card.showMetaCity
      Layout.minimumWidth: Style.space(60)
      Layout.alignment: Qt.AlignVCenter
      text: ((visitText.visible || metaNbText.visible || metaAddressText.visible) ? SpotUtils.SEP : "") + card.placeCitySegment; color: panel.secondaryColor
      font.pixelSize: Style.font.caption; font.underline: true
      elide: Text.ElideMiddle
      MouseArea {
        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
        onClicked: panel.selectCity(card.cityKey)
      }
    }
    // Slack absorber. Without a fill item, RowLayout spreads the row's slack
    // between the preferred-size items — measured: a ~36px gap opened before the
    // city's " · ". This trailing fill spacer absorbs the slack instead (~6px),
    // so every segment renders at its own content width.
    Item { Layout.fillWidth: true }
    HoverHandler { id: metaHover }
  }

  // ---- Right column: score block ----
  // Fixed width, anchored right, identical on every card so stars, the Yelp
  // pill, and distance line up vertically down the list.
  Item {
    id: scoreBlock
    z: 1
    width: card.scoreBlockWidth
    anchors.right: parent.right; anchors.rightMargin: Style.space(22)
    anchors.top: parent.top; anchors.topMargin: Style.space(4)
    // Three stacked rows: stars, Yelp/distance, then the 4x24 action cluster.
    // 4 + 68 = 72, leaving 4px under the block inside the 76px collapsed card.
    height: Style.space(68)

    // Row 1 — stars + numeric value. Unrated spots show the Yelp stars muted,
    // no number. The action cluster moved below the Yelp/distance line, so the
    // score block's top row is pure data (stars / Yelp / distance).
    Row {
      id: starsRow
      anchors.left: parent.left
      anchors.top: parent.top; anchors.topMargin: Style.space(4)
      spacing: Style.space(4)
      StarRating {
        id: stars
        panel: card.panel
        value: Math.round(card.showYelpStars ? card.yelpRating : (card.starValue || 0))
        interactive: card.starsInteractive
        opacity: card.showYelpStars ? 0.55 : 1.0
        onPicked: function(stars) { card.panel.runIpcCommand("rate", [card.name, String(stars), "", card.cityKey]) }
      }
      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        visible: card.starValue > 0
        text: card.starValueLabel
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
      // reserved for controls (active chips, links, action pills).
      Rectangle {
        id: yelpPill
        visible: card.yelpRating > 0
        width: yelpRateText.implicitWidth + Style.space(10); height: Style.space(18)
        radius: Style.space(9)
        color: panel.foregroundAlpha(0.08)
        Text {
          textFormat: Text.PlainText
          id: yelpRateText; anchors.centerIn: parent
          text: card.yelpRating.toFixed(1) + (card.yelpReviewCount > 0 ? " (" + card.yelpReviewCount + ")" : "")
          color: panel.secondaryColor; font.pixelSize: Style.font.caption
        }
        HoverHandler { id: yelpHover }
      }
      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        visible: !!card.spotDistanceLabel
        text: card.spotDistanceLabel
        color: panel.secondaryColor
        font.pixelSize: Style.font.caption
      }
    }

    // Row 3 — action cluster: four 24px touch targets (save heart / external
    // link / Maps / Copy) with no gap. The glyphs are centered in each cell, so
    // the glyph-to-glyph rhythm stays 24px while every target clears the 24x24
    // minimum. Four cells total exactly the score-block width, so the cluster
    // spans the block and the heart keeps the same left edge as the stars and
    // Yelp rows above it. A spot without a website or Maps link drops that cell
    // (width 0), leaving the remaining icons packed from the left.
    RowLayout {
      id: actionCluster
      z: 2
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top; anchors.topMargin: Style.space(44)
      spacing: 0

      // Heart — save toggle. Accent marks the saved (active) state.
      Item {
        id: heartItem
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth: Style.space(24)
        Layout.preferredHeight: Style.space(24)
        Text {
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: card.saved ? "\u2665" : "\u2661"
          color: card.saved ? card.panel.accentColor : card.panel.secondaryColor
          font.pixelSize: Style.font.iconLarge
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: card.panel.toggleSaved(card.name) }
        HoverHandler { id: heartHover }
      }

      // External link — opens the spot's website.
      Item {
        id: websiteItem
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth: Style.space(24)
        Layout.preferredHeight: Style.space(24)
        visible: card.hasWebsite
        Image { anchors.centerIn: parent; source: Qt.resolvedUrl("../icons/external-link.svg"); width: 13; height: 13 }
        MouseArea {
          anchors.fill: parent; cursorShape: Qt.PointingHandCursor
          onClicked: { if (spot) panel.openUrl(spot.website) }
        }
        HoverHandler { id: websiteHover }
      }
      // Maps — opens the spot in Google Maps.
      Item {
        id: mapsItem
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth: Style.space(24)
        Layout.preferredHeight: Style.space(24)
        visible: card.hasMaps
        Image { anchors.centerIn: parent; source: Qt.resolvedUrl("../icons/map-pin.svg"); width: 13; height: 13 }
        MouseArea {
          anchors.fill: parent; cursorShape: Qt.PointingHandCursor
          onClicked: { if (spot && spot._mapsUrl) panel.openUrl(spot._mapsUrl) }
        }
        HoverHandler { id: mapsHover }
      }
      // Copy — copies the formatted spot text to the clipboard, with a brief
      // "Copied!" confirmation.
      Item {
        id: copyItem
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth: Style.space(24)
        Layout.preferredHeight: Style.space(24)
        property bool copied: false
        Timer { id: copyTimer; interval: card.panel.copyFeedbackMs; onTriggered: copyItem.copied = false }
        Text {
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: copyItem.copied ? "\u2713" : "\uf0c5"
          color: copyItem.copied ? card.panel.accentColor : card.panel.secondaryColor
          font.pixelSize: Style.font.icon
        }
        MouseArea {
          anchors.fill: parent; cursorShape: Qt.PointingHandCursor
          onClicked: {
            copyItem.copied = true
            copyTimer.start()
            var displayCityName = card.cityKey ? card.panel.cityLabel(card.cityKey) : ""
            var clipboardText = SpotUtils.formatSpotClipboard(card.spot, card.name, displayCityName) + "\n\nvia Omakase — " + card.panel.repoUrl
            Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy 2>/dev/null || printf '%s' \"$1\" | xclip -selection clipboard 2>/dev/null", "_", clipboardText])
          }
        }
        HoverHandler { id: copyHover }
      }
    }
  }

  // Expand affordance — chevron at the card's right edge, pointing right when
  // collapsed and down when expanded. A rounded hover background appears with
  // the card hover so the row advertises that it is tappable; the glyph is
  // sized to read at a glance.
  Item {
    z: 2
    width: Style.space(24); height: Style.space(24)
    anchors.right: parent.right; anchors.rightMargin: Style.space(4)
    // Center in the collapsed region, not the card: `parent.verticalCenter`
    // tracks the card height, so an expanded card drags the chevron down beside
    // the editor. Anchoring to the top edge + half the collapsed height keeps
    // the cue fixed beside the score block in both states.
    anchors.top: parent.top
    anchors.topMargin: (panel.collapsedCardHeight - Style.space(24)) / 2
    Rectangle {
      anchors.fill: parent
      radius: Style.space(6)
      color: card.hover ? panel.cardHoverBackground : "transparent"
    }
    Text {
      textFormat: Text.PlainText
      id: chevron
      anchors.centerIn: parent
      text: card.expanded ? "\u2304" : "\u203a"
      color: card.hover ? panel.foregroundColor : panel.foregroundAlpha(0.7)
      font.pixelSize: Style.font.title
    }
  }

  // Toggle-row MouseArea
  MouseArea {
    anchors.left: parent.left; anchors.right: parent.right
    anchors.top: parent.top; height: panel.collapsedCardHeight
    cursorShape: card.spot ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: {
      // A card click is an unambiguous "I've chosen something in the list", so
      // it dismisses the search-suggestions dropdown (scroll does not).
      panel.searchSuggestionsDismissed = true;
      if (!card.spot) return;
      panel.toggleRow(card.name, card.journalEntry ? card.journalEntry.rating : 0, card.journalEntry ? card.journalEntry.notes : "");
    }
  }

  // Full place line on hover. Shows when a segment is actually clipped, when the
  // street address is hidden (unscoped list), or when a visit date leads the row
  // (it displaces the neighborhood and address), so the full address + "City, ST"
  // is reachable in every case. Lives at the card root (not inside the clipped
  // row) so the row's `clip: true` cannot cut it off. Each tooltip is pinned to
  // its trigger's row with a fixed top margin and aligned to the trigger's
  // column, so it renders inside its own card and can never land on a
  // neighbouring one.
  Tooltip {
    id: placeTooltip
    visible: metaHover.hovered && (
      metaNbText.truncated || metaAddressText.truncated || metaCityText.truncated || visitText.truncated ||
      (!card.scopedToCity && card.spotAddress !== "") || card.visitDate !== ""
    )
    anchors.top: parent.top; anchors.topMargin: Style.space(52)
    anchors.left: parent.left; anchors.leftMargin: titleLeft
    panel: card.panel
    text: SpotUtils.joinNonEmpty([
      card.visitDate !== "" ? ("rated " + card.visitDate) : "",
      card.spotNeighborhood,
      card.spotAddress,
      card.placeCityState
    ])
  }

  // Hover tooltip comparing Yelp vs the user's rating. Placed BESIDE the star
  // row, at the row's own height and in the gap left of the score block: `x`
  // sets the tooltip's right edge `Style.space(6)` left of the score block,
  // `y` aligns it with the star row (`scoreBlock.y + starsRow.y`). Both are
  // sums over tracked properties (`scoreBlock.x/y`, `starsRow.y`), never
  // `mapToItem` (see the cluster tooltips below). Beside is the only position
  // that works: the star row is the score block's top row, so an above
  // position would sit above the card's own top edge and be cut by the Explore
  // ListView's `clip: true` (a z lift cannot defeat clipping) — and for the
  // first card it would have to render outside the panel window itself; a below
  // position stays visible but the pointer on the star row extends down over
  // the tooltip's top edge and obscures its text.
  Tooltip {
    id: starsTooltip
    visible: stars.hovered && card.starValue > 0 && card.yelpRating > 0
    x: scoreBlock.x - width - Style.space(6)
    y: scoreBlock.y + starsRow.y
    panel: card.panel
    text: "Yelp " + card.yelpRating.toFixed(1) + SpotUtils.SEP + "yours " + card.starValueLabel
  }

  // Hover tooltip for the Yelp rating pill: names the rating and gives the bare
  // review count an explicit unit. The count suffix mirrors the pill's own
  // label (`(288)` only when the count is present) and handles the singular, so
  // the two can never disagree. Pinned above the pill, centred on it, via the
  // same tracked-property sums as the cluster tooltips.
  Tooltip {
    id: yelpTooltip
    visible: yelpHover.hovered && card.yelpRating > 0
    x: scoreBlock.x + yelpPill.x + (yelpPill.width - width) / 2
    y: scoreBlock.y + yelpRow.y - height - Style.space(4)
    panel: card.panel
    text: "Yelp " + card.yelpRating.toFixed(1) +
          (card.yelpReviewCount > 0
            ? SpotUtils.SEP + card.yelpReviewCount + (card.yelpReviewCount === 1 ? " review" : " reviews")
            : "")
  }

  // Full courses line on hover, only when the text is actually clipped.
  Tooltip {
    id: coursesTooltip
    visible: coursesHover.hovered && coursesText.truncated
    anchors.top: parent.top; anchors.topMargin: Style.space(36)
    anchors.left: parent.left; anchors.leftMargin: titleLeft
    panel: card.panel
    text: card.courses
  }

  // Hover tooltip for the Yelp price bucket, shown only when the curated price
  // is absent (the Yelp value is the one on display).
  Tooltip {
    id: priceTooltip
    visible: priceHover.hovered && card.priceLabel === "" && card.yelpPrice !== ""
    anchors.top: parent.top; anchors.topMargin: Style.space(36)
    anchors.left: parent.left; anchors.leftMargin: titleLeft
    panel: card.panel
    text: "Yelp price"
  }

  // Hover tooltips for the collapsed-card action cluster. Each sits directly
  // above the icon it describes, centred above its own icon: `x` is the icon's
  // left edge (`scoreBlock.x + <icon>.x`) plus half the difference between the
  // icon's width and the tooltip's width, and `y` is one 4px gap above the
  // cluster top (`scoreBlock.y + actionCluster.y - height - Style.space(4)`).
  // The card-relative position is a sum over tracked properties (`scoreBlock.x/y`,
  // `actionCluster.y`, and the icon's own `x`/`width`), NOT `mapToItem`:
  // mapToItem is a C++ method call, so QML's dependency capture never tracks
  // it, and the binding would freeze at its first (pre-layout) value, leaving
  // the tooltip a row too high.
  Tooltip {
    id: saveTooltip
    visible: heartHover.hovered
    x: scoreBlock.x + heartItem.x + (heartItem.width - width) / 2
    y: scoreBlock.y + actionCluster.y - height - Style.space(4)
    panel: card.panel
    text: card.saved ? "Saved" : "Save"
  }
  Tooltip {
    id: websiteTooltip
    visible: websiteHover.hovered && card.hasWebsite
    x: scoreBlock.x + websiteItem.x + (websiteItem.width - width) / 2
    y: scoreBlock.y + actionCluster.y - height - Style.space(4)
    panel: card.panel
    text: "Website"
  }
  Tooltip {
    id: mapsTooltip
    visible: mapsHover.hovered
    x: scoreBlock.x + mapsItem.x + (mapsItem.width - width) / 2
    y: scoreBlock.y + actionCluster.y - height - Style.space(4)
    panel: card.panel
    text: "Maps"
  }
  Tooltip {
    id: copyTooltip
    visible: copyHover.hovered
    x: scoreBlock.x + copyItem.x + (copyItem.width - width) / 2
    y: scoreBlock.y + actionCluster.y - height - Style.space(4)
    panel: card.panel
    text: copyItem.copied ? "Copied!" : "Copy"
  }

  // Expand form
  Loader {
    id: expandLoader
    active: expanded
    anchors.left: parent.left; anchors.leftMargin: Style.space(18)
    anchors.right: parent.right; anchors.rightMargin: Style.space(14)
    anchors.top: parent.top; anchors.topMargin: panel.collapsedCardHeight
    sourceComponent: Component {
      RatingEditor {
        panel: card.panel; spotData: card.spot; spotName: card.name; spotCity: card.cityKey
        collapsed: !panel.editorOpen
        onExpandRequested: panel.openEditor()
      }
    }
  }
}
