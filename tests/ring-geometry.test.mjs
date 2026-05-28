// Tests for RingGeometry.js — pure geometry math used by Ring.qml.

import { createRequire } from 'node:module';
import { test } from 'node:test';
import assert from 'node:assert/strict';

const require = createRequire(import.meta.url);
const Geom = require('../contents/ui/core/RingGeometry.js');

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
    // size * 0.08 = 14.4, rounded to 14, max(10, 14) = 14
    assert.equal(d.labelPx, 14);
    // size * 0.16 = 28.8, rounded to 29, max(14, 29) = 29
    assert.equal(d.valuePx, 29);
});

test('dimensionsFor: at very small size, floors kick in', () => {
    const d = Geom.dimensionsFor(40);
    assert.equal(d.ringStroke, 4);   // floor
    assert.equal(d.nestedStroke, 2); // floor
    assert.equal(d.nestedGap, 2);    // floor
    assert.equal(d.labelPx, 10);     // floor
    assert.equal(d.valuePx, 14);     // floor
});

test('dimensionsFor: at huge size, factors scale linearly', () => {
    const d = Geom.dimensionsFor(1000);
    assert.equal(d.ringStroke, 55);
    assert.equal(d.nestedStroke, 17);
    assert.equal(d.labelPx, 80);
    assert.equal(d.valuePx, 160);
});

test('dimensionsFor: invalid size (0, negative, NaN) returns floor values', () => {
    assert.equal(Geom.dimensionsFor(0).ringStroke, 4);
    assert.equal(Geom.dimensionsFor(-5).ringStroke, 4);
    assert.equal(Geom.dimensionsFor(NaN).ringStroke, 4);
});

// ── nestedRingLayout: count-aware concentric ring layout ────────────────
//
// Up to COMFORT_RING_COUNT (7): preferred stroke/gap are used directly,
// cores stack grows naturally inward. Past 7: the layout shrinks
// stroke = gap = (7 × (preferredStroke + preferredGap)) / (2 × count)
// so the whole stack always fits inside the 7-ring envelope.

test('COMFORT_RING_COUNT is exposed and equals 7', () => {
    // 6 cores (dev rig) → no shrinking; one more before scaling kicks in.
    assert.equal(Geom.COMFORT_RING_COUNT, 7);
});

test('nestedRingLayout: count=0 returns empty layout', () => {
    const out = Geom.nestedRingLayout(83, 10, 3, 4, 0);
    assert.equal(out.stroke, 0);
    assert.equal(out.gap, 0);
    assert.deepEqual(out.radii, []);
});

test('nestedRingLayout: low count uses preferred stroke/gap untouched', () => {
    // 6 cores at preferredStroke=3, preferredGap=4 → no scaling.
    const out = Geom.nestedRingLayout(83, 10, 3, 4, 6);
    assert.equal(out.stroke, 3);
    assert.equal(out.gap, 4);
    // Outermost: outerEdge=83-5=78, then -gap=4 -stroke/2=1.5 → 72.5
    assert.equal(out.radii[0], 72.5);
    // Step inward by (stroke + gap) = 7
    assert.equal(out.radii[1], 72.5 - 7);
    assert.equal(out.radii[5], 72.5 - 5 * 7);
});

test('nestedRingLayout: 7 cores still uses preferred values (last comfortable count)', () => {
    const out = Geom.nestedRingLayout(83, 10, 3, 4, 7);
    assert.equal(out.stroke, 3);
    assert.equal(out.gap, 4);
    assert.equal(out.radii.length, 7);
});

test('nestedRingLayout: 8+ cores shrinks to fit the 7-ring envelope', () => {
    // envelope = 7 × (3 + 4) = 49 px → unit at count=8 = 49 / 16 = 3.0625
    const out = Geom.nestedRingLayout(83, 10, 3, 4, 8);
    assert.equal(out.stroke, 49 / 16);
    assert.equal(out.gap, 49 / 16);
    assert.equal(out.radii.length, 8);
});

test('nestedRingLayout: 12 cores stack ends at the same inner radius as 7 cores', () => {
    // Both stacks should end (innermost radius) at the same fixed point:
    // outerEdge - 7 × (3 + 4) = 78 - 49 = 29 (approx, modulo stroke / 2 offset).
    const seven = Geom.nestedRingLayout(83, 10, 3, 4, 7);
    const twelve = Geom.nestedRingLayout(83, 10, 3, 4, 12);
    // Innermost ring's centre radius minus its own stroke/2 = stack's
    // innermost edge. These must match (within 0.5 px) for both counts.
    const sevenInnerEdge = seven.radii[6] - seven.stroke / 2;
    const twelveInnerEdge = twelve.radii[11] - twelve.stroke / 2;
    assert.ok(Math.abs(sevenInnerEdge - twelveInnerEdge) < 0.5,
        `inner edges drifted: 7-ring at ${sevenInnerEdge}, 12-ring at ${twelveInnerEdge}`);
});

test('nestedRingLayout: high count floors at stroke=1 (32-core stays visible)', () => {
    // envelope = 49, unit at count=32 = 49/64 ≈ 0.77 → floor to 1.
    const out = Geom.nestedRingLayout(83, 10, 3, 4, 32);
    assert.equal(out.stroke, 1);
    assert.equal(out.gap, 1);
    assert.equal(out.radii.length, 32);
});

