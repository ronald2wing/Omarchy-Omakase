// tests/_assert.js — shared test harness. assert() accumulates pass/fail counts
// and prints a FAIL line per failure; assertEq() prints expected vs actual;
// report() prints the summary and exits non-zero on any failure.
let passed = 0, failed = 0;

function show(value) {
  return value === undefined ? "undefined" : JSON.stringify(value);
}

// Shared failure printer. When expected/actual are available the message
// carries them (so a failure is diagnosable without re-running); otherwise it
// prints the label alone.
function fail(label, actual, expected, hasValues) {
  if (hasValues) {
    console.log("FAIL: " + label + " — expected " + show(expected) + ", got " + show(actual));
  } else {
    console.log("FAIL: " + label);
  }
  failed++;
}

function assert(label, cond) {
  if (cond) { passed++; return; }
  fail(label);
}

// Diagnostic equality check: on failure both values are printed so a
// contributor sees what the code returned, not just the label.
function assertEq(label, actual, expected) {
  if (actual === expected) { passed++; return; }
  fail(label, actual, expected, true);
}

function report() {
  console.log("tests " + (passed + failed));
  console.log("pass " + passed);
  console.log("fail " + failed);
  if (failed) process.exit(1);
}

module.exports = { assert, assertEq, report };
