import QtQuick
import qs.Commons

// Five-star rating row. `value` is the filled-star count — a null/0 value
// (unrated) renders all-outline stars. `interactive` enables click-to-rate
// and emits picked(stars). `fontSize` reproduces the two call-site sizes
// (large editor stars vs. compact card stars).
//
// Rendered as one rich-text `Text` (per-glyph color) plus one `MouseArea`
// instead of a 5-item Repeater, so a card carries 3 visual nodes rather than 18.
// `spacing` is kept as the inter-glyph gap via font.letterSpacing; the hit
// test divides the text width into five equal cells (letterSpacing is included
// in each glyph's advance, so width/5 is the exact cell width).
Row {
  id: starRating
  property Item panel
  property real value: 0
  property bool interactive: false
  property real fontSize: Style.font.bodySmall
  signal picked(int stars)
  readonly property alias hovered: starHover.hovered

  spacing: 0
  HoverHandler { id: starHover }

  Text {
    id: starsText
    textFormat: Text.RichText
    text: starRating.glyphMarkup
    font.pixelSize: starRating.fontSize
    font.letterSpacing: starRating.spacing

    MouseArea {
      anchors.fill: parent
      enabled: starRating.interactive
      cursorShape: starRating.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: starRating.picked(starRating.starIndexAt(mouseX) + 1)
    }
  }

  // Rich-text markup: filled stars in the accent color, empty in secondary.
  // Declarative with explicit deps — a function-call binding would not re-track
  // `value`/the accent colors (reads inside a called function are untracked), so
  // the stars could go stale after a quick-rate. `value` may be null (unrated);
  // Math.round(null) is 0, so all outline. The binding is pure (reads `value`
  // and the panel colors, returns a string) and writes no property during
  // evaluation.
  property string glyphMarkup: {
    starRating.value
    starRating.panel
    var filled = Math.round(starRating.value || 0)
    var accent = starRating.panel ? starRating.panel.accentColor.toString() : "#44aaff"
    var secondary = starRating.panel ? starRating.panel.secondaryColor.toString() : "#888888"
    var markup = ""
    for (var i = 0; i < 5; i++) {
      var isFilled = i < filled
      markup += "<font color=\"" + (isFilled ? accent : secondary) + "\">" + (isFilled ? "\u2605" : "\u2606") + "</font>"
    }
    return markup
  }

  // mouseX -> 0-based star index. The text width is five equal cells; clamp so
  // a click on the trailing edge still lands on the last star.
  function starIndexAt(mouseX) {
    if (starsText.width <= 0) return 0
    var index = Math.floor(mouseX / (starsText.width / 5))
    return Math.max(0, Math.min(4, index))
  }
}
