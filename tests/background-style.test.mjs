// Tests for BackgroundStyle.js — the halo geometry behind the optional
// widget background (issue #170).

import { createRequire } from 'node:module';
import { test } from 'node:test';
import assert from 'node:assert/strict';

const require = createRequire(import.meta.url);
const BackgroundStyle = require('../contents/ui/core/BackgroundStyle.js');

test('clampOpacity keeps values inside [0, 1]', () => {
    assert.equal(BackgroundStyle.clampOpacity(0.4), 0.4);
    assert.equal(BackgroundStyle.clampOpacity(-1), 0);
    assert.equal(BackgroundStyle.clampOpacity(7), 1);
});

test('clampOpacity turns a non-number into 0 rather than NaN', () => {
    // A NaN alpha reaching Qt.rgba() paints an undefined color; an
    // unset config key must simply mean "invisible".
    for (const junk of [undefined, null, 'half', NaN])
        assert.equal(BackgroundStyle.clampOpacity(junk), 0);
});

test('featherPixels is a percentage of the shorter side', () => {
    assert.equal(BackgroundStyle.featherPixels(10, 400, 200), 20);
    assert.equal(BackgroundStyle.featherPixels(10, 200, 400), 20);
});

test('softness 0 means a crisp plate', () => {
    assert.equal(BackgroundStyle.featherPixels(0, 400, 200), 0);
});

test('max softness fades from the centre line: half the shorter side', () => {
    assert.equal(BackgroundStyle.featherPixels(BackgroundStyle.MAX_FEATHER_PERCENT, 400, 200), 100);
});

test('featherPixels survives an unsized or junk widget', () => {
    // Bindings evaluate before the first layout pass, where width/height
    // are still 0 — that must yield a crisp plate, not NaN margins.
    assert.equal(BackgroundStyle.featherPixels(20, 0, 0), 0);
    assert.equal(BackgroundStyle.featherPixels(20, undefined, 200), 0);
    assert.equal(BackgroundStyle.featherPixels('soft', 400, 200), 0);
});

test('clampPercent holds the softness inside [0, MAX_FEATHER_PERCENT]', () => {
    assert.equal(BackgroundStyle.clampPercent(12), 12);
    assert.equal(BackgroundStyle.clampPercent(-5), 0);
    assert.equal(BackgroundStyle.clampPercent(90), BackgroundStyle.MAX_FEATHER_PERCENT);
    assert.equal(BackgroundStyle.clampPercent(NaN), 0);
});

test('a percentage past the cap feathers like the cap, not like zero', () => {
    assert.equal(BackgroundStyle.featherPixels(90, 400, 200), BackgroundStyle.featherPixels(BackgroundStyle.MAX_FEATHER_PERCENT, 400, 200));
});

// ── ringBounds ────────────────────────────────────────────────────
test('ringBounds spans a horizontal strip with ring-radius caps', () => {
    const cells = [
        { x: 0, y: 0, width: 100, height: 100 },
        { x: 110, y: 0, width: 100, height: 100 },
    ];
    assert.deepEqual(BackgroundStyle.ringBounds(cells), { x: 0, y: 0, width: 210, height: 100, radius: 50 });
});

test('ringBounds follows the drawn rings, not over-wide cells', () => {
    // SCENARIO: a Plasma applet resized taller than the vertical strip —
    // each cell grows, but the ring stays a centred min(w, h) square.
    const cells = [
        { x: 0, y: 0, width: 100, height: 160 },
        { x: 0, y: 170, width: 100, height: 160 },
    ];
    assert.deepEqual(BackgroundStyle.ringBounds(cells), { x: 0, y: 30, width: 100, height: 270, radius: 50 });
});

test('ringBounds skips unsized cells and reports nothing without rings', () => {
    assert.equal(BackgroundStyle.ringBounds([]), null);
    assert.equal(BackgroundStyle.ringBounds(undefined), null);
    assert.equal(BackgroundStyle.ringBounds([{ x: 0, y: 0, width: 0, height: 0 }]), null);
    assert.deepEqual(BackgroundStyle.ringBounds([{ x: 5, y: 5, width: 0, height: 0 }, { x: 10, y: 20, width: 40, height: 40 }]), { x: 10, y: 20, width: 40, height: 40, radius: 20 });
});

