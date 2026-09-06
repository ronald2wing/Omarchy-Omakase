import QtQuick

// Shared transient "Copied" feedback: the copied flag, the auto-reset timer,
// and the check glyph / label strings. Both the collapsed cluster's Copy and
// Phone cells (SpotCard) consume this instead of each duplicating the same
// state machine. Each cell owns both of its label states here — the resting
// label (set per cell, since Copy and Phone rest on different labels) and the
// copied label — and `label` resolves to whichever is current. A QtObject never
// participates in a parent's Column/Row, so each host keeps its own glyph and
// label placement and only reads the state and strings here.
QtObject {
  id: copyFeedback

  // BarWidget root, read only for the feedback duration.
  property Item panel
  property bool copied: false

  // Resting (not-copied) label for this cell; Copy and Phone set different ones.
  property string restingLabel: ""

  readonly property string checkGlyph: "\u2713"
  readonly property string copiedLabel: "Copied"
  // The label to show right now: the copied confirmation while the feedback
  // flash is live, else the cell's resting label.
  readonly property string label: copyFeedback.copied ? copyFeedback.copiedLabel : copyFeedback.restingLabel

  // Held as a property, not a child: QtObject has no default property to host
  // a nested Timer.
  property Timer resetTimer: Timer {
    interval: copyFeedback.panel.copyFeedbackMs
    onTriggered: copyFeedback.copied = false
  }

  // Begin the feedback: set the flag and schedule the auto-reset. `restart()`
  // covers a repeat action while the previous reset is still pending.
  function flash() {
    copyFeedback.copied = true;
    resetTimer.restart();
  }
}
