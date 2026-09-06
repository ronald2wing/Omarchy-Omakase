import QtQuick
import qs.Commons

// Five-star rating row. `value` is the filled-star count; 0 = unrated renders
// all-outline stars. `interactive` enables click-to-rate and emits
// picked(stars).
//
// Rendered as one rich-text `Text` (per-glyph color) plus one `MouseArea`
// instead of a 5-item Repeater, so a card carries 3 visual nodes rather than 18.
// The hit test divides the text width into five equal cells, so width/5 is the
// exact cell width.
Row {
  id: starRating
  property Item panel
  property real value: 0
  property bool interactive: false
  // 1-based index of the star under the pointer (0 = none). Set by the
  // MouseArea's hover handlers; the glyph binding previews it while > 0.
  property int hoveredStar: 0
  signal picked(int stars)
  readonly property alias rowHovered: starHover.hovered

  HoverHandler { id: starHover }

  Text {
    id: starsText
    textFormat: Text.RichText
    text: starRating.glyphMarkup
    font.pixelSize: Style.font.bodySmall

    MouseArea {
      anchors.fill: parent
      enabled: starRating.interactive
      // Per-star hover needs hover events even with no button pressed; `enabled`
      // already gates this off for the non-interactive row, so hoveredStar stays
      // 0 there and the committed rating is untouched.
      hoverEnabled: true
      cursorShape: starRating.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
      onEntered: starRating.hoveredStar = starRating.starIndexAt(mouseX)
      onPositionChanged: (mouse) => starRating.hoveredStar = starRating.starIndexAt(mouse.x)
      onExited: starRating.hoveredStar = 0
      onClicked: (mouse) => {
        var stars = starRating.starIndexAt(mouse.x)
        starRating.hoveredStar = 0
        starRating.picked(stars)
      }
    }
  }

  // Rich-text markup: filled stars in the accent color, empty in secondary.
  // Declarative with explicit deps — a function-call binding would not re-track
  // `value`/`hoveredStar`/the accent colors (reads inside a called function are
  // untracked), so the stars could go stale after a quick-rate. `value` is a
  // real (0 = unrated → all outline), never null. The binding is pure
  // (reads `value`, `hoveredStar` and the panel colors, returns a string) and
  // writes no property during evaluation.
  readonly property string glyphMarkup: {
    starRating.value
    starRating.hoveredStar
    starRating.panel
    // A hovered star previews the rating a click would set, so the preview wins
    // over the committed value; on exit the committed (or Yelp, via the caller's
    // `value`) rating returns.
    var filled = starRating.hoveredStar > 0 ? starRating.hoveredStar : Math.round(starRating.value)
    var accent = starRating.panel.accentColor.toString()
    var secondary = starRating.panel.secondaryColor.toString()
    var markup = ""
    for (var i = 0; i < 5; i++) {
      var isFilled = i < filled
      markup += "<font color=\"" + (isFilled ? accent : secondary) + "\">" + (isFilled ? "\u2605" : "\u2606") + "</font>"
    }
    return markup
  }

  // mouseX -> 1-based star index (1..5). The text width is five equal cells;
  // clamp so a click on the trailing edge still lands on the last star.
  function starIndexAt(mouseX) {
    if (starsText.width <= 0) return 1
    var index = Math.floor(mouseX / (starsText.width / 5)) + 1
    return Math.max(1, Math.min(5, index))
  }
}
