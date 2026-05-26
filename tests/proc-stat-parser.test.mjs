// TDD spec for ProcStatParser.
//
// Run:  node --test tests/proc-stat-parser.test.mjs
//
// Implementation: contents/ui/core/ProcStatParser.js. Dual-loaded by
// QML (standalone MetricsBackend) and Node via the module.exports
// shim at the bottom.

import { createRequire } from "node:module";
import { test } from "node:test";
import assert from "node:assert/strict";

const require = createRequire(import.meta.url);
const Parser = require("../contents/ui/core/ProcStatParser.js");

// ── parseProcStat ───────────────────────────────────────────────────

test("parseProcStat returns empty on null / undefined / empty input", () => {
    assert.deepEqual(Parser.parseProcStat(null), { all: null, cores: [] });
    assert.deepEqual(Parser.parseProcStat(undefined), { all: null, cores: [] });
    assert.deepEqual(Parser.parseProcStat(""), { all: null, cores: [] });
});

test("parseProcStat extracts the aggregate cpu line", () => {
    const sample = "cpu  100 0 50 800 10 0 0 0\nintr 5\n";
    const result = Parser.parseProcStat(sample);
    assert.deepEqual(result.all, [100, 0, 50, 800, 10, 0, 0, 0]);
});

test("parseProcStat extracts per-core lines and orders them by index", () => {
    const sample = [
        "cpu  300 0 150 2400 30 0 0 0",
        "cpu1 100 0 50 800 10 0 0 0",
        "cpu0 100 0 50 800 10 0 0 0",
        "cpu2 100 0 50 800 10 0 0 0",
        "intr 5",
        ""
    ].join("\n");
    const result = Parser.parseProcStat(sample);
    assert.equal(result.cores.length, 3);
    // Index-ordered: cpu0, cpu1, cpu2
    assert.deepEqual(result.cores[0], [100, 0, 50, 800, 10, 0, 0, 0]);
    assert.deepEqual(result.cores[1], [100, 0, 50, 800, 10, 0, 0, 0]);
    assert.deepEqual(result.cores[2], [100, 0, 50, 800, 10, 0, 0, 0]);
});

test("parseProcStat ignores non-cpu lines (intr, ctxt, btime, …)", () => {
    const sample = [
        "cpu  100 0 50 800",
        "cpu0 100 0 50 800",
        "intr 1234 5 6 7 8 9 10",
        "ctxt 99999",
        "btime 1700000000",
        "processes 12345",
        "procs_running 2"
    ].join("\n");
    const result = Parser.parseProcStat(sample);
    assert.ok(result.all);
    assert.equal(result.cores.length, 1);
});

test("parseProcStat tolerates missing optional fields (older kernels)", () => {
    // Pre-2.6.33 kernels: no `steal`. Pre-2.6.24: no `iowait` / `irq` /
    // `softirq` either. percentFromSample handles this via `prev[3]
    // || 0`; the parser just produces whatever the line gives.
    const sample = "cpu  100 0 50 800\ncpu0 100 0 50 800\n";
    const result = Parser.parseProcStat(sample);
    assert.equal(result.all.length, 4);
    assert.equal(result.cores[0].length, 4);
});

test("parseProcStat does NOT match `cpufreq` or other cpu*-prefixed non-time lines", () => {
    // The regex pinned to `^cpu(\d+)$` prevents partial matches.
    const sample = [
        "cpu  100 0 50 800",
        "cpufreq 12345",
        "cpu_avg_freq 2400"
    ].join("\n");
    const result = Parser.parseProcStat(sample);
    assert.equal(result.cores.length, 0);
    assert.ok(result.all);
});

// ── percentFromSample ───────────────────────────────────────────────

test("percentFromSample returns 0 on null / empty samples", () => {
    assert.equal(Parser.percentFromSample(null, null), 0);
    assert.equal(Parser.percentFromSample([], [100, 0, 50, 800]), 0);
    assert.equal(Parser.percentFromSample([100, 0, 50, 800], []), 0);
});

test("percentFromSample returns 0 when samples are identical (no time elapsed)", () => {
    const s = [100, 0, 50, 800, 10, 0, 0, 0];
    assert.equal(Parser.percentFromSample(s, s), 0);
});

test("percentFromSample returns 0 when only idle ticked", () => {
    // 100 idle ticks accumulated, nothing else. usage = 0%.
    const prev = [100, 0, 50, 800, 10, 0, 0, 0];
    const cur = [100, 0, 50, 900, 10, 0, 0, 0];
    assert.equal(Parser.percentFromSample(prev, cur), 0);
});

test("percentFromSample returns 100 when only active fields ticked", () => {
    // 100 user ticks, no idle progression.
    const prev = [100, 0, 50, 800, 10, 0, 0, 0];
    const cur = [200, 0, 50, 800, 10, 0, 0, 0];
    assert.equal(Parser.percentFromSample(prev, cur), 100);
});

test("percentFromSample handles a 30/70 active/idle split", () => {
    // user +30, idle +70 → 30/100 → 30%. Allow a tiny epsilon for
    // float arithmetic — JS does the division before the multiply
    // and (1 - 70/100) * 100 lands at 30.000000000000004.
    const prev = [100, 0, 50, 800];
    const cur = [130, 0, 50, 870];
    const result = Parser.percentFromSample(prev, cur);
    assert.ok(Math.abs(result - 30) < 0.001, `expected ~30, got ${result}`);
});

test("percentFromSample treats iowait as idle", () => {
    // 100 ticks of iowait, no user → 0% usage (same logic as top(1)).
    const prev = [100, 0, 50, 800, 10, 0, 0, 0];
    const cur = [100, 0, 50, 800, 110, 0, 0, 0];
    assert.equal(Parser.percentFromSample(prev, cur), 0);
});

test("percentFromSample clamps negative-going deltas to 0 (counter wraparound)", () => {
    // Highly unlikely on a 64-bit counter, but defended for safety.
    const prev = [200, 0, 50, 800];
    const cur = [100, 0, 50, 700];  // total went down
    assert.equal(Parser.percentFromSample(prev, cur), 0);
});

test("percentFromSample handles samples with missing optional fields", () => {
    // Old kernel format: only [user, nice, system, idle]. user +50,
    // idle +50 → 50% (within float epsilon).
    const prev = [100, 0, 50, 800];
    const cur = [150, 0, 50, 850];
    const result = Parser.percentFromSample(prev, cur);
    assert.ok(Math.abs(result - 50) < 0.001, `expected ~50, got ${result}`);
});
