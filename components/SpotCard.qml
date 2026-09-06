import QtQuick
import QtQuick.Layouts
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
// cards. All actions (save heart / link / Maps / Copy / phone) live in one
// cluster in the score block, beneath the Yelp/distance line; the Yelp pill
// itself opens the spot's Yelp page.
Rectangle {
  id: card

  property Item panel
  property var scrollView

  // ---- Inputs (set by delegate) ----
  property var spot                 // resolved spot object, or null (unresolved wishlist name)
  property string cityKey           // city key for filtering ("nyc")
  property string fallbackName      // display name when spot is null
  property bool starsInteractive    // permit a collapsed star click to quick-rate (the tab's flag; the expanded state is folded in at the ScoreBlock binding)
  property bool showCity            // show city label?
  // Keep the "rated <date>" segment in the place row. Only the Journal tab (a
  // list of rated spots, where the date is the point) opts in; the browse tabs
  // leave the place row to geography and surface the date in the expanded card.
  property bool showDateInPlaceRow: false
  property bool useHoverBg          // use hover bg instead of zebra
  property int zebraStripe          // 0 or 1 for zebra striping (ignored when hover)
  property bool hovered: false

  // ---- Derived (bound from inputs) ----
  // The name shown in the row, the monogram, and the clipboard — and the identity
  // key for journal/save lookups and the row actions (rate/save/toggle/expand):
  // the spot's name when resolved, else the caller's fallback name (an unresolved
  // wishlist entry). One name serves both roles; there is no separate display
  // label to drift from the journal identity.
  readonly property string spotName: spot && spot.name ? spot.name : fallbackName
  // The spot's most recent journal entry ({ rating, notes, timestamp } or
  // null), resolved here so the three delegates stop computing it. `panel.journal`
  // is the explicit tracked dep — the `latestJournalFor` call itself is
  // untracked and would otherwise never re-run under a held list snapshot (the
  // hold freezes the model snapshots, but a rating/notes write must still
  // resolve in place) or when the journal is rewritten — so the bare read keeps
  // the binding live. `spotName` is read as the lookup key, tracking the
  // resolved name so an unresolved wishlist entry re-resolves once its spot
  // lands.
  readonly property var journalEntry: {
    card.panel.journal;
    return card.panel.latestJournalFor(card.spotName);
  }
  readonly property string spotImageUrl: spot ? spot._imageUrl : ""
  readonly property real starValue: journalEntry && journalEntry.rating ? journalEntry.rating : 0
  // The journal entry's notes, guarded once for the expand handler (which would
  // otherwise repeat the `journalEntry ?` test). `starValue` above already
  // carries the rating, so the two call sites share one expression.
  readonly property string journalNotes: journalEntry ? journalEntry.notes : ""
  readonly property bool expanded: panel.expandedSpotName === card.spotName
  // The journal entry's visit date, surfaced by the expanded editor's "rated
  // <date>" line. The identity column derives its own date segment from the same
  // entry, so the two stay in agreement without a shared binding.
  readonly property string visitDate: journalEntry ? SpotUtils.formatDate(journalEntry.timestamp) : ""

  // Left inset for the identity column. Always reserves the photo slot so
  // cards with and without images align their text identically.
  readonly property real identityLeft: Style.space(14) + Style.space(48) + Style.space(10)
  // Fixed score-block width — identical on every card so the scan line holds.
  readonly property real scoreBlockWidth: Style.space(120)
  // Bounded width for the identity lines. RowLayout does not clip, so a line
  // anchored only on the right would let its non-fillWidth children overflow
  // under the score block (declared later, so it paints on top). The two rows
  // carry `clip: true` as a backstop; the name line just elides. The place
  // row owns the full left width now that the action cluster lives in the
  // score block.
  readonly property real leftWidth: card.width - card.identityLeft - card.scoreBlockWidth - Style.space(22) - Style.space(8)

  // Viewport-gated remote image. The list IS virtualized — ExploreTab is a
  // ListView with reuseItems and a 500px cacheBuffer, so only ~20 delegates
  // instantiate at once, not the ~88-176 a non-virtualized list would. The
  // gate still pays off: those delegates (plus the buffer's) would each fire a
  // Yelp CDN fetch as they enter the buffer, and a model reset re-instantiates
  // the whole window. The model is a plain JS-array snapshot (`exploreModel`,
  // reassigned by refreshExploreModel()), and a plain-array model resets every
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
  readonly property bool imageActive: card.spotImageUrl !== "" && card.imageNearViewport

  // ---- Layout ----
  // Bottom gap below the expanded editor, matching the editor's own 8px bottom
  // padding (RatingEditor.qml `bottomPadding`) so the card frames the form with
  // symmetric space above and below.
  readonly property real expandedEditorBottomGap: Style.space(8)
  width: ListView.view ? ListView.view.width : parent.width
  height: expanded ? panel.collapsedCardHeight + (expandLoader.item ? expandLoader.item.implicitHeight : panel.expandedFallbackHeight) + card.expandedEditorBottomGap : panel.collapsedCardHeight
  radius: Style.cornerRadius
  color: card.useHoverBg ? (card.hovered ? panel.cardHoverBackground : panel.cardBackground) : (card.zebraStripe ? panel.cardBackground : panel.foregroundAlpha(0.03))
  border.color: panel.foregroundAlpha(0.14)
  border.width: 1
  HoverHandler { onHoveredChanged: card.hovered = hovered }

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
    color: (!card.useHoverBg && card.hovered) ? panel.foregroundAlpha(0.04) : "transparent"
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
      source: card.imageActive ? card.spotImageUrl : ""
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
      text: card.spotName.charAt(0)
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
  // The name, spec row (kind · price · courses), Closed/Reserve badges, and
  // place row live in SpotCardIdentity.qml, sized over the full collapsed card
  // at x:0/y:0. The component must NOT be positioned at `x: identityLeft` —
  // the rows already carry `anchors.leftMargin: identityLeft`, the badges
  // anchor to `metaRow.right`, and the place tooltip carries its own left
  // margin, so an offset here would add a second `identityLeft` and shift every
  // row, detach the badges, and drop the tooltip off its segment.
  SpotCardIdentity {
    id: identityColumn
    panel: card.panel
    spot: card.spot
    spotName: card.spotName
    cityKey: card.cityKey
    journalEntry: card.journalEntry
    showCity: card.showCity
    showDateInPlaceRow: card.showDateInPlaceRow
    identityLeft: card.identityLeft
    leftWidth: card.leftWidth
    x: 0
    y: 0
    width: card.width
    height: panel.collapsedCardHeight
  }

  // ---- Right column: score block ----
  // Fixed width, anchored right, identical on every card so stars, the Yelp
  // pill, and distance line up vertically down the list. The rows and the
  // action cluster (with their hover tooltips) live in ScoreBlock.qml.
  ScoreBlock {
    panel: card.panel
    spot: card.spot
    spotName: card.spotName
    cityKey: card.cityKey
    // The star row is interactive when the tab permits a collapsed quick-rate OR
    // the card is expanded — an expanded Journal card must still be ratable even
    // though its tab passes `starsInteractive: false`. Compute the combined gate
    // here so no tab needs to know about the expanded state.
    starsInteractive: card.starsInteractive || card.expanded
    starValue: card.starValue
    width: card.scoreBlockWidth
  }

  // ---- Meta-row tooltip overlay ----
  // The place/courses/price tooltips must paint ABOVE the score block's action
  // cluster, but QML `z` orders an item only among its siblings within the same
  // parent: the tooltips were children of SpotCardIdentity and the cluster lives
  // in ScoreBlock, so no `z` on the tooltips could lift them above the block.
  // They are hoisted here, to a card-level overlay at z:4 (above ScoreBlock's
  // z:3), positioned at the identity column's origin (x:0, y:0) so the
  // MetaTooltips' summed geometry (`row.x + anchorItem.x`, in identity
  // coordinates) lands on the same card pixels. The column content stays at z:3
  // beneath the score block — the two never overlap — and the score block's own
  // tooltips (stars/Yelp/cluster) remain children of ScoreBlock at z:3,
  // untouched by this overlay.
  Item {
    id: tooltipOverlay
    z: 4
    x: 0
    y: 0
    width: card.width
    height: panel.collapsedCardHeight

    // Full place line on hover, so the full address + "City, ST" + date is
    // reachable in every case. Lives at the card root (not inside the clipped
    // place row) so the row's `clip: true` cannot cut it off.
    Tooltip {
      id: placeTooltip
      visible: identityColumn.placeHovered && identityColumn.placeTooltipNeeded
      anchors.top: parent.top; anchors.topMargin: Style.space(52)
      anchors.left: parent.left; anchors.leftMargin: card.identityLeft
      panel: card.panel
      text: identityColumn.placeTooltipText
    }

    // Full courses line on hover, only when the text is actually clipped.
    // `rightAlign` right-aligns the (wider-than-clipped) full text to the
    // segment's right edge to stay inside the card.
    MetaTooltip {
      id: coursesTooltip
      visible: identityColumn.coursesHovered && identityColumn.coursesTruncated
      row: identityColumn.metaRowItem
      anchorItem: identityColumn.coursesItem
      rightAlign: true
      panel: card.panel
      text: identityColumn.spotCourses
    }

    // Hover tooltip for the Yelp price bucket, shown only when the curated price
    // is absent (the Yelp value is the one on display). The short fixed label
    // never overflows, so a plain left alignment (`rightAlign` off) suffices.
    MetaTooltip {
      id: priceTooltip
      visible: identityColumn.priceHovered && identityColumn.spotPriceLabel === "" && identityColumn.yelpPrice !== ""
      row: identityColumn.metaRowItem
      anchorItem: identityColumn.priceItem
      panel: card.panel
      text: "Yelp price"
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
      color: card.hovered ? panel.cardHoverBackground : "transparent"
    }
    Text {
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: card.expanded ? "\u2304" : "\u203a"
      color: card.hovered ? panel.foregroundColor : panel.foregroundAlpha(0.7)
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
      panel.toggleRow(card.spotName, card.starValue, card.journalNotes);
    }
  }

  // Expand form. The Loader owns the editor's width (the editor root sets no
  // left/right anchors — anchoring a Loader's item fights the Loader's own
  // sizing and desyncs paint from hit-testing). The inset lives here, once:
  // 16px each side. The editor's implicitHeight drives the expanded card height
  // (see the root `height` binding), and the form reports its full height — the
  // notes box and Remove rating are always shown together. The star control
  // stays in the score block above, the single star row in both states.
  Loader {
    id: expandLoader
    active: expanded
    anchors.left: parent.left; anchors.leftMargin: Style.space(16)
    anchors.right: parent.right; anchors.rightMargin: Style.space(16)
    anchors.top: parent.top; anchors.topMargin: panel.collapsedCardHeight
    sourceComponent: Component {
      RatingEditor {
        panel: card.panel; spotName: card.spotName; spotCityKey: card.cityKey
        ratedDate: card.visitDate
        journalEntry: card.journalEntry
      }
    }
  }
}
