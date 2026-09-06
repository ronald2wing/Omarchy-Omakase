import QtQuick
import qs.Commons

// Kind segmented control: four mutually-exclusive options grouped into one boxed
// segmented control, so the row reads a single choice (pick one kind) as
// distinct from the independent toggles beside it. The container is a filled
// rounded surface (the panel's inputBackground token) with the same 1px
// secondaryColor outline as the neighbouring chips, so the whole row keeps
// exactly one border colour. The internal dividers reuse that same neutral
// secondaryColor, so the group never reads as two overlapping outlines. The
// active cell is the only filled one; its opaque fill paints over the two
// dividers that border it, so no hairline ever sits across the accent.
Rectangle {
  id: kindSegment
  property Item panel
  property var options

  width: kindRow.implicitWidth
  height: kindRow.implicitHeight
  radius: Style.cornerRadius
  color: kindSegment.panel.inputBackground
  border.color: kindSegment.panel.secondaryColor
  border.width: 1

  Row {
    id: kindRow
    anchors.centerIn: parent
    spacing: 0

    Repeater {
      model: kindSegment.options
      delegate: Rectangle {
        // Rounded to an integral width so each 1px divider lands on an
        // integer pixel: a content-sized cell width is fractional (Text
        // implicitWidth is fractional), and a 1px divider at a fractional
        // x antialiases into a 2px smear on the worst boundaries.
        implicitWidth: Math.round(cellText.implicitWidth + Style.space(8))
        implicitHeight: Math.round(Style.space(24))
        color: "transparent"

        // 1px hairline on the right edge, only between adjacent cells
        // (never after the last). Declared before the active fill so the
        // fill paints over it.
        Rectangle {
          anchors.right: parent.right
          width: 1
          height: parent.height
          color: kindSegment.panel.secondaryColor
          visible: index < kindSegment.options.length - 1
        }

        // Active fill: extends 1px left (index > 0) to cover the previous
        // cell's divider and paints over its own right divider (declared
        // above), so an active cell hides both dividers that border it.
        Rectangle {
          x: index > 0 ? -1 : 0
          width: parent.width + (index > 0 ? 1 : 0)
          height: parent.height
          color: kindSegment.panel.kindFilter === modelData.key ? kindSegment.panel.accentColor : "transparent"
        }

        Text {
          textFormat: Text.PlainText
          id: cellText
          anchors.centerIn: parent
          text: modelData.label
          color: kindSegment.panel.kindFilter === modelData.key ? kindSegment.panel.accentTextColor : kindSegment.panel.secondaryColor
          font.pixelSize: Style.font.caption
          font.bold: kindSegment.panel.kindFilter === modelData.key
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            kindSegment.panel.kindFilter = modelData.key;
            kindSegment.panel.openSheet = false;
          }
        }
      }
    }
  }
}
