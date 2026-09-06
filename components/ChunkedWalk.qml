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
      // Reschedule through a closure, not `Qt.callLater(walker.runChunked, opts, token)`:
      // the bare-method-reference form does not reliably re-bind the args in
      // Quickshell, so the next slice can silently never run and the walk stalls
      // after its first chunk (observed: spotsByName never built, Wishlist/Journal
      // empty). The closure captures opts/token explicitly, which is also the
      // first-party convention used across omarchy's own QML.
      Qt.callLater(function() { walker.runChunked(opts, token); });
    } else {
      opts.done(ctx);
    }
  }

  // Shared city×spot cursor walk. Iterates the city-key list returned by
  // `opts.cities(ctx)` and, within each city, every spot in
  // `ctx.spotsByCity[cityKey]`, calling `opts.onSpot(ctx, spot, cityKey)` per
  // spot and `opts.onCityDone(ctx, cityKey)` (optional) each time a city's spots
  // are exhausted — including empty cities, which yield zero spots. Returns the
  // `step(ctx)` function for runChunked: each call consumes exactly one spot (a
  // city-boundary advance is a zero-cost hop, not a processed unit) and reports
  // { processed, more }. The cursor advance and trailing-city-exhausted guard are
  // shared by every walk; only the per-spot body and per-city hook differ.
  function walkSpotsByCity(opts) {
    return function (ctx) {
      var cities = opts.cities(ctx);
      var cityKey = cities[ctx.city];
      var spots = ctx.spotsByCity[cityKey] || [];
      if (ctx.spot >= spots.length) {
        if (opts.onCityDone) opts.onCityDone(ctx, cityKey);
        ctx.spot = 0;
        ctx.city++;
        return { processed: 0, more: ctx.city < cities.length };
      }
      opts.onSpot(ctx, spots[ctx.spot], cityKey);
      ctx.spot++;
      if (ctx.spot >= spots.length) {
        if (opts.onCityDone) opts.onCityDone(ctx, cityKey);
        ctx.spot = 0;
        ctx.city++;
      }
      return { processed: 1, more: ctx.city < cities.length };
    };
  }

  // Shared spot-walk wiring: wraps walkSpotsByCity into runChunked's contract so
  // BarWidget's three walks (catalog stamp, spot index, distance build) pass only
  // their distinct parts — cities/onSpot/onCityDone (the per-spot logic),
  // chunkSize, ctx, and done — while this function owns the getToken/chunkSize/
  // step/done wiring and the captured token. Service.qml's seed parse uses
  // runChunked directly (its step is line-based, not spot-based), so it is
  // untouched.
  function runSpotWalk(opts, token) {
    runChunked({
      getToken: opts.getToken,
      chunkSize: opts.chunkSize,
      ctx: opts.ctx,
      step: walkSpotsByCity({
        cities: opts.cities,
        onSpot: opts.onSpot,
        onCityDone: opts.onCityDone
      }),
      done: opts.done
    }, token);
  }
}
