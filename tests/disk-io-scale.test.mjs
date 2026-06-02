// TDD spec for DiskIoScale (issue #77 — disk-I/O ring scaling).
//
// Run:  node --test tests/disk-io-scale.test.mjs
//
// Implementation: contents/ui/core/DiskIoScale.js. Shared by both
// platform backends (Plasma ksysguard rates + standalone diskstats
// rates), so it lives in core/.

import { createRequire } from "node:module";
import { test } from "node:test";
import assert from "node:assert/strict";

const require = createRequire(import.meta.url);
const DiskIo = require("../contents/ui/core/DiskIoScale.js");

const MB = DiskIo.BYTES_PER_MB;

// ── combinedRate ────────────────────────────────────────────────────

test("combinedRate sums read + write", () => {
    assert.equal(DiskIo.combinedRate(30 * MB, 20 * MB), 50 * MB);
});

test("combinedRate coerces NaN / undefined / negative halves to 0", () => {
    assert.equal(DiskIo.combinedRate(NaN, 5 * MB), 5 * MB);
    assert.equal(DiskIo.combinedRate(undefined, undefined), 0);
    assert.equal(DiskIo.combinedRate(-100, 5 * MB), 5 * MB);
});

// ── updatePeak ──────────────────────────────────────────────────────

test("updatePeak never drops below the floor", () => {
    assert.equal(DiskIo.updatePeak(0, 0), DiskIo.PEAK_FLOOR_BPS);
    assert.equal(DiskIo.updatePeak(1 * MB, 0), DiskIo.PEAK_FLOOR_BPS);
});

test("updatePeak rises immediately to a faster live rate", () => {
    assert.equal(DiskIo.updatePeak(50 * MB, 500 * MB), 500 * MB);
});

test("updatePeak decays the previous peak when the rate sits below it", () => {
    // rate below peak → peak = prev * PEAK_DECAY (above the floor here).
    const peak = DiskIo.updatePeak(500 * MB, 100 * MB);
    assert.equal(peak, 500 * MB * DiskIo.PEAK_DECAY);
    assert.ok(peak < 500 * MB, "decays");
    assert.ok(peak > 100 * MB, "still above the current rate");
});

test("updatePeak repeated idle decays toward the floor, not below", () => {
    let peak = 1000 * MB;
    for (let i = 0; i < 1000; i++) peak = DiskIo.updatePeak(peak, 0);
    assert.equal(peak, DiskIo.PEAK_FLOOR_BPS);
});

test("updatePeak coerces NaN inputs", () => {
    assert.equal(DiskIo.updatePeak(NaN, NaN), DiskIo.PEAK_FLOOR_BPS);
});

// ── rateToPercent ───────────────────────────────────────────────────

test("rateToPercent fills proportionally against the peak", () => {
    assert.equal(DiskIo.rateToPercent(50 * MB, 100 * MB), 50);
    assert.equal(DiskIo.rateToPercent(100 * MB, 100 * MB), 100);
    assert.equal(DiskIo.rateToPercent(0, 100 * MB), 0);
});

test("rateToPercent clamps above the peak to 100", () => {
    assert.equal(DiskIo.rateToPercent(200 * MB, 100 * MB), 100);
});

test("rateToPercent returns 0 for non-positive / non-finite peak", () => {
    assert.equal(DiskIo.rateToPercent(50 * MB, 0), 0);
    assert.equal(DiskIo.rateToPercent(50 * MB, NaN), 0);
    assert.equal(DiskIo.rateToPercent(50 * MB, -1), 0);
});

// ── formatRate ──────────────────────────────────────────────────────

test("formatRateValue is the number only (no unit) — the ring renders the unit separately", () => {
    assert.equal(DiskIo.formatRateValue(3.4 * MB), "3.4");
    assert.equal(DiskIo.formatRateValue(0), "0.0");
    assert.equal(DiskIo.formatRateValue(380.2 * MB), "380");
    assert.equal(DiskIo.formatRateValue(NaN), "0.0");
});

test("formatRate appends the MB/s unit to formatRateValue", () => {
    assert.equal(DiskIo.formatRate(3.4 * MB), "3.4 MB/s");
    assert.equal(DiskIo.formatRate(0), "0.0 MB/s");
});

test("formatRate drops the decimal at/above 100 MB/s", () => {
    assert.equal(DiskIo.formatRate(380.2 * MB), "380 MB/s");
    assert.equal(DiskIo.formatRate(100 * MB), "100 MB/s");
});

test("formatRate coerces NaN / negative to 0", () => {
    assert.equal(DiskIo.formatRate(NaN), "0.0 MB/s");
    assert.equal(DiskIo.formatRate(-5 * MB), "0.0 MB/s");
});
