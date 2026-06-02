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

// ── scaleRate / dynamic unit ────────────────────────────────────────

test("scaleRate picks the unit keeping the number in 0–999 (SI 10^3 steps)", () => {
    assert.deepEqual(DiskIo.scaleRate(0), { value: 0, unit: "B/s" });
    assert.deepEqual(DiskIo.scaleRate(850), { value: 850, unit: "B/s" });
    assert.deepEqual(DiskIo.scaleRate(1000), { value: 1, unit: "KB/s" });
    assert.deepEqual(DiskIo.scaleRate(3.4 * MB), { value: 3.4, unit: "MB/s" });
    assert.deepEqual(DiskIo.scaleRate(2.5e9), { value: 2.5, unit: "GB/s" });
});

test("scaleRate coerces negative / NaN to 0 B/s", () => {
    assert.deepEqual(DiskIo.scaleRate(-100), { value: 0, unit: "B/s" });
    assert.deepEqual(DiskIo.scaleRate(NaN), { value: 0, unit: "B/s" });
});

test("formatRateValue is the number only, in the auto-picked unit (one decimal <100, none above)", () => {
    assert.equal(DiskIo.formatRateValue(3.4 * MB), "3.4");   // 3.4 MB/s
    assert.equal(DiskIo.formatRateValue(0), "0.0");          // 0.0 B/s
    assert.equal(DiskIo.formatRateValue(850), "850");        // 850 B/s (≥100 → int)
    assert.equal(DiskIo.formatRateValue(380.2 * MB), "380"); // 380 MB/s
    assert.equal(DiskIo.formatRateValue(2.5e9), "2.5");      // 2.5 GB/s
    assert.equal(DiskIo.formatRateValue(NaN), "0.0");
});

test("formatRateUnit / formatRate scale dynamically from B/s to GB/s", () => {
    assert.equal(DiskIo.formatRateUnit(0), "B/s");
    assert.equal(DiskIo.formatRateUnit(50 * 1000), "KB/s");
    assert.equal(DiskIo.formatRateUnit(3.4 * MB), "MB/s");
    assert.equal(DiskIo.formatRateUnit(2.5e9), "GB/s");
    assert.equal(DiskIo.formatRate(0), "0.0 B/s");
    assert.equal(DiskIo.formatRate(3.4 * MB), "3.4 MB/s");
    assert.equal(DiskIo.formatRate(2.5e9), "2.5 GB/s");
});

test("formatRate coerces NaN / negative to 0 (B/s at zero)", () => {
    assert.equal(DiskIo.formatRate(NaN), "0.0 B/s");
    assert.equal(DiskIo.formatRate(-5 * MB), "0.0 B/s");
});
