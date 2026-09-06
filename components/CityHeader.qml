import QtQuick
import qs.Commons

// "Back to All Cities" header row. The title (city name or "Within N km")
// is derived from root state; `label`/`count` complete the trailing count
// text ("42 spots" / "7 saved" / "3 rated") which differs per tab. `back`
// lets each call site reset its own query/state.
Row {
  id: header
  property Item panel
  property string label: ""
  property int count: 0
  signal back()
  width: parent.width
  spacing: Style.space(8)
  BackLink {
    id: headerBack
    panel: header.panel
    label: "All Cities"
    onClicked: header.back()
  }
  Text {
    textFormat: Text.PlainText
    anchors.verticalCenter: parent.verticalCenter
    width: header.width - headerBack.width - header.spacing
    horizontalAlignment: Text.AlignRight
    text: {
      var title = header.panel.radius > 0 ? "Within " + header.panel.radius + " km" : header.panel.displayCity(header.panel.cityKey);
      return title + " · " + header.count + " " + header.label;
    }
    color: header.panel.secondaryColor
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideLeft
  }
}