test('clampPercent honours an explicit ceiling', () => {
    assert.equal(BackgroundStyle.clampPercent(150, BackgroundStyle.MAX_SPREAD_PERCENT), BackgroundStyle.MAX_SPREAD_PERCENT);
    assert.equal(BackgroundStyle.clampPercent(70, BackgroundStyle.MAX_SPREAD_PERCENT), 70);
});

// ── spreadBounds ──────────────────────────────────────────────────
test('spreadBounds grows the stadium by a share of the ring radius', () => {
    const rings = { x: 0, y: 0, width: 100, height: 300, radius: 50 };
    assert.deepEqual(BackgroundStyle.spreadBounds(rings, 40), { x: -20, y: -20, width: 140, height: 340, radius: 70 });
});

test('spreadBounds 0 hugs the rings, and junk or overshoot is clamped', () => {
    const rings = { x: 10, y: 10, width: 100, height: 100, radius: 50 };
    assert.deepEqual(BackgroundStyle.spreadBounds(rings, 0), rings);
    assert.deepEqual(BackgroundStyle.spreadBounds(rings, 'big'), rings);
    assert.deepEqual(BackgroundStyle.spreadBounds(rings, 500), BackgroundStyle.spreadBounds(rings, BackgroundStyle.MAX_SPREAD_PERCENT));
    assert.equal(BackgroundStyle.spreadBounds(null, 50), null);
});

// ── haloGeometry ──────────────────────────────────────────────────
test('haloGeometry: crisp when feather is 0', () => {
    const g = BackgroundStyle.haloGeometry(300, 100, 0);
    assert.equal(g.edgeAlpha, 1);
    assert.equal(g.fadeStop, 0);
    assert.equal(g.capStop, 1);
});

test('haloGeometry: a horizontal pill has caps left and right', () => {
    const g = BackgroundStyle.haloGeometry(300, 100, 25);
    assert.equal(g.r, 50);
    assert.equal(g.edgeAlpha, 0);
    assert.equal(g.fadeStop, 0.25);
    assert.equal(g.capStop, 0.5);
    assert.deepEqual(g.body, [{ x: 50, y: 0 }, { x: 250, y: 0 }, { x: 250, y: 100 }, { x: 50, y: 100 }]);
    // The fade runs across the thickness.
    assert.deepEqual(g.across, { start: { x: 0, y: 0 }, end: { x: 0, y: 100 } });
    assert.deepEqual(g.capA.center, { x: 50, y: 50 });
    assert.equal(g.capA.clockwise, false);
    assert.deepEqual(g.capB.center, { x: 250, y: 50 });
    assert.equal(g.capB.clockwise, true);
});

test('haloGeometry: a vertical pill has caps top and bottom', () => {
    const g = BackgroundStyle.haloGeometry(100, 300, 25);
    assert.deepEqual(g.body, [{ x: 0, y: 50 }, { x: 0, y: 250 }, { x: 100, y: 250 }, { x: 100, y: 50 }]);
    assert.deepEqual(g.across, { start: { x: 0, y: 0 }, end: { x: 100, y: 0 } });
    assert.deepEqual(g.capA.start, { x: 0, y: 50 });
    assert.deepEqual(g.capA.end, { x: 100, y: 50 });
    assert.equal(g.capA.clockwise, true);
    assert.equal(g.capB.clockwise, false);
});

test('haloGeometry: seams on whole pixels, feather capped at the radius', () => {
    const g = BackgroundStyle.haloGeometry(301, 101, 999);
    // r = 50.5, seams rounded; body never inverted.
    assert.equal(g.capA.start.x, 51);
    assert.equal(g.capB.start.x, 250);
    assert.equal(g.capStop, 0);
    assert.equal(g.fadeStop, 0.5);
    // A single ring: both seams meet at the middle, no body.
    const one = BackgroundStyle.haloGeometry(100, 100, 10);
    assert.equal(one.capA.start.x, one.capB.start.x);
});

test('haloGeometry survives an unsized box', () => {
    const g = BackgroundStyle.haloGeometry(0, 0, 10);
    assert.equal(g.r, 0);
    assert.equal(g.fadeStop, 0);
    assert.equal(g.capStop, 1);
});
