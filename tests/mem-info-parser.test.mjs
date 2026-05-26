// Tests for MemInfoParser.js — pure parser for /proc/meminfo plus the
// shared usagePercent helper reused by the statvfs (disk) path.

import { createRequire } from "node:module";
import { test } from "node:test";
import assert from "node:assert/strict";

const require = createRequire(import.meta.url);
const Parser = require("../contents/ui/core/MemInfoParser.js");

// ── parseMemInfo ────────────────────────────────────────────────────

test("parseMemInfo returns nulls on null / undefined / empty input", () => {
    assert.deepEqual(Parser.parseMemInfo(null), { total: null, available: null });
    assert.deepEqual(Parser.parseMemInfo(undefined), { total: null, available: null });
    assert.deepEqual(Parser.parseMemInfo(""), { total: null, available: null });
});

test("parseMemInfo extracts MemTotal and MemAvailable in kB", () => {
    const sample =
        "MemTotal:       16275216 kB\n" +
        "MemFree:         2121540 kB\n" +
        "MemAvailable:    9029768 kB\n" +
        "Buffers:           97012 kB\n";
    assert.deepEqual(Parser.parseMemInfo(sample), { total: 16275216, available: 9029768 });
});

test("parseMemInfo ignores other lines (Buffers, Cached, SwapTotal, …)", () => {
    const sample =
        "Buffers:           97012 kB\n" +
        "MemTotal:        8388608 kB\n" +
        "Cached:          1234567 kB\n" +
        "MemAvailable:    4194304 kB\n" +
        "SwapTotal:       2097152 kB\n";
    assert.deepEqual(Parser.parseMemInfo(sample), { total: 8388608, available: 4194304 });
});

test("parseMemInfo ignores MemTotal-lookalikes (e.g. MemTotalSomething)", () => {
    // Regex is anchored at line start with a colon — a hypothetical
    // future field that starts with "MemTotal" must not match.
    const sample = "MemTotalSomething: 999 kB\nMemTotal: 100 kB\nMemAvailable: 50 kB\n";
    assert.deepEqual(Parser.parseMemInfo(sample), { total: 100, available: 50 });
});

test("parseMemInfo: missing MemAvailable leaves the field null", () => {
    // Synthetic input (real /proc/meminfo always has it on kernel >= 3.14)
    // — the parser must not invent a value or fall back to MemFree.
    const sample = "MemTotal: 100 kB\nMemFree: 50 kB\n";
    assert.deepEqual(Parser.parseMemInfo(sample), { total: 100, available: null });
});

test("parseMemInfo: malformed number is skipped, not coerced to 0", () => {
    const sample = "MemTotal: abc kB\nMemAvailable: 50 kB\n";
    assert.deepEqual(Parser.parseMemInfo(sample), { total: null, available: 50 });
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

test("usagePercent: unit-agnostic — same answer for kB or bytes", () => {
    // The ratio cancels the unit. This is what lets the statvfs (disk)
    // path reuse the same helper without converting bytes → kB.
    const kB = Parser.usagePercent(16275216, 9029768);
    const bytes = Parser.usagePercent(16275216 * 1024, 9029768 * 1024);
    assert.equal(kB, bytes);
});
