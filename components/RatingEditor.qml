import QtQuick
import QtQuick.Layouts
import qs.Commons

// Expanded rating form for one spot: the action pills (Yelp/Website/Call), the
// large interactive star row, a notes editor, and Save/Remove. `panel` is the
// BarWidget root (colors, helpers, actions).
//
// The action pills and the star row are always visible so a single click on a
// card exposes quick-rate and the spot's links. Only the notes box and the
// Save/Remove buttons live behind the `collapsed` gate. A single pill beside
// the stars serves two roles depending on `dirty`: with no pending rating it
// reads "Edit" and reveals the full form; with a pending star rating (the
// default state in Explore/Wishlist) it reads "Save" and commits that rating
// in place, so tapping a star is always recoverable without discovering the
// Edit pill first. Maps/Copy are NOT repeated here — they live on the collapsed
// card (SpotCard.qml).
Column {
  id: ratingEditor

  property Item panel
  property var spotData: null
  property string spotName: ""
  property string spotCity: ""
  // Compact state: the action pills and star row stay visible; only the notes
  // box and the Save/Remove buttons are hidden until the pill emits
  // `expandRequested()` (or, when dirty, commits the pending rating directly).
  property bool collapsed: false
  signal expandRequested()

  readonly property bool hasRating: {
    panel.journal; // bind to journal changes
    return !!panel.latestJournalFor(spotName);
  }

  // True when the on-screen stars differ from the stored rating — i.e. the user
  // has tapped a star but not yet saved. `latestJournalFor()` is a function
  // call, so its internal read of the journal index is NOT tracked by the
  // binding engine; the explicit `panel.journal` read (same dependency as
  // `hasRating` above) is what makes this recompute after a save and flip the
  // pill back to "Edit". Reads only — no property is written here.
  readonly property bool dirty: {
    panel.journal; // bind to journal changes
    var entry = panel.latestJournalFor(spotName);
    return panel.editStars !== (entry ? entry.rating : 0);
  }

  // Action-pill visibility. Maps/Copy are omitted: they already live on the
  // collapsed card, so repeating them here would duplicate the actions.
  readonly property bool yelpVisible: !!(spotData && spotData.yelp_url && spotData.yelp_url.length > 0)
  readonly property bool webVisible: !!(spotData && spotData.website)
  readonly property bool callVisible: !!(spotData && spotData.phone)

  // Pills laid out as centered rows of up to `actionColumns` so a partial final
  // row is balanced instead of leaving a dangling empty cell at the end of a
  // left-aligned wrap. The visible actions are collected first (visibility
  // varies per spot), then sliced into rows; each row centers itself.
  readonly property int actionColumns: 3
  readonly property var actionRows: {
    var items = [];
    if (yelpVisible) items.push({ kind: "yelp", icon: "\uf1e9", iconSource: "", label: "Yelp" });
    if (webVisible) items.push({ kind: "web", icon: "", iconSource: "../icons/external-link.svg", label: "Website" });
    if (callVisible) items.push({ kind: "call", icon: "\uf095", iconSource: "", label: "Call" });
    var rows = [];
    for (var i = 0; i < items.length; i += actionColumns) rows.push(items.slice(i, i + actionColumns));
    return rows;
  }

  function runAction(kind) {
    if (kind === "yelp") { if (spotData && spotData.yelp_url) ratingEditor.panel.openUrl(spotData.yelp_url); }
    else if (kind === "web") { if (spotData && spotData.website) ratingEditor.panel.openUrl(spotData.website); }
    else if (kind === "call") { if (spotData && spotData.phone) ratingEditor.panel.openUrl("tel:" + spotData.phone); }
  }
  anchors.left: parent.left; anchors.leftMargin: Style.space(16)
  anchors.right: parent.right; anchors.rightMargin: Style.space(16)
  spacing: Style.space(6)
  bottomPadding: Style.space(8)

  // Rate label + interactive stars, always visible. The pill (compact state
  // only) sits after the stars: "Edit" reveals the notes + save/remove block,
  // "Save" commits a pending star rating (see `dirty`). Wrapped in a Column
  // because RowLayout has no topPadding; the Column supplies the gap above the
  // row.
  Column {
    width: parent.width
    topPadding: Style.space(10)
    RowLayout {
      width: parent.width
      spacing: Style.space(8)
      Text {
        textFormat: Text.PlainText
        text: "Rate"
        color: panel.foregroundColor
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        font.letterSpacing: 1
        Layout.alignment: Qt.AlignVCenter
      }
      StarRating {
        panel: ratingEditor.panel
        spacing: Style.space(6)
        value: ratingEditor.panel.editStars
        interactive: true
        fontSize: Style.font.display
        Layout.alignment: Qt.AlignVCenter
        onPicked: function(stars) { ratingEditor.panel.editStars = stars }
      }
      Item { Layout.fillWidth: true }
      Rectangle {
        visible: ratingEditor.collapsed
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: editPillText.implicitWidth + Style.space(20)
        implicitHeight: Style.space(28)
        radius: Style.cornerRadius
        // Two roles in one pill: "Edit" (tint) opens the full form; "Save"
        // (accent fill) commits a pending star rating in place, reusing the
        // expanded Save button's accent-fill / accent-text treatment.
        color: ratingEditor.dirty ? ratingEditor.panel.accentColor : ratingEditor.panel.accentTint
        border.color: ratingEditor.panel.accentColor
        border.width: 1
        Text {
          textFormat: Text.PlainText
          id: editPillText
          anchors.centerIn: parent
          text: ratingEditor.dirty ? "Save" : "Edit"
          color: ratingEditor.dirty ? ratingEditor.panel.accentTextColor : ratingEditor.panel.accentColor
          font.bold: true
          font.pixelSize: Style.font.caption
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (ratingEditor.dirty) {
              if (!spotName || !ratingEditor.panel.editStars) return;
              ratingEditor.panel.runIpcCommand("rate", [spotName, String(ratingEditor.panel.editStars), ratingEditor.panel.editNotes, spotCity]);
              if (!ratingEditor.panel.spotlight) ratingEditor.panel.collapseRow();
            } else {
              ratingEditor.expandRequested();
            }
          }
        }
      }
    }

    // Action pills (Yelp/Website/Call), always visible alongside the stars so
    // the first expand exposes the spot's links without opening the Edit form.
    // The explicit height collapse keeps the card-height binding correct when
    // no action is available (no dead spacing).
    Column {
      width: parent.width
      spacing: Style.space(8)
      topPadding: Style.space(4)
      visible: ratingEditor.actionRows.length > 0
      height: visible ? implicitHeight : 0
      Repeater {
        model: ratingEditor.actionRows
        delegate: Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(8)
          Repeater {
            model: modelData
            delegate: ActionPill {
              panel: ratingEditor.panel
              icon: modelData.icon
              iconSource: modelData.iconSource
              label: modelData.label
              onActivated: ratingEditor.runAction(modelData.kind)
            }
          }
        }
      }
    }
  }

  // Full form. A Column measures hidden children, so the explicit height
  // collapse is required for the compact state to actually shrink the card.
  Column {
    width: parent.width
    spacing: ratingEditor.spacing
    visible: !ratingEditor.collapsed
    height: visible ? implicitHeight : 0

    Flickable {
      width: parent.width
      // Grow with the notes up to a bounded height, then scroll internally. A
      // fixed 56px box clipped the final wrapped line mid-glyph; sizing to the
      // content (capped) keeps the last line whole for short notes and still
      // bounds the editor for long ones.
      height: Math.min(Math.max(notesEdit.implicitHeight + Style.space(16), Style.space(56)), Style.space(120))
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
        Text { textFormat: Text.PlainText; text: "Notes…"; visible: !notesEdit.text; color: ratingEditor.panel.secondaryColor; font.pixelSize: Style.font.bodySmall; anchors.left: parent.left; anchors.top: parent.top }
      }
    }
    Row {
      width: parent.width
      spacing: Style.space(8)
      topPadding: Style.space(6)
      readonly property int count: hasRating ? 2 : 1
      readonly property real btnW: (width - spacing * (count - 1)) / count
      Rectangle {
        width: parent.btnW; height: Style.space(40)
        radius: Style.cornerRadius
        color: ratingEditor.panel.editStars > 0 ? ratingEditor.panel.accentColor : "transparent"
        border.color: ratingEditor.panel.editStars > 0 ? ratingEditor.panel.accentColor : ratingEditor.panel.secondaryColor
        border.width: 1
        Row { anchors.centerIn: parent; spacing: Style.space(6)
          Text { textFormat: Text.PlainText; text: hasRating ? "\u21bb" : "\u2713"; color: ratingEditor.panel.editStars > 0 ? ratingEditor.panel.accentTextColor : ratingEditor.panel.secondaryColor; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
          Text { textFormat: Text.PlainText; text: "Save"; color: ratingEditor.panel.editStars > 0 ? ratingEditor.panel.accentTextColor : ratingEditor.panel.secondaryColor; font.bold: true; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter }
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
}
