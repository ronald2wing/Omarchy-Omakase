// tests/_assert.js — shared test harness. assert() accumulates pass/fail counts
// and prints a FAIL line per failure; report() prints the summary and exits
// non-zero on any failure.
let passed = 0, failed = 0;

function assert(label, cond) {
  if (cond) { passed++; } else { console.log("FAIL: " + label); failed++; }
}

function report() {
  console.log("tests " + (passed + failed));
  console.log("pass " + passed);
  console.log("fail " + failed);
  if (failed) process.exit(1);
}

module.exports = { assert, report };
