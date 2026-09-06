import QtQuick
import qs.Commons

// Shared glyph for the copy/phone actions: shows the transient "copied" check
// glyph while the owning CopyFeedback is flashing, else the action's resting
// glyph. Only the glyph is shared — the two actions differ (copy spot text vs
// copy phone number) and keep their own click bodies, so the phone cell still
// keeps its phone glyph and only its feedback/label wiring is common.
Text {
  id: copyGlyph
  textFormat: Text.PlainText

  property Item panel
  property var feedback
  property string restingGlyph

  anchors.centerIn: parent
  text: copyGlyph.feedback.copied ? copyGlyph.feedback.checkGlyph : copyGlyph.restingGlyph
  color: copyGlyph.feedback.copied ? copyGlyph.panel.accentColor : copyGlyph.panel.secondaryColor
  font.pixelSize: Style.font.icon
}
