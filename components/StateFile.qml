import QtQuick
import Quickshell.Io
import "../lib/spot-utils.js" as SpotUtils

// Shared state-file read wrapper. BarWidget (state.json, journal.json,
// wishlist.json) and Service (journal.json, user_spots.json, undo.json,
// weather.json, state.json) each watch a state file with byte-identical
// boilerplate, differing only in `path` and the load handler. This component
// owns that shape and re-exposes the outcomes as `parsed(content)`, `missing()`,
// and `oversized()`, so each call site shrinks to `path` + a few handlers.
//
// WHY the read never goes through FileView: Quickshell FileView has no byte
// ceiling and materializes the whole file into shared-shell memory on read, so
// an oversized state file can exhaust the shell. This component keeps a
// `preload: false` FileView solely as a *change notifier* (`watchChanges`) and
// *write adapter* (`setText`/`saved`/`atomicWrites`) — it never calls
// text()/data()/reload(), so it never loads the file. Every read instead goes
// through the bounded `Process` below, whose `head -c $maxBytes` caps stdout at
// MAX_STATE_BYTES (4 MiB) regardless of the file's on-disk size. A file larger
// than the cap emits `oversized()` (the first maxBytes are still bounded, then
// discarded) so a call site can keep its previous state / reseed / fold to
// no-location rather than parse a truncated blob.
//
// The root is an Item (not a FileView) because FileView's default property is
// its `adapter` (a FileViewAdapter) — it cannot hold a child Process. The Item
// forwards the FileView surface (`path`, `atomicWrites`, `watchChanges`,
// `setText`, `saved`) so existing call sites are unchanged.
Item {
  id: root

  // Forwarded FileView surface. `atomicWrites` defaults to true (FileView's own
  // default) and `watchChanges` defaults to true (the old StateFile.qml fixed it
  // to true), matching the shape every extracted block carried; call sites
  // override watchChanges for the service-owned state.json.
  property string path: ""
  property bool atomicWrites: true
  property bool watchChanges: true
  property int maxBytes: SpotUtils.MAX_STATE_BYTES

  signal parsed(string content)
  signal missing()
  signal oversized()
  signal saved()

  property bool _reading: false
  property bool _dirty: false

  function setText(text) {
    view.setText(text);
  }

  function requestRead() {
    if (root._reading) { root._dirty = true; return; }
    if (!root.path) { root.missing(); return; }
    root._reading = true;
    reader.running = true;
  }

  FileView {
    id: view
    path: root.path
    atomicWrites: root.atomicWrites
    watchChanges: root.watchChanges
    preload: false
    printErrors: false

    // Re-emit the write-completion signal so Service's owner-only chmod hooks
    // keep firing post-save (post-atomic-rename) exactly as before.
    onSaved: root.saved()

    // The FileView is a change notifier only: any external rewrite triggers a
    // bounded re-read instead of FileView's unbounded reload().
    onFileChanged: root.requestRead()
  }

  Process {
    id: reader
    // $1 = file, $2 = max bytes. stdout carries at most $2 bytes (head -c);
    // stderr carries a one-word status: "missing" (exit 3, file unreadable),
    // "read-error" (exit 1, head failed after the -r check), or "oversized".
    // The oversized probe reads only a single byte past the cap and counts it
    // with `wc -c` (bytes, not locale characters), so it stays correct for NUL,
    // newline, and multibyte bytes while keeping memory bounded.
    command: ["bash", "-c",
      "f=\"$1\"; m=\"$2\"; " +
      "[ -r \"$f\" ] || { printf 'missing' >&2; exit 3; }; " +
      "head -c \"$m\" \"$f\" || { printf 'read-error' >&2; exit 1; }; " +
      "if [ \"$(tail -c +$((m+1)) \"$f\" | head -c 1 | wc -c)\" -gt 0 ]; then printf 'oversized' >&2; fi",
      "_", root.path, String(root.maxBytes)]
    stdout: StdioCollector { id: out; waitForEnd: true }
    stderr: StdioCollector { id: err; waitForEnd: true }
    onExited: function(code) {
      root._reading = false;
      var status = String(err.text || "").trim();
      if (status === "oversized") root.oversized();
      else if (status === "missing" || code !== 0) root.missing();
      else root.parsed(String(out.text || ""));
      if (root._dirty) { root._dirty = false; root.requestRead(); }
    }
  }

  Component.onCompleted: root.requestRead()
}
