import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../spot-utils.js" as SpotUtils

// One spot row: cover photo, title/badges, meta row, rating line, and the
// expandable rating editor. `panel` is the BarWidget root (colors, helpers,
// actions); `scrollView` is the outer Flickable used to gate the remote image
// fetch on proximity to the visible area.
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
  readonly property string cityLabel: panel.displayCity(cityKey)
  readonly property string spotState: spot ? (spot.state || "") : ""
  readonly property string spotNeighborhood: spot ? (spot.neighborhood || "") : ""
  readonly property string spotDistance: panel.spotDistance(spot)
  // "City, ST" for the collapsed meta row. City is omitted when the list is
  // already scoped to one city (showCity false), leaving just the state.
  readonly property string metaCityState: {
    var parts = [];
    if (card.showCity && card.cityKey) parts.push(card.cityLabel);
    if (card.spotState) parts.push(card.spotState);
    return parts.join(", ");
  }
  readonly property real yelpRating: spot ? spot._yelpRating : 0
  readonly property int yelpReviewCount: spot ? spot._yelpReviewCount : 0
  readonly property string yelpPrice: spot ? spot._yelpPrice : ""
  readonly property bool isClosed: spot ? spot._isClosed : false
  readonly property bool canBook: spot ? spot._canBook : false
  readonly property string imageUrl: spot ? spot._imageUrl : ""
  readonly property string kind: spot ? spot._spotKind : ""
  readonly property real starValue: journalEntry && journalEntry.rating ? journalEntry.rating : 0
  readonly property bool expanded: panel.expandedSpotName === card.name
  readonly property bool hasLink: !!(spot && (spot.website || spot._mapsUrl))
  readonly property bool hasNeighborhood: !!(spot && spot.neighborhood)
  readonly property string courses: spot ? spot._courses : ""
  readonly property string priceLabel: spot ? spot._priceLabel : ""
  readonly property bool saved: { panel.saved; return panel.isSaved(name); }
  readonly property string visitDate: journalEntry ? SpotUtils.formatDate(journalEntry.timestamp) : ""
  readonly property bool showYelpStars: !card.starValue && card.yelpRating > 0

  // Left inset for the title/meta/rating rows. Always reserves the photo
  // slot so cards with and without images align their text identically.
  readonly property real titleLeft: Style.space(18) + Style.space(64) + Style.space(10)

  // Viewport-gated remote image. The list is not virtualized, so without this
  // every instantiated card (~88-176) fires a Yelp CDN fetch on panel open.
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

  // ---- Layout ----
  width: ListView.view ? ListView.view.width : parent.width
  height: expanded ? panel.collapsedCardHeight + (expandLoader.item ? expandLoader.item.implicitHeight : panel.expandedFallbackHeight) + Style.space(8) : panel.collapsedCardHeight
  radius: Style.cornerRadius
  color: card.useHoverBg ? (card.hover ? panel.cardHoverBackground : panel.cardBackground) : (card.zebraStripe ? panel.cardBackground : panel.foregroundAlpha(0.03))
  border.color: panel.foregroundAlpha(0.14)
  border.width: 1
  HoverHandler { onHoveredChanged: card.hover = hovered }

  // Accent stripe
  Rectangle {
    anchors.left: parent.left
    anchors.top: parent.top; anchors.topMargin: Style.space(6)
    anchors.bottom: parent.bottom; anchors.bottomMargin: Style.space(6)
    width: 4; radius: 2
    color: panel.accentTint
  }

  // Cover photo (remote Yelp image, lazily loaded async like the media plugin).
  // Wrapped in a rounded clip so it reads as a deliberate thumbnail. The
  // source is gated on `imageActive` so a card only fetches once it nears the
  // viewport; when no image exists or the card is off-screen, a monogram
  // placeholder keeps cards aligned.
  Rectangle {
    width: Style.space(64); height: Style.space(64)
    radius: Style.space(10)
    color: panel.inputBackground
    border.color: panel.foregroundAlpha(0.14)
    border.width: 1
    clip: true
    anchors.left: parent.left; anchors.leftMargin: Style.space(18)
    anchors.top: parent.top; anchors.topMargin: Style.space(20)
    Image {
      anchors.fill: parent
      source: card.imageActive ? card.imageUrl : ""
      asynchronous: true
      // Decode at 2x the 64px box so the full-resolution remote image is not
      // decoded per card.
      sourceSize.width: 128
      sourceSize.height: 128
      fillMode: Image.PreserveAspectCrop
      visible: card.imageActive
    }
    Text {
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: card.name.charAt(0)
      color: panel.secondaryColor
      font.pixelSize: Style.fontPx(1.6)
      font.bold: true
      visible: !card.imageActive
    }
  }

  // Title row: name · Closed badge · link icon. RowLayout so the name takes
  // the remaining width and elides, keeping the badges pinned and visible.
  RowLayout {
    id: titleRow
    // Above the toggle-row MouseArea so the link icon stays clickable.
    z: 1
    anchors.left: parent.left; anchors.leftMargin: titleLeft
    anchors.top: parent.top; anchors.topMargin: Style.space(9)
    anchors.right: heartItem.left; anchors.rightMargin: Style.space(8)
    spacing: Style.space(6)
    Text {
      textFormat: Text.PlainText
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      text: card.name
      color: panel.foregroundColor
      font.bold: true; font.pixelSize: Style.fontPx(1.35)
      elide: Text.ElideRight
    }
    Rectangle {
      Layout.alignment: Qt.AlignVCenter
      visible: card.kind !== ""
      width: typeLabel.implicitWidth + Style.space(12); height: Style.space(18)
      radius: Style.space(4)
      color: panel.accentTint
      border.color: panel.accentColor
      border.width: 1
      Text {
        textFormat: Text.PlainText
        id: typeLabel; anchors.centerIn: parent
        text: card.kind === "discount" ? "Discount" : "Omakase"
        color: panel.accentColor
        font.bold: true; font.pixelSize: Style.font.caption
      }
    }
    Rectangle {
      Layout.alignment: Qt.AlignVCenter
      visible: card.isClosed
      width: closedLabel.implicitWidth + Style.space(12); height: Style.space(18)
      radius: Style.space(4)
      color: Qt.rgba(panel.dangerColor.r, panel.dangerColor.g, panel.dangerColor.b, 0.15)
      border.color: panel.dangerBorder
      border.width: 1
      Text {
        textFormat: Text.PlainText
        id: closedLabel; anchors.centerIn: parent
        text: "Closed"; color: panel.dangerColor
        font.bold: true; font.pixelSize: Style.font.caption
      }
    }
    Rectangle {
      Layout.alignment: Qt.AlignVCenter
      visible: card.canBook
      width: bookLabel.implicitWidth + Style.space(12); height: Style.space(18)
      radius: Style.space(4)
      color: panel.accentTint
      border.color: panel.accentColor
      border.width: 1
      Text {
        textFormat: Text.PlainText
        id: bookLabel; anchors.centerIn: parent
        text: "Book"; color: panel.accentColor
        font.bold: true; font.pixelSize: Style.font.caption
      }
    }
    Item {
      z: 2; Layout.alignment: Qt.AlignVCenter
      Layout.preferredWidth: hasLink ? 18 : 0
      Layout.preferredHeight: hasLink ? 18 : 0
      visible: hasLink
      Image { anchors.centerIn: parent; source: Qt.resolvedUrl("../icons/external-link.svg"); width: 13; height: 13 }
      MouseArea {
        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
        onClicked: { if (spot && spot.website) panel.openUrl(spot.website); else if (spot && spot._mapsUrl) panel.openUrl(spot._mapsUrl) }
      }
    }
  }

  // Heart
  Item {
    id: heartItem; z: 1
    anchors.right: parent.right; anchors.rightMargin: Style.space(14)
    anchors.verticalCenter: titleRow.verticalCenter
    width: 24; height: 24
    Text {
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: card.saved ? "\u2665" : "\u2661"
      color: card.saved ? panel.accentColor : panel.secondaryColor
      font.pixelSize: 17
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: panel.toggleSaved(card.name) }
  }

  // Meta row: neighborhood · city, state (elided) on the left; distance
  // pinned right so it never truncates. Country is dropped (redundant with
  // state for US spots) and the street address lives in the expanded view.
  // The location segments stay clickable to filter the list to that place.
  RowLayout {
    anchors.left: parent.left; anchors.leftMargin: titleLeft
    anchors.top: parent.top; anchors.topMargin: Style.space(40)
    anchors.right: parent.right; anchors.rightMargin: Style.space(14)
    spacing: Style.space(6); z: 1

    // Neighborhood (clickable) — filters to this neighborhood.
    Text {
      textFormat: Text.PlainText
      id: metaNbText
      visible: hasNeighborhood
      Layout.alignment: Qt.AlignVCenter
      text: card.spotNeighborhood; color: panel.secondaryColor
      font.pixelSize: Style.font.caption; font.underline: true
      elide: Text.ElideRight
      MouseArea {
        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
        onClicked: panel.selectNeighborhood(card.spotNeighborhood, card.cityKey)
      }
    }
    Text {
      textFormat: Text.PlainText
      visible: hasNeighborhood && card.metaCityState !== ""
      Layout.alignment: Qt.AlignVCenter
      text: "\u00b7"; color: panel.secondaryColor; font.pixelSize: Style.font.caption
    }
    // City, state (clickable) — filters to this city. Fills the remaining
    // width and elides, so the distance stays pinned to the right edge.
    Text {
      textFormat: Text.PlainText
      id: metaCityStateText
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      text: card.metaCityState; color: panel.secondaryColor
      font.pixelSize: Style.font.caption; font.underline: true
      elide: Text.ElideRight
      MouseArea {
        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
        onClicked: panel.selectCity(card.cityKey)
      }
    }
    // Distance — fixed, right-aligned, never elided.
    Text {
      textFormat: Text.PlainText
      id: metaDistanceText
      visible: !!card.spotDistance
      Layout.alignment: Qt.AlignVCenter
      text: card.spotDistance; color: panel.secondaryColor; font.pixelSize: Style.font.caption
    }
  }

  // Rating / price line: interactive stars + price + community yelp rating.
  Row {
    // Above the toggle-row MouseArea so the quick-rate stars stay clickable.
    z: 1
    anchors.left: parent.left; anchors.leftMargin: titleLeft
    anchors.top: parent.top; anchors.topMargin: Style.space(66)
    anchors.right: parent.right; anchors.rightMargin: Style.space(14)
    clip: true; spacing: Style.space(6)
    StarRating {
      id: userStars
      panel: card.panel
      value: Math.round(showYelpStars ? card.yelpRating : (card.starValue || 0))
      interactive: card.starsInteractive
      onPicked: function(stars) { card.panel.runIpcCommand("rate", [card.name, String(stars), "", card.cityKey]) }
    }
    Text { textFormat: Text.PlainText; text: "\u00b7"; anchors.verticalCenter: parent.verticalCenter; color: panel.secondaryColor; font.pixelSize: Style.font.caption; visible: !!(spot && (card.priceLabel || card.courses)) }
    Text { textFormat: Text.PlainText; anchors.verticalCenter: parent.verticalCenter; text: card.priceLabel; color: panel.secondaryColor; font.pixelSize: Style.font.bodySmall; font.bold: true; visible: !!card.priceLabel }
    Item {
      visible: !!card.yelpPrice && !card.priceLabel
      implicitWidth: yelpPriceText.width; implicitHeight: yelpPriceText.height
      Text {
        textFormat: Text.PlainText
        id: yelpPriceText; anchors.verticalCenter: parent.verticalCenter
        text: card.yelpPrice; color: panel.secondaryColor; font.pixelSize: Style.font.caption; font.bold: true
      }
      HoverHandler { id: priceHover }
      Text {
        textFormat: Text.PlainText
        visible: priceHover.hovered; anchors.bottom: yelpPriceText.top; anchors.horizontalCenter: yelpPriceText.horizontalCenter
        text: "Yelp price"; color: panel.secondaryColor; font.pixelSize: Style.font.caption
        Rectangle { anchors.fill: parent; anchors.margins: -2; color: panel.cardBackground; radius: 2; z: -1 }
      }
    }
    Rectangle {
      visible: card.yelpRating > 0
      width: yelpRateText.implicitWidth + Style.space(12); height: Style.space(20)
      radius: Style.space(10)
      color: panel.accentTint
      Text {
        textFormat: Text.PlainText
        id: yelpRateText; anchors.centerIn: parent
        text: card.yelpRating.toFixed(1) + (card.yelpReviewCount > 0 ? " (" + card.yelpReviewCount + ")" : "")
        color: panel.accentColor; font.pixelSize: Style.font.caption; font.bold: true
      }
      HoverHandler { id: yelpHover }
      Text {
        textFormat: Text.PlainText
        visible: yelpHover.hovered; anchors.bottom: yelpRateText.top; anchors.horizontalCenter: yelpRateText.horizontalCenter
        text: "Yelp community rating"; color: panel.secondaryColor
        font.pixelSize: Style.font.caption; font.bold: true
        Rectangle {
          anchors.fill: parent; anchors.margins: -2
          color: panel.cardBackground; radius: 2; z: -1
        }
      }
    }
    Text { textFormat: Text.PlainText; anchors.verticalCenter: parent.verticalCenter; text: courses; color: panel.secondaryColor; font.pixelSize: Style.font.caption; visible: !showYelpStars && !!courses; elide: Text.ElideRight; maximumLineCount: 1; width: Math.min(implicitWidth, Style.space(140)) }
    Text { textFormat: Text.PlainText; text: "\u00b7"; color: panel.secondaryColor; font.pixelSize: Style.font.caption; visible: !!visitDate && !!courses }
    Text { textFormat: Text.PlainText; text: "rated " + visitDate; color: panel.secondaryColor; font.pixelSize: Style.font.caption; visible: !!visitDate; elide: Text.ElideRight; maximumLineCount: 1; width: Math.min(implicitWidth, Style.space(120)) }
  }

  // Toggle-row MouseArea
  MouseArea {
    anchors.left: parent.left; anchors.right: parent.right
    anchors.top: parent.top; height: panel.collapsedCardHeight
    cursorShape: card.spot ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: {
      if (!card.spot) return;
      panel.toggleRow(card.name, card.journalEntry ? card.journalEntry.rating : 0, card.journalEntry ? card.journalEntry.notes : "");
    }
  }

  // Hover tooltip comparing Yelp vs the user's rating. Lives at the card root
  // (not inside the clipped rating row) so it can render above neighbouring
  // content.
  Rectangle {
    visible: userStars.hovered && card.starValue > 0 && card.yelpRating > 0
    anchors.top: parent.top; anchors.topMargin: Style.space(82)
    anchors.left: parent.left; anchors.leftMargin: titleLeft
    width: starTooltipText.implicitWidth + Style.space(8)
    height: starTooltipText.implicitHeight + Style.space(4)
    radius: 2; color: panel.cardBackground
    border.color: panel.foregroundAlpha(0.1)
    z: 5
    Text {
      textFormat: Text.PlainText
      id: starTooltipText
      anchors.centerIn: parent
      text: "Yelp " + card.yelpRating.toFixed(1) + " · yours " + card.starValue
      color: panel.secondaryColor; font.pixelSize: Style.font.caption
    }
  }

  // Expand form
  Loader {
    id: expandLoader
    active: expanded
    anchors.left: parent.left; anchors.leftMargin: Style.space(18)
    anchors.right: parent.right; anchors.rightMargin: Style.space(14)
    anchors.top: parent.top; anchors.topMargin: panel.collapsedCardHeight
    sourceComponent: Component {
      RatingEditor { panel: card.panel; spotData: card.spot; spotName: card.name; spotCity: card.cityKey }
    }
  }
}
