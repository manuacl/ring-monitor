// TDD spec for ProcStatParser.
//
// Run:  node --test tests/proc-stat-parser.test.mjs
//
// Implementation: contents/ui/platforms/standalone/ProcStatParser.js.
// Dual-loaded by QML (standalone MetricsBackend) and Node via the
// module.exports shim at the bottom.

import { createRequire } from "node:module";
import { test } from "node:test";
import assert from "node:assert/strict";

const require = createRequire(import.meta.url);
const Parser = require("../contents/ui/platforms/standalone/ProcStatParser.js");

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

// ── SCENARIO: `cpu`-prefixed non-CPU lines must not perturb the parse ──

test("SCENARIO: `cpufreq` and other cpu-prefixed metadata lines are ignored", () => {
    // Review finding 🟠 PR #29: the outer guard `line.indexOf("cpu") !== 0`
    // accepted `cpufreq 2400 …`, `cpu_avg_freq …`, etc. — these fed
    // through the inner parser, parseInt'd their fields, and only got
    // discarded later because no branch claimed them. After the fix
    // (regex `^cpu(\d*)\b`), those lines are rejected at the gate.
    // The output is identical pre/post-fix (no behavior regression) —
    // this SCENARIO locks the regression guard in place so a future
    // refactor doesn't loosen the gate back.
    const sample = [
        "cpu  300 0 150 2400 30 0 0 0",
        "cpu0 100 0 50 800 10 0 0 0",
        "cpufreq 2400 3200 1800",                 // synthetic — not a real /proc/stat line
        "cpu_avg_freq 2000",                       // synthetic
        "cpuidle 12345",                           // synthetic
        "cpu1 100 0 50 800 10 0 0 0",
        "intr 5",
        ""
    ].join("\n");
    const result = Parser.parseProcStat(sample);
    // Aggregate and the two real cores parsed cleanly; the synthetic
    // lookalikes did not become extra `cores` entries and did not
    // overwrite `all`.
    assert.deepEqual(result.all, [300, 0, 150, 2400, 30, 0, 0, 0]);
    assert.equal(result.cores.length, 2);
    assert.deepEqual(result.cores[0], [100, 0, 50, 800, 10, 0, 0, 0]);
    assert.deepEqual(result.cores[1], [100, 0, 50, 800, 10, 0, 0, 0]);
});

test("SCENARIO: post-s2idle resume with stale per-core counters returns 0%", () => {
    // After the laptop wakes from s2idle, some per-core counters can
    // look "older" than the aggregate (the kernel resumed the core
    // partway through tick accounting). If `cur` ends up numerically
    // smaller than `prev` for any core, `dTotal <= 0` short-circuits
    // to 0 — the ring shows "idle" for that tick instead of a NaN /
    // negative-going gauge. Reproduces a real wakeup pattern reported
    // upstream (LKML 2023) where /proc/stat samples taken too close
    // to resume show a per-core regression vs. the pre-sleep sample.
    const preSleep  = [200, 0, 80, 1200, 5, 0, 0, 0];   // core was busy before sleep
    const postWake  = [195, 0, 78, 1199, 4, 0, 0, 0];   // counters slightly lower (or unchanged) right after resume
    assert.equal(Parser.percentFromSample(preSleep, postWake), 0,
        "post-resume regression must clamp to 0, not propagate a negative pct");
});

test("SCENARIO: core hotplug-out — parser produces a shorter cores array without throwing", () => {
    // Live core hotplug-out (echo 0 > /sys/devices/system/cpu/cpu3/online)
    // drops `cpu3` from /proc/stat between samples. parseProcStat must
    // produce a shorter `cores` array without inventing values. The
    // downstream length-mismatch handling in MetricsBackend
    // (Math.min(prev, cur) in MetricsBackend.qml) is NOT covered by
    // this test — it's only the parser side that's guarded here.
    const beforeHotplug = [
        "cpu  400 0 200 3200 40 0 0 0",
        "cpu0 100 0 50 800 10 0 0 0",
        "cpu1 100 0 50 800 10 0 0 0",
        "cpu2 100 0 50 800 10 0 0 0",
        "cpu3 100 0 50 800 10 0 0 0",
        ""
    ].join("\n");
    const afterHotplug = [
        "cpu  301 0 151 2401 31 0 0 0",
        "cpu0 101 0 51 801 11 0 0 0",
        "cpu1 100 0 50 800 10 0 0 0",
        "cpu2 100 0 50 800 10 0 0 0",
        // cpu3 missing — hotplugged out
        ""
    ].join("\n");
    const before = Parser.parseProcStat(beforeHotplug);
    const after = Parser.parseProcStat(afterHotplug);
    assert.equal(before.cores.length, 4);
    assert.equal(after.cores.length, 3, "hotplug-out must yield a shorter cores array, not throw");
    // Sanity: the surviving cores are still index-ordered and intact.
    assert.deepEqual(after.cores[0], [101, 0, 51, 801, 11, 0, 0, 0]);
});

test("SCENARIO: core hotplug-in — new core appears late, percentFromSample tolerates missing fields", () => {
    // Reverse case: echo 1 > /sys/devices/system/cpu/cpu3/online
    // re-introduces a core. The first sample after hotplug-in has
    // counters that started from 0 (or a small post-init value);
    // percentFromSample against the missing-prev case (zero-length
    // prev) returns 0 — the MetricsBackend skips that core for one
    // tick, then the next tick has both prev and cur for the new
    // core and percent computes normally.
    const freshlyOnline = [50, 0, 25, 400, 5, 0, 0, 0];
    assert.equal(Parser.percentFromSample([], freshlyOnline), 0,
        "missing prev (newly-online core) must yield 0, not crash on prev.length===0");
});

test("SCENARIO: a hypothetical `cpu99X` line is rejected (word-boundary check)", () => {
    // The `\b` boundary on `^cpu(\d*)\b` prevents `cpu99extra` from
    // being parsed as core 99. Real /proc/stat doesn't emit such a
    // line today, but the guard is cheap and a future kernel change
    // could.
    const sample = [
        "cpu  100 0 50 800 10",
        "cpu0 50 0 25 400 5",
        "cpu99extra 1 2 3",   // synthetic — must NOT become core 99
        ""
    ].join("\n");
    const result = Parser.parseProcStat(sample);
    assert.equal(result.cores.length, 1, "only the real cpu0 line should yield a core");
});
