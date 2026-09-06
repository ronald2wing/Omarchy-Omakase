import QtQuick
import QtQuick.Layouts
import qs.Commons

// Reusable search bar. `text` is bound by the caller to its query property —
// user typing and the clear button funnel through `edited` (the caller owns the
// target), and programmatic changes to the bound property flow back into the
// field through the internal sync below. Per-tab insets differ, so
// leftInset/rightInset are `required` — the single call site (TabSearchHeader)
// supplies them from its own per-tab defaults.
Rectangle {
  id: field
  property Item panel
  property string placeholder: ""
  property string text: ""
  signal edited(string value)
  signal dismissed()
  signal fieldClicked()
  // Whether the field's editor currently owns keyboard focus. The panel's
  // PanelKeyCatcher reads this (aggregated across every search field) to
  // `block` its own key interception while the field is being typed into, so
  // Escape reaches this field instead of closing the panel.
  readonly property bool hasFocus: input.activeFocus
  required property real leftInset
  required property real rightInset
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
    spacing: Style.space(6)

    Image {
      source: Qt.resolvedUrl("../icons/search.svg")
      Layout.preferredWidth: Style.space(14)
      Layout.preferredHeight: Style.space(14)
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
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          field.dismissed();
          event.accepted = true;
        }
      }
      // Fires `fieldClicked` on a click of the field without stealing the
      // press, so the TextInput still takes focus and positions the cursor.
      // It must be a child of the TextInput: a TapHandler on the field
      // Rectangle never fires over a TextInput, which grabs the mouse on press
      // for focus + drag selection.
      TapHandler {
        onTapped: field.fieldClicked()
      }
      Text {
        textFormat: Text.PlainText
        text: field.placeholder
        visible: !input.text
        color: panel.secondaryColor
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
    }

    // Clear button. A layout child sized by the RowLayout, never an anchored
    // sibling: anchors on a layout-managed item are undefined, and a fill-width
    // sibling would squeeze a zero-implicit-size item to ~0px (the 2px sliver).
    // minimum/maximumWidth pin the exact size against the fill-width input; the
    // glyph Text and MouseArea inside may anchor to it freely.
    Rectangle {
      id: clearButton
      Layout.preferredWidth: field.clearSize
      Layout.preferredHeight: field.clearSize
      Layout.minimumWidth: field.clearSize
      Layout.minimumHeight: field.clearSize
      Layout.maximumWidth: field.clearSize
      Layout.maximumHeight: field.clearSize
      Layout.alignment: Qt.AlignVCenter
      Layout.rightMargin: field.rightInset
      visible: input.text !== ""
      color: "transparent"
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
