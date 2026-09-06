import QtQuick
import qs.Commons

// Expanded rating form for one spot: a notes editor and the Remove-rating action.
// The star control lives in the score block (top-right) — it is the single
// star row in both card states, so the editor never repeats it. `panel` is the
// BarWidget root (colors, helpers, actions). The form has no actions of its
// own — the phone action lives in the collapsed card's action cluster.
//
// Everything auto-saves: a star click commits immediately through rateSpot,
// and notes stage on every keystroke via panel.notesEdited() then commit on a
// debounce via panel.flushNotes(). There is no Save button — a transient
// "Notes saved" label confirms a notes commit instead. Notes only exist on a rated
// spot (the IPC rate call carries a rating), so the notes box stays disabled
// until the spot is rated.
Column {
  id: ratingEditor

  property Item panel
  property string spotName: ""
  property string spotCityKey: ""
  // Formatted visit date ("Sep 15") for the spot's journal entry, shown above
  // the notes editor so the rating's date stays visible without crowding the
  // card's place row. Passed in by SpotCard (which derives it from journalEntry).
  property string ratedDate: ""
  // The spot's most recent journal entry ({ rating, notes, timestamp } or null),
  // passed in by SpotCard, which derives it once with the explicit `panel.journal`
  // tracked read. Consumed here rather than re-derived via latestJournalFor, so
  // the editor and the card can never disagree on what "the latest entry" is.
  property var journalEntry
  readonly property bool hasRating: !!journalEntry

  // Gates the notes onTextChanged handler. Component.onCompleted seeds
  // notesEdit.text from the journal, and that programmatic set fires
  // onTextChanged exactly like a user keystroke (verified under QJSEngine) —
  // without this guard a fresh expand would stage the stored notes and commit a
  // spurious re-rate once the debounce expires.
  property bool notesSeeded: false

  // No left/right anchors here: SpotCard mounts this editor inside a Loader,
  // and a Loader already sizes its item. Anchoring the item's own edges fights
  // that sizing, so the painted geometry and the hit-test geometry can diverge
  // (the "Edit" pill looked fine but would not click). The Loader owns the
  // width; this root only supplies the vertical metrics.
  spacing: Style.space(6)
  topPadding: Style.space(10)
  bottomPadding: Style.space(8)

  // Seed the notes field from the journal once, before it accepts edits. Runs
  // after every child is created, so notesEdit is reachable; `notesSeeded` keeps
  // this set from staging a commit.
  Component.onCompleted: {
    var entry = ratingEditor.journalEntry;
    notesEdit.text = entry ? (entry.notes || "") : "";
    ratingEditor.notesSeeded = true;
  }

  // Notes box + Remove rating, always shown while the card is expanded. A Column
  // reports its natural height, so the editor's implicitHeight (which drives
  // the expanded card height) includes this block unconditionally.
  Column {
    width: parent.width
    spacing: ratingEditor.spacing

    // Rated date, above the notes box — the "rated <date>" that no longer leads
    // the place row in the browse tabs. Muted, so the notes stay the focus.
    Text {
      textFormat: Text.PlainText
      visible: ratingEditor.ratedDate !== ""
      width: parent.width
      text: "rated " + ratingEditor.ratedDate
      color: panel.secondaryColor
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    // Notes box. The "Notes saved" label is a sibling overlay pinned to this wrapper
    // (not the Flickable's scrolling content), so it stays put while the box
    // scrolls and never shifts the layout when it appears or fades.
    Item {
      width: parent.width
      // Grow with the notes up to a bounded height, then scroll internally. A
      // fixed 56px box clipped the final wrapped line mid-glyph; sizing to the
      // content (capped) keeps the last line whole for short notes and still
      // bounds the editor for long ones.
      height: Math.min(Math.max(notesEdit.implicitHeight + Style.space(16), Style.space(56)), Style.space(120))
      Flickable {
        anchors.fill: parent
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
          // Disabled until the spot has a rating: notes have no representation
          // on an unrated spot (the IPC rate call requires a rating), so the
          // box cannot hold them.
          enabled: ratingEditor.hasRating
          onTextChanged: {
            if (!ratingEditor.notesSeeded) return;
            ratingEditor.panel.notesEdited(ratingEditor.spotName, text, ratingEditor.spotCityKey);
          }
          wrapMode: TextEdit.Wrap
          selectByMouse: true
          Text { textFormat: Text.PlainText; text: ratingEditor.hasRating ? "Add notes…" : "Rate this spot to add notes"; visible: !notesEdit.text; color: ratingEditor.panel.secondaryColor; font.pixelSize: Style.font.bodySmall; anchors.left: parent.left; anchors.top: parent.top }
        }
      }
      Text {
        textFormat: Text.PlainText
        text: "Notes saved"
        visible: ratingEditor.panel.notesJustSaved
        color: ratingEditor.panel.secondaryColor
        font.pixelSize: Style.font.caption
        anchors.right: parent.right; anchors.rightMargin: Style.space(12)
        anchors.top: parent.top; anchors.topMargin: Style.space(8)
      }
    }

    // Remove rating spans the full editor width now that Save is gone.
    Row {
      width: parent.width
      topPadding: Style.space(6)
      Rectangle {
        visible: hasRating
        width: parent.width; height: Style.space(40)
        radius: Style.cornerRadius
        color: "transparent"
        border.color: ratingEditor.panel.dangerBorder
        border.width: 1
        Text { textFormat: Text.PlainText; anchors.centerIn: parent; text: "Remove rating"; color: ratingEditor.panel.dangerColor; font.bold: true; font.pixelSize: Style.font.bodySmall }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (!spotName) return;
            // Flush pending notes first so the undo snapshot the unrate takes
            // still carries the user's last edit, then drop the rating.
            ratingEditor.panel.flushNotes();
            ratingEditor.panel.unrateSpot(spotName, spotCityKey);
            if (!ratingEditor.panel.spotlight) ratingEditor.panel.collapseRow();
          }
        }
      }
    }
  }
}
