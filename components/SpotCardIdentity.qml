import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../spot-utils.js" as SpotUtils
import "../catalog-utils.js" as CatalogUtils

// The left identity column of a collapsed spot card: the name line, the spec
// row (kind · price · courses), the Closed/Reserve badges that sit in the spec
// row's reserved slot, and the place row — plus the three hover tooltips that
// anchor into that markup. Extracted from SpotCard.qml so the badge-slot
// geometry, the row content, and the tooltip anchors live in one place.
// `panel` is the BarWidget root; the spot fields and journal entry are passed
// in, so the column derives nothing from the card beyond its inputs and the two
// reserved widths below.
//
// The root is sized over the full collapsed card (`x: 0`, `width` = card width),
// NOT at `x: identityLeft`: the rows already carry
// `anchors.leftMargin: identityLeft`, the badges anchor to `metaRow.right`, and
// the place tooltip carries its own left margin, so offsetting the root would
// add a second `identityLeft` and shift every row right, detach the badges from
// the row's right edge, and drop the tooltip off its segment.
Item {
  id: identity

  // ---- Inputs (set by SpotCard) ----
  property Item panel
  property var spot                 // resolved spot object, or null
  property string spotName          // display + journal identity name
  property string cityKey           // city key for filtering ("nyc")
  property var journalEntry         // { rating, notes, timestamp } or null
  property bool showCity            // show city label?
  property bool showDateInPlaceRow: false
  property real identityLeft        // left inset reserved for the photo slot
  property real leftWidth           // bounded width for the identity lines

  // z: 3 keeps this column above the card's expand chevron (z:2). The three
  // meta-row tooltips are NOT children of this item — they live in the card's
  // higher-z overlay (SpotCard.qml) so they can paint above the score block, a
  // sibling of this column that z could never lift them above from here.
  z: 3

  // ---- Derived (bound from inputs) ----
  readonly property string cityLabel: identity.panel.cityLabel(identity.cityKey)
  readonly property string spotRegionCode: identity.spot ? (identity.spot.region_code || "") : ""
  readonly property string spotCountry: identity.spot ? (identity.spot.country || "") : ""
  readonly property string spotNeighborhood: identity.spot ? (identity.spot.neighborhood || "") : ""
  // Street line for the hover tooltip (`address`, else
  // display_address[0], else ""). Never rendered in the collapsed place row.
  readonly property string spotAddress: identity.spot ? SpotUtils.streetAddress(identity.spot) : ""
  // Ordered city+state parts for the place line: the city label leads only when
  // the list is unscoped (`showCity` + a real `cityKey`), the state follows. The
  // precedence is derived once here; `placeCityState` joins the parts with ", "
  // (the hover tooltip's "City, ST" tail) and `placeTrailingSegment` takes the first
  // part — falling back to the country when neither is known — as the collapsed
  // row's trailing segment.
  readonly property var placeCityStateParts: {
    var parts = [];
    if (identity.showCity && identity.cityKey) parts.push(identity.cityLabel);
    if (identity.spotRegionCode) parts.push(identity.spotRegionCode);
    return parts;
  }
  // "City, ST" for the hover tooltip. City is omitted when the list is already
  // scoped to one city (showCity false), leaving just the state.
  readonly property string placeCityState: identity.placeCityStateParts.join(", ")
  // Place-row trailing segment: the city name alone (no ", ST") when the list
  // is unscoped, else the state, else the country. When the list is already
  // scoped to one city (showCity false) the city is redundant, so the state
  // stands in for it; a spot with neither city nor state falls back to its
  // country so the row still names a place. The raw street address is never a
  // candidate — it is noise in a collapsed list row and lives in the hover
  // tooltip and the Maps link instead.
  readonly property string placeTrailingSegment: identity.placeCityStateParts.length ? identity.placeCityStateParts[0] : identity.spotCountry
  readonly property string yelpPrice: identity.spot ? identity.spot._yelpPrice : ""
  readonly property bool isClosed: identity.spot ? identity.spot._isClosed : false
  readonly property bool canBook: identity.spot ? identity.spot._canBook : false
  readonly property string spotKindValue: identity.spot ? identity.spot._spotKind : ""
  readonly property string kindLabel: CatalogUtils.kindLabelFor(identity.spotKindValue)
  readonly property bool hasNeighborhood: identity.spotNeighborhood !== ""
  readonly property string spotCourses: identity.spot ? identity.spot._coursesSegment : ""
  readonly property string spotPriceLabel: identity.spot ? identity.spot._priceLabel : ""
  readonly property string visitDate: identity.journalEntry ? SpotUtils.formatDate(identity.journalEntry.timestamp) : ""
  // The date segment as rendered ("rated <date>"), shared by the place row's
  // visit-date lead and the place hover tooltip so the two can never disagree.
  readonly property string visitDateSegment: identity.visitDate !== "" ? ("rated " + identity.visitDate) : ""
  // Segment visibility gates for the place row. Each is the exact condition a
  // segment renders under and drives `visible` only — a hidden item in a
  // RowLayout contributes no width or spacing, so gating Layout.* hints on the
  // same flag is dead code. The neighborhood and city gates deliberately ignore
  // the visit date: geography renders for a rated spot exactly as for an
  // unrated one, and the date only leads the row where the list is about the
  // date (Journal, via `showDateInPlaceRow`).
  readonly property bool showVisitDate: identity.showDateInPlaceRow && identity.visitDate !== ""
  // Price shown on the spec line: the curated price, else the Yelp price bucket.
  readonly property string specLinePrice: identity.spotPriceLabel || identity.yelpPrice
  // A spec-line badge (Closed/Reserve) must render whole or not at all — a
  // truncated pill ("Rese…") reads as a rendering bug. When one is present the
  // courses segment — the spec line's least valuable content, whose full value
  // is surfaced by the courses tooltip — is gated off in the row below so it can
  // never compete with the badge for space, and the badge's own visibility is
  // gated on the row having room for it after the pinned kind + price.
  readonly property bool badgePresent: identity.canBook || identity.isClosed
  // Exact width the spec line consumes before its badge slot: the kind (capped
  // at its 70px maximum, though every real label is well under), the kind-price
  // separator, and the pinned price, each measured from the sibling Text items'
  // implicitWidth — never the badge's own, so the fit check cannot feed the
  // assigned width back into the measure — plus the row's `Style.space(6)` gap
  // before each present segment and before the badge. Kind is always present
  // when a badge is (both derive from a resolved spot).
  readonly property real badgeLeadingWidth: {
    var gap = Style.space(6);
    var w = Math.min(kindText.implicitWidth, Style.space(70));
    if (identity.specLinePrice !== "") w += gap + kindSeparator.implicitWidth + gap + priceText.implicitWidth;
    return w + gap;
  }
  // Width the spec line yields to its badge slot: the visible badge's implicit
  // width plus its leading 6px gap, else 0. Exactly one badge can be visible
  // (Reserve yields to Closed), so the slot derives from whichever is showing.
  // The meta row subtracts this (see `metaRow.width`), so its `clip: true` can
  // never reach a badge sitting in the reserved slot.
  readonly property real badgeSlotWidth: (closedBadge.visible || reserveBadge.visible)
    ? (closedBadge.visible ? closedBadge.implicitWidth : reserveBadge.implicitWidth) + Style.space(6)
    : 0
  // Shared badge fit test: the leading kind + price plus the badge's own width
  // must still fit the identity's bounded left width. A function (not a
  // `readonly property bool`) so each badge passes its own implicitWidth. The
  // two badge `visible` bindings read `badgeLeadingWidth`/`leftWidth` explicitly
  // before calling — property reads inside this function are untracked — so the
  // check still re-evaluates when the spec line or card width changes.
  function badgeFits(badgeWidth) {
    return identity.badgeLeadingWidth + badgeWidth <= identity.leftWidth;
  }

  // Full place line for the hover tooltip: the date segment, then neighborhood,
  // street address, and the "City, ST" tail. Derived from the same segment
  // sources the place row renders, so the tooltip never restates the row's
  // logic — it always carries the address (the collapsed row never shows it)
  // and the "City, ST" tail (the row shows the city name alone).
  readonly property string placeTooltipText: SpotUtils.joinTruthy([
    identity.visitDateSegment,
    identity.spotNeighborhood,
    identity.spotAddress,
    identity.placeCityState
  ])
  // True when the place tooltip has something to reveal: a clipped segment, a
  // street address the collapsed row never shows, or a visit date (which in the
  // browse tabs lives only in the expanded card).
  readonly property bool placeTooltipNeeded:
    metaNbText.truncated || metaCityText.truncated || visitText.truncated ||
    identity.spotAddress !== "" ||
    identity.visitDate !== ""

  // Line 1 — name across the full left width.
  Text {
    textFormat: Text.PlainText
    anchors.left: parent.left; anchors.leftMargin: identityLeft
    anchors.top: parent.top; anchors.topMargin: Style.space(10)
    width: identity.leftWidth
    text: identity.spotName
    color: panel.foregroundColor
    font.bold: true; font.pixelSize: Style.font.heading
    elide: Text.ElideRight
    maximumLineCount: 1
    z: 1
  }

  // Line 2 — kind · price · courses. Each segment renders only when present and
  // the "·" separators render only between two present segments. The
  // Closed/Reserve badges are siblings of this row (below), not children — see
  // `badgeSlotWidth`.
  //
  // The two "·" separators share this one definition (the bare-dot rationale
  // below lives here, once); each use site is a `Loader` carrying its own
  // `visible` gate.
  Component {
    id: dotSeparator
    // Separator between two present segments. A standalone item so it takes the
    // row's `spacing` on both sides and centres between the two segments. The
    // bare dot (U+00B7, no surrounding whitespace) is used rather than SEP /
    // SEP_LEAD — both carry whitespace and would double up with the row spacing.
    Text {
      textFormat: Text.PlainText
      text: "\u00B7"
      color: panel.secondaryColor
      font.pixelSize: Style.font.caption
    }
  }
  RowLayout {
    id: metaRow
    z: 1
    anchors.left: parent.left; anchors.leftMargin: identityLeft
    anchors.top: parent.top; anchors.topMargin: Style.space(32)
    // The text area yields the badge slot (see `badgeSlotWidth`): the badges
    // live OUTSIDE this row as siblings, so the row must not extend under them.
    width: identity.leftWidth - identity.badgeSlotWidth
    clip: true
    spacing: Style.space(6)

    Text {
      textFormat: Text.PlainText
      id: kindText
      visible: identity.kindLabel !== ""
      Layout.alignment: Qt.AlignVCenter
      Layout.maximumWidth: Style.space(70)
      text: identity.kindLabel
      color: panel.secondaryColor
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
    // Separator between the kind and the price.
    Loader {
      id: kindSeparator
      sourceComponent: dotSeparator
      visible: identity.kindLabel !== "" && identity.specLinePrice !== ""
      Layout.alignment: Qt.AlignVCenter
    }
    Text {
      textFormat: Text.PlainText
      id: priceText
      visible: identity.specLinePrice !== ""
      Layout.alignment: Qt.AlignVCenter
      // Price must never truncate (a range like "$110 – 125" is the whole
      // point of the segment), so it is pinned to its content width and the
      // courses segment — which follows and fills — elides first instead.
      // Hints must not read `priceText.implicitWidth`: that self-reference feeds
      // the assigned width back into the measured width, so the segment can
      // settle wider than its glyphs and leave a gap before the separator. The
      // plain `-1` form pins to the implicit width with no feedback.
      Layout.preferredWidth: -1
      Layout.maximumWidth: -1
      text: identity.specLinePrice
      color: panel.secondaryColor
      font.pixelSize: Style.font.caption
      font.bold: true
      elide: Text.ElideRight
      HoverHandler { id: priceHover }
    }
    // Separator between the price and the courses. Gated on the courses segment
    // actually rendering (visible, not merely present in the data) and on some
    // segment preceding it (the price, or the kind when the price is absent) so
    // it never leads the row nor dangles over a segment that yielded to zero —
    // when a badge pushes the courses segment out of the row, this dot goes with
    // it rather than lingering between the price and the badge.
    Loader {
      sourceComponent: dotSeparator
      visible: coursesText.visible && (identity.specLinePrice !== "" || identity.kindLabel !== "")
      Layout.alignment: Qt.AlignVCenter
    }
    // Courses is the flexible segment: preferredWidth 0 + fillWidth means it
    // takes only the space left after the pinned price and the badges, so on a
    // tight spec line it shrinks and elides before the price ever truncates.
    // The full value is surfaced by the courses tooltip below when clipped.
    // When a badge is present the segment is hidden outright (it is the least
    // valuable content and must never squeeze the badge), and the trailing
    // slack absorber takes the row's leftover space instead.
    Text {
      textFormat: Text.PlainText
      id: coursesText
      visible: identity.spotCourses !== "" && !identity.badgePresent
      Layout.alignment: Qt.AlignVCenter
      Layout.fillWidth: true
      Layout.preferredWidth: 0
      text: identity.spotCourses
      color: panel.secondaryColor
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
      HoverHandler { id: coursesHover }
    }
    // Slack absorber for when the courses segment is absent (an AYCE spot whose
    // courses value merely restates the "AYCE" kind label, suppressed by
    // formatCoursesSegment) or hidden to make room for a badge. Courses normally
    // fills the row via fillWidth, but a hidden segment contributes no width —
    // without this trailing filler, RowLayout spreads the row's slack across the
    // remaining segments and opens a large gap before the price. It only fills
    // while courses is not rendering, so it never competes with courses.
    Item {
      Layout.fillWidth: !coursesText.visible
    }
  }

  // Spec-line badges (Closed / Reserve) live OUTSIDE the clipped meta row as
  // its siblings, anchored into the slot the row yields (`badgeSlotWidth`): the
  // badge's left edge sits `Style.space(6)` right of the shrunken row's right
  // edge, so the row's `clip: true` can never slice the pill. Each renders
  // whole or not at all — the leading kind + price must still fit after the
  // slot is reserved — and Reserve yields to Closed (a closed spot never
  // advertises reservations), so at most one badge competes for the slot. The
  // visibility gate reads the badge's own implicit width, never `metaRow.width`
  // or `badgeSlotWidth`, so the check stays loop-free.
  Badge {
    id: closedBadge
    z: 2
    anchors.left: metaRow.right; anchors.leftMargin: Style.space(6)
    anchors.verticalCenter: metaRow.verticalCenter
    visible: {
      identity.isClosed;
      identity.badgeLeadingWidth;
      identity.leftWidth;
      closedBadge.implicitWidth;
      return identity.isClosed && identity.badgeFits(closedBadge.implicitWidth);
    }
    label: "Closed"
    tint: Qt.rgba(panel.dangerColor.r, panel.dangerColor.g, panel.dangerColor.b, 0.15)
    borderColor: panel.dangerBorder
    textColor: panel.dangerColor
  }
  // "Reserve" is a property of the spot (plain data), not a control, so it
  // joins the muted pill language of the score block's Yelp pill (same height,
  // radius, horizontal padding, and non-bold caption typography) rather than
  // the accent reserved for interactive elements.
  Badge {
    id: reserveBadge
    z: 2
    anchors.left: metaRow.right; anchors.leftMargin: Style.space(6)
    anchors.verticalCenter: metaRow.verticalCenter
    visible: {
      identity.canBook;
      identity.isClosed;
      identity.badgeLeadingWidth;
      identity.leftWidth;
      reserveBadge.implicitWidth;
      return identity.canBook && !identity.isClosed &&
        identity.badgeFits(reserveBadge.implicitWidth);
    }
    label: "Reserve"
    tint: panel.foregroundAlpha(0.08)
    textColor: panel.secondaryColor
    cornerRadius: Style.space(9)
    horizontalPadding: Style.space(10)
    bold: false
  }

  // Line 3 — place. The place line is `neighborhood · City`, each segment
  // omitted when missing, so it always names the same kind of thing regardless
  // of what data exists. The neighborhood and city/state/country always render
  // (gated only on their own presence, never on rating) so a rated spot names
  // its geography exactly like an unrated one. The "rated <date>" segment leads
  // the row only where the date is the point of the list (the Journal tab, via
  // `showDateInPlaceRow`); everywhere else the date lives in the expanded card,
  // leaving the place row free for geography. Every segment is content-sized (no
  // fillWidth), so any slack sits at the row's right end and no segment can
  // displace a later one. The trailing segment is the city label when unscoped
  // (the state is then tooltip-only, reachable via the hover tooltip's
  // "City, ST"), the state when scoped to one city (it stands in for the
  // redundant city), and the country when neither is known. The raw street
  // address is deliberately never rendered here — it is noise in a collapsed
  // list row and stays reachable via the hover tooltip and the Maps link.
  RowLayout {
    z: 1
    anchors.left: parent.left; anchors.leftMargin: identityLeft
    anchors.top: parent.top; anchors.topMargin: Style.space(52)
    width: identity.leftWidth
    clip: true
    // Zero spacing: the " · " separator is folded into each later segment's
    // leading text (gated on a preceding segment rendering), so the row adds no
    // gap of its own.
    spacing: 0

    // Visit date — leads the place line on the Journal tab, where the date is
    // the point of the list (`showDateInPlaceRow`). Content-sized (no fillWidth), so
    // it renders at its own width and the neighborhood follows immediately
    // instead of being pushed to the row's right edge.
    Text {
      textFormat: Text.PlainText
      id: visitText
      visible: identity.showVisitDate
      Layout.alignment: Qt.AlignVCenter
      text: identity.visitDateSegment
      color: panel.secondaryColor
      font.pixelSize: Style.font.caption
      elide: Text.ElideMiddle
      maximumLineCount: 1
    }
    // Neighborhood (clickable) — filters to this neighborhood. Sized to its own
    // content with a 90px cap so it never stretches the underline in a wide
    // panel. Normally first in the row (no leading separator — the next segment
    // carries the " · "); when a visit date leads (Journal) it takes its own
    // leading separator, gated on that date rendering. The hints must NOT read
    // `metaNbText.implicitWidth`: that self-reference feeds the width being
    // assigned back into the width being measured, so the segment can settle
    // wider than its glyphs and leave a gap before the city.
    Text {
      textFormat: Text.PlainText
      id: metaNbText
      visible: identity.hasNeighborhood
      Layout.alignment: Qt.AlignVCenter
      Layout.maximumWidth: Style.space(90)
      text: (visitText.visible ? SpotUtils.SEP : "") + identity.spotNeighborhood; color: panel.secondaryColor
      font.pixelSize: Style.font.caption; font.underline: true
      elide: Text.ElideRight
      MouseArea {
        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
        onClicked: panel.selectNeighborhood(identity.spotNeighborhood, identity.cityKey)
      }
    }
    // City (clickable) — filters to this city. Shows the city name alone; the
    // state lives in the hover tooltip. Keeps a readable floor (min 60) and
    // middle-elides. The " · " separator is folded into the leading text and
    // gated on any preceding segment (date or neighborhood) actually rendering,
    // so it never leads the row and never dangles over an empty segment.
    Text {
      textFormat: Text.PlainText
      id: metaCityText
      visible: identity.placeTrailingSegment !== ""
      Layout.minimumWidth: Style.space(60)
      Layout.alignment: Qt.AlignVCenter
      text: ((visitText.visible || metaNbText.visible) ? SpotUtils.SEP : "") + identity.placeTrailingSegment; color: panel.secondaryColor
      font.pixelSize: Style.font.caption; font.underline: true
      elide: Text.ElideMiddle
      MouseArea {
        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
        onClicked: panel.selectCity(identity.cityKey)
      }
    }
    // Slack absorber. Without a fill item, RowLayout spreads the row's slack
    // between the preferred-size items — measured: a ~36px gap opened before the
    // city's " · ". This trailing fill spacer absorbs the slack instead (~6px),
    // so every segment renders at its own content width.
    Item { Layout.fillWidth: true }
    HoverHandler { id: metaHover }
  }

  // ---- Tooltip inputs (consumed by the card-level overlay) ----
  // The place/courses/price tooltips must paint ABOVE the score block, but z is
  // sibling-scoped: a tooltip child of this column can never rise above the
  // score block (a sibling of this column), which renders after it. The
  // tooltips therefore live at the card root (SpotCard.qml) in a higher-z
  // overlay; this column exposes the hover/segment state they bind to. The
  // segment Items are exposed so the MetaTooltips keep their summed-geometry
  // position (`row.x + anchorItem.x`) unchanged — those coordinates are
  // identity-relative, and the overlay sits at the same origin (x:0, y:0), so
  // the sums land on the same card pixels.
  readonly property bool placeHovered: metaHover.hovered
  readonly property bool coursesHovered: coursesHover.hovered
  readonly property bool priceHovered: priceHover.hovered
  readonly property bool coursesTruncated: coursesText.truncated
  readonly property Item metaRowItem: metaRow
  readonly property Item coursesItem: coursesText
  readonly property Item priceItem: priceText
}
