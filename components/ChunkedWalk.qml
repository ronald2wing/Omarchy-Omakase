import QtQuick

// Shared chunked-walk scaffold, imported by both Service.qml (seed parse) and
// BarWidget.qml (catalog stamp, spot index, distance build) so the two
// processes share one token/chunk/reschedule/publish implementation.
//
// A long synchronous job is split into chunkSize-unit slices that run one per
// event-loop turn and yield via Qt.callLater, so startup/home-move builds never
// freeze the UI. `token` is the value captured when the run started;
// `getToken()` returns the live token, so a superseded run's leftover slices
// no-op instead of publishing stale state. `step(ctx)` consumes one unit and
// returns { processed, more }; `done(ctx)` publishes atomically only when the
// cursor is exhausted and the token still matches, so readers never observe a
// partial result.
//
// The token logic is load-bearing: each caller bumps its own token before
// starting a run and passes the bumped value here, and `getToken` re-reads the
// live token every slice so a newer run discards an older in-flight one. Do not
// merge runs or drop the supersede check.
QtObject {
  id: walker

  function runChunked(opts, token) {
    if (token !== opts.getToken()) return;
    var ctx = opts.ctx;
    var processed = 0;
    var more = true;
    while (more && processed < opts.chunkSize) {
      var res = opts.step(ctx);
      processed += res.processed;
      more = res.more;
    }
    if (token !== opts.getToken()) return;
    if (more) {
      Qt.callLater(walker.runChunked, opts, token);
    } else {
      opts.done(ctx);
    }
  }
}
