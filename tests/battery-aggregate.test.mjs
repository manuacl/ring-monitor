import { test } from "node:test";
import assert from "node:assert/strict";
import { aggregate } from "../contents/ui/core/BatteryAggregate.js";

// Pure aggregation logic for the battery ring. The platform backends supply
// records; this module folds them into a single { percent, charging, available }.

test("empty input → available=false, percent=0, charging=false", () => {
    const r = aggregate([]);
    assert.equal(r.available, false);
    assert.equal(r.percent, 0);
    assert.equal(r.charging, false);
});

test("null / undefined / missing input → available=false", () => {
    assert.equal(aggregate(null).available, false);
    assert.equal(aggregate(undefined).available, false);
});

test("single battery, discharging", () => {
    const r = aggregate([{ percent: 75, weight: 1000, charging: false }]);
    assert.equal(r.available, true);
    assert.equal(r.percent, 75);
    assert.equal(r.charging, false);
});

test("single battery, charging", () => {
    const r = aggregate([{ percent: 42, weight: 1000, charging: true }]);
    assert.equal(r.available, true);
    assert.equal(r.percent, 42);
    assert.equal(r.charging, true);
});

test("charging=true if ANY record is charging", () => {
    const r = aggregate([
        { percent: 80, weight: 1, charging: false },
        { percent: 30, weight: 1, charging: true },
    ]);
    assert.equal(r.charging, true);
});

test("charging=false when all records are discharging", () => {
    const r = aggregate([
        { percent: 80, weight: 1, charging: false },
        { percent: 60, weight: 1, charging: false },
    ]);
    assert.equal(r.charging, false);
});

test("two equal-weight batteries → arithmetic mean", () => {
    const r = aggregate([
        { percent: 80, weight: 100, charging: false },
        { percent: 60, weight: 100, charging: false },
    ]);
    assert.equal(r.available, true);
    assert.equal(r.percent, 70);
});

test("two batteries with differing weights → weighted mean", () => {
    // BAT0: 50% capacity, weight 40000 (µWh); BAT1: 100% capacity, weight 10000 (µWh)
    // Weighted mean = (50*40000 + 100*10000) / (40000+10000) = (2000000+1000000)/50000 = 60
    const r = aggregate([
        { percent: 50, weight: 40000, charging: false },
        { percent: 100, weight: 10000, charging: false },
    ]);
    assert.equal(r.available, true);
    assert.equal(r.percent, 60);
});

test("zero total weight falls back to arithmetic mean", () => {
    // Both weights are 0, so fall back to simple mean.
    const r = aggregate([
        { percent: 40, weight: 0, charging: false },
        { percent: 60, weight: 0, charging: false },
    ]);
    assert.equal(r.available, true);
    assert.equal(r.percent, 50);
});

test("missing weight falls back to arithmetic mean", () => {
    // No weight property at all.
    const r = aggregate([
        { percent: 20, charging: false },
        { percent: 80, charging: false },
    ]);
    assert.equal(r.available, true);
    assert.equal(r.percent, 50);
});

test("non-finite weight falls back to arithmetic mean", () => {
    const r = aggregate([
        { percent: 20, weight: NaN, charging: false },
        { percent: 80, weight: Infinity, charging: false },
    ]);
    assert.equal(r.available, true);
    assert.equal(r.percent, 50);
});

test("percent clamped to 100 when weighted result exceeds 100", () => {
    // percent values above 100 are invalid data but must not break the ring.
    const r = aggregate([{ percent: 150, weight: 1, charging: false }]);
    assert.equal(r.percent, 100);
});

test("percent clamped to 0 when weighted result is negative", () => {
    const r = aggregate([{ percent: -10, weight: 1, charging: false }]);
    assert.equal(r.percent, 0);
});

test("records with non-finite percent are ignored", () => {
    // One valid, one garbage — valid record wins.
    const r = aggregate([
        { percent: NaN, weight: 1, charging: false },
        { percent: 60, weight: 1, charging: false },
    ]);
    assert.equal(r.available, true);
    assert.equal(r.percent, 60);
});

test("all non-finite percent → available=false", () => {
    const r = aggregate([
        { percent: NaN, weight: 1, charging: false },
        { percent: Infinity, weight: 1, charging: true },
    ]);
    assert.equal(r.available, false);
    assert.equal(r.percent, 0);
    assert.equal(r.charging, false);
});

test("null entries in the array are skipped gracefully", () => {
    const r = aggregate([null, { percent: 55, weight: 1, charging: false }, undefined]);
    assert.equal(r.available, true);
    assert.equal(r.percent, 55);
});

test("return object shape matches the expected contract", () => {
    const r = aggregate([{ percent: 50, weight: 1, charging: false }]);
    assert.ok("percent" in r, "percent key present");
    assert.ok("charging" in r, "charging key present");
    assert.ok("available" in r, "available key present");
    assert.equal(typeof r.percent, "number");
    assert.equal(typeof r.charging, "boolean");
    assert.equal(typeof r.available, "boolean");
});
