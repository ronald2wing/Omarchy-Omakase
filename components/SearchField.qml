import QtQuick
import QtQuick.Layouts
import qs.Commons

// Reusable search bar. `text` is bound by the caller to its query property —
// user typing and the clear button funnel through `edited` (the caller owns the
// target), and programmatic changes to the bound property flow back into the
// field through the internal sync below. Per-tab height/insets/clear size
// differ slightly, so they're exposed as properties with the Explore defaults.
Rectangle {
  id: field
  property Item panel
  property string placeholder: ""
  property string text: ""
  signal edited(string value)
  property real leftInset: Style.space(10)
  property real rightInset: Style.space(6)
  property real clearSize: 18

  // A plain binding on input.text would be severed by the first keystroke, so
  // this handler is the single re-sync path for external `text` changes (e.g.
  // a reset). `onTextEdited` below covers the user direction.
  onTextChanged: { if (input.text !== field.text) input.text = field.text }

  width: parent.width
  height: Style.space(32)
  radius: Style.cornerRadius
  color: panel.inputBackground

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: field.leftInset
    anchors.rightMargin: field.rightInset
    spacing: Style.space(6)

    Image {
      source: Qt.resolvedUrl("../icons/search.svg")
      Layout.preferredWidth: 14
      Layout.preferredHeight: 14
      Layout.alignment: Qt.AlignVCenter
    }

    TextInput {
      id: input
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      color: panel.foregroundColor
      font.pixelSize: Style.font.bodySmall
      selectByMouse: true
      onTextEdited: field.edited(text)
      Text {
        textFormat: Text.PlainText
        text: field.placeholder
        visible: !input.text
        color: panel.secondaryColor
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
    }

    Item {
      Layout.preferredWidth: field.clearSize
      Layout.preferredHeight: field.clearSize
      visible: input.text !== ""
      Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: "\u2715"
        color: panel.secondaryColor
        font.pixelSize: Style.font.bodySmall
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: field.edited("")
      }
    }
  }
}
