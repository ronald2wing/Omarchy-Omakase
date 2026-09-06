import QtQuick
import Quickshell.Io

// Shared state-file read wrapper. BarWidget (state.json, journal.json,
// wishlist.json) and Service (journal.json, user_spots.json, undo.json) each
// watch a handful of state files with byte-identical FileView boilerplate —
// `watchChanges: true; printErrors: false; onFileChanged: reload()` — differing
// only in `path` and the load handler. This component owns that shape and
// re-exposes the two load outcomes as `parsed(content)` and `missing()`, so each
// remaining block shrinks to `path` + two handlers.
//
// The root IS a FileView (not a wrapper around one), so `path`, `atomicWrites`,
// the `saved` signal, and the setText()/reload() methods pass through natively:
// Service's writeJournal/saveUndoSnapshot still call setText() on the instance,
// and the owner-only chmod still hooks the `saved` signal exactly as before.
// `watchChanges` and `printErrors` are fixed here because every extracted block
// carried the same values.
FileView {
  id: root

  watchChanges: true
  printErrors: false

  signal parsed(string content)
  signal missing()

  onLoaded: root.parsed(text())
  onLoadFailed: root.missing()
  onFileChanged: reload()
}
