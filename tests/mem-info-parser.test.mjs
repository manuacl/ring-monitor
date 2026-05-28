// Tests for MemInfoParser.js — pure parser for /proc/meminfo plus the
// shared usagePercent helper reused by the statvfs (disk) path.

import { createRequire } from "node:module";
import { test } from "node:test";
import assert from "node:assert/strict";

const require = createRequire(import.meta.url);
const Parser = require("../contents/ui/platforms/standalone/MemInfoParser.js");

// ── parseMemInfo ────────────────────────────────────────────────────

const NULLS = { total: null, available: null, swapTotal: null, swapFree: null };

test("parseMemInfo returns nulls on null / undefined / empty input", () => {
    assert.deepEqual(Parser.parseMemInfo(null), NULLS);
    assert.deepEqual(Parser.parseMemInfo(undefined), NULLS);
    assert.deepEqual(Parser.parseMemInfo(""), NULLS);
});

test("parseMemInfo extracts MemTotal and MemAvailable in kB", () => {
    const sample =
        "MemTotal:       16275216 kB\n" +
        "MemFree:         2121540 kB\n" +
        "MemAvailable:    9029768 kB\n" +
        "Buffers:           97012 kB\n";
    assert.deepEqual(Parser.parseMemInfo(sample),
        { total: 16275216, available: 9029768, swapTotal: null, swapFree: null });
});

test("parseMemInfo extracts SwapTotal and SwapFree (incl. zram)", () => {
    // Real Bazzite zram sample: 7.8 GiB swap, ~2 GiB used → ~26%.
    const sample =
        "MemTotal:       16275216 kB\n" +
        "MemAvailable:    9029768 kB\n" +
        "SwapCached:         4832 kB\n" +
        "SwapTotal:       8137212 kB\n" +
        "SwapFree:        6026436 kB\n";
    assert.deepEqual(Parser.parseMemInfo(sample),
        { total: 16275216, available: 9029768, swapTotal: 8137212, swapFree: 6026436 });
});

test("parseMemInfo ignores unrelated lines (Buffers, Cached, SwapCached)", () => {
    // SwapCached must NOT be mistaken for SwapTotal/SwapFree — the
    // anchored regex only matches the four exact field names.
    const sample =
        "Buffers:           97012 kB\n" +
        "MemTotal:        8388608 kB\n" +
        "Cached:          1234567 kB\n" +
        "MemAvailable:    4194304 kB\n" +
        "SwapCached:         4832 kB\n";
    assert.deepEqual(Parser.parseMemInfo(sample),
        { total: 8388608, available: 4194304, swapTotal: null, swapFree: null });
});

test("parseMemInfo ignores MemTotal-lookalikes (e.g. MemTotalSomething)", () => {
    // Regex is anchored at line start with a colon — a hypothetical
    // future field that starts with "MemTotal" must not match.
    const sample = "MemTotalSomething: 999 kB\nMemTotal: 100 kB\nMemAvailable: 50 kB\n";
    assert.deepEqual(Parser.parseMemInfo(sample),
        { total: 100, available: 50, swapTotal: null, swapFree: null });
});

test("parseMemInfo: missing MemAvailable leaves the field null", () => {
    // Synthetic input (real /proc/meminfo always has it on kernel >= 3.14)
    // — the parser must not invent a value or fall back to MemFree.
    const sample = "MemTotal: 100 kB\nMemFree: 50 kB\n";
    assert.deepEqual(Parser.parseMemInfo(sample),
        { total: 100, available: null, swapTotal: null, swapFree: null });
});

test("parseMemInfo: malformed number is skipped, not coerced to 0", () => {
    const sample = "MemTotal: abc kB\nMemAvailable: 50 kB\n";
    assert.deepEqual(Parser.parseMemInfo(sample),
        { total: null, available: 50, swapTotal: null, swapFree: null });
});

// ── usagePercent ────────────────────────────────────────────────────

test("usagePercent: standard case", () => {
    // 16 GiB total, 8 GiB available → 50% used.
    assert.equal(Parser.usagePercent(16275216, 8137608), 50);
});

test("usagePercent: 100% when available is 0", () => {
    assert.equal(Parser.usagePercent(100, 0), 100);
});

test("usagePercent: 0% when available equals total", () => {
    assert.equal(Parser.usagePercent(100, 100), 0);
});

test("usagePercent: clamps to [0, 100] for absurd inputs", () => {
    assert.equal(Parser.usagePercent(100, 200), 0);   // over-available → underflow guard
    assert.equal(Parser.usagePercent(100, -50), 100); // negative available → > 100, clamped
});

test("usagePercent: returns 0 when total is null / 0 / negative", () => {
    assert.equal(Parser.usagePercent(null, 50), 0);
    assert.equal(Parser.usagePercent(0, 50), 0);
    assert.equal(Parser.usagePercent(-10, 50), 0);
});

test("usagePercent: returns 0 when available is null / NaN / undefined", () => {
    assert.equal(Parser.usagePercent(100, null), 0);
    assert.equal(Parser.usagePercent(100, NaN), 0);
    assert.equal(Parser.usagePercent(100, undefined), 0);
});