// ── Split-mode geometry (left/right half-arcs meeting at the top) ──
//
// The two halves together span the same 270° as the full sweep: each
// is HALF_SWEEP_ANGLE = 135°. They start at the bottom gap edges
// (135° / 45°) and grow toward the top (270°) in opposite directions.

test('split constants: halves geometrically meet at top before gap', () => {
    assert.equal(Geom.LEFT_HALF_START, 135);
    assert.equal(Geom.RIGHT_HALF_START, 45);
    assert.equal(Geom.HALF_SWEEP_ANGLE, 135);
    assert.equal(Geom.SPLIT_GAP_ANGLE, 8);
    // Geometric halves still sum to 270° — SPLIT_GAP_ANGLE is the
    // *rendered* tweak applied via effectiveHalfSweep(), not a change
    // to the underlying geometry.
    assert.equal(Geom.HALF_SWEEP_ANGLE * 2, Geom.BASE_SWEEP_ANGLE);
    assert.equal(Geom.LEFT_HALF_START + Geom.HALF_SWEEP_ANGLE, 270);
    assert.equal((Geom.RIGHT_HALF_START - Geom.HALF_SWEEP_ANGLE + 360) % 360, 270);
});

test('effectiveHalfSweep shortens each half by SPLIT_GAP_ANGLE/2', () => {
    // 135° geometric − 4° (half of 8° gap) = 131° rendered max.
    assert.equal(Geom.effectiveHalfSweep(), 131);
});

test('leftHalfSweepFor: 0% → 0°, 100% → +131°, 50% → +65.5°', () => {
    assert.equal(Geom.leftHalfSweepFor(0), 0);
    assert.equal(Geom.leftHalfSweepFor(100), 131);
    assert.equal(Geom.leftHalfSweepFor(50), 65.5);
});

test('rightHalfSweepFor: 0% → 0°, 100% → −131°, 50% → −65.5°', () => {
    assert.equal(Geom.rightHalfSweepFor(0), 0);
    assert.equal(Geom.rightHalfSweepFor(100), -131);
    assert.equal(Geom.rightHalfSweepFor(50), -65.5);
});

test('left/rightHalfSweepFor: clamp out-of-range input', () => {
    assert.equal(Geom.leftHalfSweepFor(-5), 0);
    assert.equal(Geom.leftHalfSweepFor(150), 131);
    assert.equal(Geom.rightHalfSweepFor(-5), 0);
    assert.equal(Geom.rightHalfSweepFor(150), -131);
});

test('left/rightHalfSweepFor: non-finite input → 0 (clamped via clampPercent)', () => {
    assert.equal(Geom.leftHalfSweepFor(NaN), 0);
    assert.equal(Geom.rightHalfSweepFor(NaN), 0);
    assert.equal(Geom.leftHalfSweepFor(Infinity), 0);
    assert.equal(Geom.rightHalfSweepFor(Infinity), 0);
});

// ── equalRingLayout (disk multi-partition mode) ───────────────────────

test('DISK_COMFORT_RING_COUNT is exposed and equals 5', () => {
    assert.equal(Geom.DISK_COMFORT_RING_COUNT, 5);
});

test('equalRingLayout: count=0 returns empty layout', () => {
    const out = Geom.equalRingLayout(90, 10, 4, 0);
    assert.deepEqual(out, { stroke: 0, gap: 0, radii: [] });
});

test('equalRingLayout: outermost ring sits AT the main radius (no inset)', () => {
    // Unlike nested rings (inset below a separate main ring), the disk rings
    // ARE the main ring — radii[0] must equal ringRadius exactly.
    const out = Geom.equalRingLayout(90, 10, 4, 1);
    assert.equal(out.radii[0], 90);
    assert.equal(out.stroke, 10);
});

test('equalRingLayout: low count uses preferred (full) stroke + gap, steps inward', () => {
    const out = Geom.equalRingLayout(90, 10, 4, 3);
    assert.equal(out.stroke, 10);
    assert.equal(out.gap, 4);
    // radii[i] = ringRadius - i*(stroke+gap) = 90, 76, 62
    assert.deepEqual(out.radii, [90, 76, 62]);
});

test('equalRingLayout: 5 partitions still preferred (last comfortable count)', () => {
    const out = Geom.equalRingLayout(90, 10, 4, 5);
    assert.equal(out.stroke, 10);
    assert.equal(out.gap, 4);
    assert.equal(out.radii.length, 5);
});

test('equalRingLayout: 6+ partitions shrink to fit the 5-ring envelope', () => {
    const out = Geom.equalRingLayout(90, 10, 4, 6);
    // envelope = 5*(10+4)=70; unit = 70/(2*6)=5.833…; stroke=gap=unit
    assert.ok(out.stroke < 10, `expected shrink below 10, got ${out.stroke}`);
    assert.equal(out.stroke, out.gap);
    assert.equal(out.radii.length, 6);
    assert.equal(out.radii[0], 90);  // outermost still pinned to the main radius
});

test('equalRingLayout: high count floors stroke at 1px', () => {
    const out = Geom.equalRingLayout(90, 10, 4, 100);
    assert.equal(out.stroke, 1);
    assert.equal(out.gap, 1);
});
