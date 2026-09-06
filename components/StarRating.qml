import QtQuick
import qs.Commons

// Five-star rating row. `value` is the filled-star count — a null/0 value
// (unrated) renders all-outline stars. `interactive` enables click-to-rate
// and emits picked(stars). `starSize`/`fontSize` reproduce the two call-site
// sizes (large editor stars vs. compact card stars).
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
  property real starSize: 14
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
  // Math.round(null) is 0, so all outline.
  //
  // The markup is a pure function of (filled, accent, secondary), so it is built
  // once per distinct triple and cached. `glyphMarkupCache` is a declarative
  // property (reassigned whole, never mutated in place) keyed on those inputs;
  // `glyphMarkup` is a cheap read of it. A re-rate that keeps the same colors
  // reuses the cached string instead of rebuilding five <font> nodes, and no
  // binding writes a property during evaluation.
  property var glyphMarkupCache: {
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
    return { key: filled + "|" + accent + "|" + secondary, markup: markup }
  }
  readonly property string glyphMarkup: {
    starRating.glyphMarkupCache
    return starRating.glyphMarkupCache.markup
  }

  // mouseX -> 0-based star index. The text width is five equal cells; clamp so
  // a click on the trailing edge still lands on the last star.
  function starIndexAt(mouseX) {
    if (starsText.width <= 0) return 0
    var index = Math.floor(mouseX / (starsText.width / 5))
    return Math.max(0, Math.min(4, index))
  }
}