test("usagePercent: swap usage reuses the RAM formula (zram ~26%)", () => {
    // SCENARIO: standalone swap ring read 0 on a host with active zram
    // (the metricValue("swap") path was hardcoded to 0). Swap usage is
    // (SwapTotal - SwapFree) / SwapTotal — exactly usagePercent with
    // available = SwapFree. Real Bazzite sample: 8137212 / 6026436.
    const pct = Parser.usagePercent(8137212, 6026436);
    assert.ok(Math.abs(pct - 25.94) < 0.1, `expected ~26%, got ${pct}`);
});

test("usagePercent: swapless host (SwapTotal 0) reports 0, not NaN", () => {
    // A genuinely swapless machine has SwapTotal: 0 kB; the swap ring
    // must read a clean 0 rather than a NaN sweep.
    assert.equal(Parser.usagePercent(0, 0), 0);
});

test("usagePercent: unit-agnostic — same answer for kB or bytes", () => {
    // The ratio cancels the unit.
    const kB = Parser.usagePercent(16275216, 9029768);
    const bytes = Parser.usagePercent(16275216 * 1024, 9029768 * 1024);
    assert.equal(kB, bytes);
});

// ── diskUsagePercent ────────────────────────────────────────────────

test("diskUsagePercent: matches df on a fresh ext4 (5% root reservation)", () => {
    // SCENARIO: a freshly-formatted 100 GB ext4 root filesystem.
    // - total       = 100 GB (f_blocks)
    // - free        = 100 GB (f_bfree, all blocks unused)
    // - available   = 95 GB  (f_bavail, free minus the 5% root reservation)
    // df shows 0% used. The naive (total - available) / total would
    // report 5% used because the root reservation counts as "used"
    // in that formula. The correct formula treats the reservation
    // as "size invisible to the user" — denom = used + available.
    const total = 100_000_000_000;
    const free = 100_000_000_000;
    const available = 95_000_000_000;
    assert.equal(Parser.diskUsagePercent(total, free, available), 0);
});

test("diskUsagePercent: 50% used when half the user-visible space is consumed", () => {
    // 100 GB total, 50 GB free, 45 GB available (5 GB reserved).
    // used = 50 GB; denom = used + available = 95 GB; pct = 50/95 = 52.63%.
    // Cross-check against `df`: `df` reports 53% for this exact case.
    const pct = Parser.diskUsagePercent(100, 50, 45);
    assert.ok(Math.abs(pct - (50 / 95) * 100) < 1e-9);
});

test("diskUsagePercent: 100% when no available blocks remain", () => {
    // Disk is "full" for the unprivileged user even though f_bfree > 0
    // (root-reserved blocks still free). df shows 100%.
    assert.equal(Parser.diskUsagePercent(100, 5, 0), 100);
});

test("diskUsagePercent: returns 0 on invalid input", () => {
    assert.equal(Parser.diskUsagePercent(null, 50, 40), 0);
    assert.equal(Parser.diskUsagePercent(0, 50, 40), 0);
    assert.equal(Parser.diskUsagePercent(-10, 50, 40), 0);
    assert.equal(Parser.diskUsagePercent(100, null, 40), 0);
    assert.equal(Parser.diskUsagePercent(100, NaN, 40), 0);
    assert.equal(Parser.diskUsagePercent(100, 50, null), 0);
    assert.equal(Parser.diskUsagePercent(100, 50, NaN), 0);
});

test("diskUsagePercent: clamps to [0, 100] for absurd inputs", () => {
    // free > total → used negative → clamped to 0
    assert.equal(Parser.diskUsagePercent(100, 200, 50), 0);
    // available negative → > 100, clamped
    const pct = Parser.diskUsagePercent(100, 0, -50);
    assert.ok(pct === 100 || pct === 0);
});

test("usagePercent + diskUsagePercent: non-finite arithmetic returns 0 (matches RingGeometry.clampPercent)", () => {
    // After the clampPercent dedup, the local _clampPercent guards
    // against `!isFinite` results (Infinity from a divide-by-tiny,
    // NaN from operations that go inconsistent). Returning 0 — same
    // as RingGeometry.clampPercent — surfaces "no data" rather than
    // propagating Infinity into the ring sweep math (which would
    // render a glitched arc). Real /proc + statvfs inputs never
    // trigger this; the guard is defense against future contract
    // drift in the C++ helper.
    assert.equal(Parser.usagePercent(Number.MIN_VALUE, -Number.MAX_VALUE), 0);
    assert.equal(Parser.diskUsagePercent(Number.MIN_VALUE, 0, -Number.MAX_VALUE), 0);
});

test("diskUsagePercent: differs from usagePercent on reserved filesystems", () => {
    // Same 100 / 95 (total / available) inputs, freshly empty:
    // - usagePercent says 5% (counts reservation as used)
    // - diskUsagePercent says 0% (matches df)
    // The 5% gap is exactly the ext4 root reservation. This test
    // guards the regression where someone "simplifies" the disk
    // path back to usagePercent.
    assert.equal(Parser.usagePercent(100, 95), 5);
    assert.equal(Parser.diskUsagePercent(100, 100, 95), 0);
});
