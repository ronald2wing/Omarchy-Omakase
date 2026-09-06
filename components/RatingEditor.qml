import QtQuick
import Quickshell
import qs.Commons
import "../spot-utils.js" as SpotUtils

// Expanded rating form for one spot: action pills (Yelp/Website/Maps/Call/Copy),
// the large interactive star row, a notes editor, and Save/Submit/Remove.
// `panel` is the BarWidget root (colors, helpers, actions).
Column {
  id: ratingEditor

  property Item panel
  property var spotData: null
  property string spotName: ""
  property string spotCity: ""

  readonly property bool hasRating: {
    panel.journal; // bind to journal changes
    return !!panel.latestJournalFor(spotName);
  }
  anchors.left: parent.left; anchors.leftMargin: Style.space(16)
  anchors.right: parent.right; anchors.rightMargin: Style.space(16)
  spacing: Style.space(6)
  bottomPadding: Style.space(8)

  readonly property bool mapsVisible: !!(spotData && spotData._mapsUrl)
  readonly property bool webVisible: !!(spotData && spotData.website)
  readonly property bool callVisible: !!(spotData && spotData.phone)
  readonly property bool yelpVisible: !!(spotData && spotData.yelp_url && spotData.yelp_url.length > 0)

  Rectangle {
    width: parent.width
    height: 1
    color: panel.foregroundAlpha(0.15)
  }

  Flow {
    width: parent.width
    spacing: Style.space(8)

    ActionPill {
      panel: ratingEditor.panel
      visible: yelpVisible
      icon: "\uf1e9"
      label: "Yelp"
      onActivated: { if (spotData && spotData.yelp_url) ratingEditor.panel.openUrl(spotData.yelp_url) }
    }
    ActionPill {
      panel: ratingEditor.panel
      visible: webVisible
      iconSource: Qt.resolvedUrl("../icons/external-link.svg")
      label: "Website"
      onActivated: { if (spotData && spotData.website) ratingEditor.panel.openUrl(spotData.website) }
    }
    ActionPill {
      panel: ratingEditor.panel
      visible: mapsVisible
      iconSource: Qt.resolvedUrl("../icons/map-pin.svg")
      label: "Maps"
      onActivated: { if (spotData && spotData._mapsUrl) ratingEditor.panel.openUrl(spotData._mapsUrl) }
    }
    ActionPill {
      panel: ratingEditor.panel
      visible: callVisible
      icon: "\uf095"
      label: "Call"
      onActivated: { if (spotData && spotData.phone) ratingEditor.panel.openUrl("tel:" + spotData.phone) }
    }
    Rectangle {
      id: copyRect
      visible: !!spotData
      width: Style.space(84)
      height: Style.space(28)
      radius: Style.cornerRadius
      color: panel.accentTint
      border.color: panel.accentColor
      border.width: 1
      property bool copied: false
      Timer { id: copyTimer; interval: ratingEditor.panel.copyFeedbackMs; onTriggered: copyRect.copied = false }
      Row {
        anchors.centerIn: parent
        spacing: Style.space(5)
        Text { textFormat: Text.PlainText; text: "\uf0c5"; color: ratingEditor.panel.accentColor; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
        Text { textFormat: Text.PlainText; text: copyRect.copied ? "Copied!" : "Copy"; color: ratingEditor.panel.accentColor; font.bold: true; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          copyRect.copied = true
          copyTimer.start()
          var displayCityName = spotCity ? ratingEditor.panel.displayCity(spotCity) : ""
          var clipboardText = SpotUtils.formatSpotClipboard(spotData, spotName, displayCityName) + "\n\nvia Omakase — " + ratingEditor.panel.repoUrl
          Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy 2>/dev/null || printf '%s' \"$1\" | xclip -selection clipboard 2>/dev/null", "_", clipboardText])
        }
      }
    }
  }

  // Divider separating the action pills from the rating section.
  Rectangle {
    width: parent.width
    height: 1
    color: panel.foregroundAlpha(0.08)
  }

  Row {
    width: parent.width
    spacing: Style.space(8)
    topPadding: Style.space(10)
    Text {
      textFormat: Text.PlainText
      text: "Rate"
      color: panel.foregroundColor
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      font.letterSpacing: 1
      font.capitalization: Font.AllUppercase
    }
    Text {
      textFormat: Text.PlainText
      text: "tap a star"
      color: panel.secondaryColor
      font.pixelSize: Style.font.caption
      anchors.verticalCenter: parent.verticalCenter
    }
  }
  StarRating {
    panel: ratingEditor.panel
    spacing: Style.space(6)
    value: ratingEditor.panel.editStars
    interactive: true
    starSize: 36
    fontSize: Style.font.display
    onPicked: function(stars) { ratingEditor.panel.editStars = stars }
  }
  Flickable {
    width: parent.width; height: Style.space(56)
    clip: true
    contentWidth: width
    contentHeight: Math.max(notesEdit.implicitHeight + Style.space(16), Style.space(56))
    Rectangle { anchors.fill: parent; radius: Style.cornerRadius; color: ratingEditor.panel.inputBackground }
    TextEdit {
      id: notesEdit
      width: parent.width - Style.space(24)
      anchors.left: parent.left; anchors.leftMargin: Style.space(12)
      anchors.top: parent.top; anchors.topMargin: Style.space(8)
      color: ratingEditor.panel.foregroundColor
      font.pixelSize: Style.font.bodySmall
      text: ratingEditor.panel.editNotes
      onTextChanged: ratingEditor.panel.editNotes = text
      wrapMode: TextEdit.Wrap
      selectByMouse: true
      Text { textFormat: Text.PlainText; text: "Notes..."; visible: !notesEdit.text; color: ratingEditor.panel.secondaryColor; font.pixelSize: Style.font.bodySmall; anchors.left: parent.left; anchors.top: parent.top }
    }
  }
  Row {
    width: parent.width
    spacing: Style.space(8)
    topPadding: Style.space(6)
    readonly property int count: hasRating ? 3 : 2
    readonly property real btnW: (width - spacing * (count - 1)) / count
    Item {
      id: saveBtn
      width: parent.btnW; height: Style.space(40)
      property bool saved: ratingEditor.panel.isSaved(spotName)
      Connections {
        target: ratingEditor.panel
        function onSavedChanged() { saveBtn.saved = ratingEditor.panel.isSaved(spotName) }
      }
      Rectangle { anchors.fill: parent; radius: Style.cornerRadius; color: saveBtn.saved ? ratingEditor.panel.accentTint : "transparent"; border.color: saveBtn.saved ? ratingEditor.panel.accentColor : ratingEditor.panel.secondaryColor; border.width: 1 }
      Row { anchors.centerIn: parent; spacing: Style.space(6)
        Text { textFormat: Text.PlainText; text: saveBtn.saved ? "\u2665" : "\u2661"; color: saveBtn.saved ? ratingEditor.panel.accentColor : ratingEditor.panel.secondaryColor; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
        Text { textFormat: Text.PlainText; text: saveBtn.saved ? "Saved" : "Save"; color: saveBtn.saved ? ratingEditor.panel.accentColor : ratingEditor.panel.secondaryColor; font.bold: true; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter }
      }
      MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ratingEditor.panel.toggleSaved(spotName) }
    }
    Rectangle {
      width: parent.btnW; height: Style.space(40)
      radius: Style.cornerRadius
      color: ratingEditor.panel.editStars > 0 ? ratingEditor.panel.accentColor : "transparent"
      border.color: ratingEditor.panel.editStars > 0 ? ratingEditor.panel.accentColor : ratingEditor.panel.secondaryColor
      border.width: 1
      Row { anchors.centerIn: parent; spacing: Style.space(6)
        Text { textFormat: Text.PlainText; text: hasRating ? "\u21bb" : "\u2713"; color: ratingEditor.panel.editStars > 0 ? ratingEditor.panel.accentTextColor : ratingEditor.panel.secondaryColor; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
        Text { textFormat: Text.PlainText; text: hasRating ? "Update" : "Submit"; color: ratingEditor.panel.editStars > 0 ? ratingEditor.panel.accentTextColor : ratingEditor.panel.secondaryColor; font.bold: true; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter }
      }
      MouseArea { anchors.fill: parent; enabled: ratingEditor.panel.editStars > 0; cursorShape: Qt.PointingHandCursor
        onClicked: {
          if (!spotName || !ratingEditor.panel.editStars) return;
          ratingEditor.panel.runIpcCommand("rate", [spotName, String(ratingEditor.panel.editStars), ratingEditor.panel.editNotes, spotCity]);
          if (!ratingEditor.panel.spotlight) ratingEditor.panel.collapseRow();
        }
      }
    }
    Rectangle {
      visible: hasRating
      width: parent.btnW; height: Style.space(40)
      radius: Style.cornerRadius
      color: "transparent"
      border.color: ratingEditor.panel.dangerBorder
      border.width: 1
      Text { textFormat: Text.PlainText; anchors.centerIn: parent; text: "Remove"; color: ratingEditor.panel.dangerColor; font.bold: true; font.pixelSize: Style.font.bodySmall }
      MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
        onClicked: {
          if (!spotName) return;
          ratingEditor.panel.runIpcCommand("unrate", [spotName, spotCity]);
          if (!ratingEditor.panel.spotlight) ratingEditor.panel.collapseRow();
        }
      }
    }
  }
}
