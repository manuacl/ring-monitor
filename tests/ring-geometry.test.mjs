// Tests for RingGeometry.js — pure geometry math used by Ring.qml.

import { createRequire } from 'node:module';
import { test } from 'node:test';
import assert from 'node:assert/strict';

const require = createRequire(import.meta.url);
const Geom = require('../contents/ui/RingGeometry.js');

test('BASE_*_ANGLE constants match the established aesthetic', () => {
    // 270° sweep starting at 135°: 90° gap at the bottom.
    assert.equal(Geom.BASE_START_ANGLE, 135);
    assert.equal(Geom.BASE_SWEEP_ANGLE, 270);
});

test('clampPercent: in-range stays untouched', () => {
    assert.equal(Geom.clampPercent(0), 0);
    assert.equal(Geom.clampPercent(50), 50);
    assert.equal(Geom.clampPercent(100), 100);
});

test('clampPercent: below 0 → 0', () => {
    assert.equal(Geom.clampPercent(-5), 0);
    assert.equal(Geom.clampPercent(-9999), 0);
});

test('clampPercent: above 100 → 100', () => {
    assert.equal(Geom.clampPercent(105), 100);
    assert.equal(Geom.clampPercent(9999), 100);
});

test('clampPercent: non-finite → 0', () => {
    assert.equal(Geom.clampPercent(NaN), 0);
    assert.equal(Geom.clampPercent(Infinity), 0);
    assert.equal(Geom.clampPercent(-Infinity), 0);
});

test('sweepForPercent: 0% → 0°, 100% → 270°, 50% → 135°', () => {
    assert.equal(Geom.sweepForPercent(0), 0);
    assert.equal(Geom.sweepForPercent(100), 270);
    assert.equal(Geom.sweepForPercent(50), 135);
});

test('sweepForPercent: clamps out-of-range input', () => {
    assert.equal(Geom.sweepForPercent(-10), 0);
    assert.equal(Geom.sweepForPercent(200), 270);
});

test('dimensionsFor: at size=180 (default), values match Ring.qml expectations', () => {
    const d = Geom.dimensionsFor(180);
    // size * 0.055 = 9.9, rounded to 10, max(4, 10) = 10
    assert.equal(d.ringStroke, 10);
    // size/2 - stroke/2 - 2 = 90 - 5 - 2 = 83
    assert.equal(d.ringRadius, 83);
    // size * 0.017 = 3.06, rounded to 3, max(2, 3) = 3
    assert.equal(d.nestedStroke, 3);
    // size * 0.022 = 3.96, rounded to 4, max(2, 4) = 4
    assert.equal(d.nestedGap, 4);
    // size * 0.06 = 10.8, rounded to 11, max(8, 11) = 11
    assert.equal(d.labelPx, 11);
    // size * 0.16 = 28.8, rounded to 29, max(14, 29) = 29
    assert.equal(d.valuePx, 29);
});

test('dimensionsFor: at very small size, floors kick in', () => {
    const d = Geom.dimensionsFor(40);
    assert.equal(d.ringStroke, 4);   // floor
    assert.equal(d.nestedStroke, 2); // floor
    assert.equal(d.nestedGap, 2);    // floor
    assert.equal(d.labelPx, 8);      // floor
    assert.equal(d.valuePx, 14);     // floor
});

test('dimensionsFor: at huge size, factors scale linearly', () => {
    const d = Geom.dimensionsFor(1000);
    assert.equal(d.ringStroke, 55);
    assert.equal(d.nestedStroke, 17);
    assert.equal(d.labelPx, 60);
    assert.equal(d.valuePx, 160);
});

test('dimensionsFor: invalid size (0, negative, NaN) returns floor values', () => {
    assert.equal(Geom.dimensionsFor(0).ringStroke, 4);
    assert.equal(Geom.dimensionsFor(-5).ringStroke, 4);
    assert.equal(Geom.dimensionsFor(NaN).ringStroke, 4);
});

test('nestedRadius: index 0 sits just inside the main ring', () => {
    // Main ringRadius=83, ringStroke=10, nestedStroke=3, nestedGap=4
    // r0 = 83 - 5 - 4 - 1.5 - 0 = 72.5
    assert.equal(Geom.nestedRadius(83, 10, 3, 4, 0), 72.5);
});

test('nestedRadius: each subsequent index steps inward by (nestedStroke + nestedGap)', () => {
    const step = 3 + 4; // 7
    const r0 = Geom.nestedRadius(83, 10, 3, 4, 0);
    const r1 = Geom.nestedRadius(83, 10, 3, 4, 1);
    const r5 = Geom.nestedRadius(83, 10, 3, 4, 5);
    assert.equal(r1 - r0, -step);
    assert.equal(r5, r0 - 5 * step);
});
