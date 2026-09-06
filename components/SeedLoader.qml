import QtQuick
import Quickshell.Io

// Headless seed loader: shells out to bash to emit `city\tjson` lines from
// data/*.jsonl, then parses them in chunked slices so a slow first-run/refresh
// never blocks IPC. The caller owns the catalog state — `loaded` hands back the
// parsed spotsByCity and the caller assigns cities/aliases, flips catalogLoaded,
// and writes state.json.
//
// The parse token is load-bearing (see ChunkedWalk): bumped once per process
// exit and re-read live on every slice, so a second refresh landing mid-parse
// discards the superseded run's leftover slices instead of publishing a
// half-built catalog or leaking slices into the new context.
Item {
  id: root

  // sourceDir is the plugin directory whose data/*.jsonl are seeded. Passed as
  // argv ($1) so bash treats it literally — a HOME containing a space or shell
  // metacharacter can no longer break or inject.
  property string sourceDir: ""
  // $0 handed to the bash loader so its own diagnostics name the command.
  property string loaderName: "seed-loader"
  // Lines parsed per event-loop turn (Qt.callLater). Parsing every seed line in
  // one synchronous onExited handler blocked IPC, so the parse runs in
  // chunkSize-line slices, one per event-loop turn.
  property int chunkSize: 400

  // Emitted with the parsed catalog (city -> [spot]) once the whole seed parse
  // finishes. Fired from the walker's done, never the Process onExited, so it
  // can't fire before the parse completes.
  signal loaded(var spotsByCity)
  signal failed(string message)

  // Discards a superseded parse on a second refresh: bumped once per process
  // exit, re-read live on every slice.
  property int parseToken: 0

  ChunkedWalk { id: chunkWalk }

  function start() {
    seedProc.running = true;
  }

  Process {
    id: seedProc
    command: ["bash", "-c", "for f in \"$1\"/data/*.jsonl; do city=$(basename \"$f\" .jsonl); while IFS= read -r line; do [ -n \"$line\" ] && printf '%s\\t%s\\n' \"$city\" \"$line\"; done < \"$f\"; done", root.loaderName, root.sourceDir]
    stdout: StdioCollector { id: seedStdout; waitForEnd: true }
    stderr: StdioCollector { id: seedStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        console.warn("seed loader failed exit=" + exitCode, String(seedStderr.text || ""));
        root.failed("seed loader failed exit=" + exitCode);
        return;
      }
      var text = String(seedStdout.text || "");
      if (!text) {
        console.warn("seed loader produced no output — no catalog loaded");
        root.failed("seed loader produced no output — no catalog loaded");
        return;
      }
      // Capture the output once (a refresh run resets seedStdout.text) and hand
      // the line array to the chunked parser; the per-line JSON.parse is what's
      // expensive, so the parse — not the split — is what gets chunked.
      root.parseToken++;
      var ctx = {
        index: 0,
        lines: text.split("\n"),
        newSpots: Object.create(null)
      };
      chunkWalk.runChunked({
        getToken: function () { return root.parseToken; },
        chunkSize: root.chunkSize,
        ctx: ctx,
        step: function (ctx) {
          var line = ctx.lines[ctx.index];
          var tabIndex = line.indexOf("\t");
          if (tabIndex >= 0) {
            var city = line.slice(0, tabIndex).trim().toLowerCase();
            var rawJson = line.slice(tabIndex + 1);
            try {
              var entry = JSON.parse(rawJson);
              if (entry && entry.name) {
                // The file stem is the only city key: the entry `city` field is
                // no longer consulted, so a spot always lands under its file.
                if (!ctx.newSpots[city]) ctx.newSpots[city] = [];
                ctx.newSpots[city].push(entry);
              }
            } catch (_) {
              // Malformed JSONL lines are silently skipped.
            }
          }
          ctx.index++;
          return { processed: 1, more: ctx.index < ctx.lines.length };
        },
        done: function (ctx) {
          root.loaded(ctx.newSpots);
        }
      }, root.parseToken);
    }
  }
}
