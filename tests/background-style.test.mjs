// Tests for BackgroundStyle.js — the two-stop math behind the optional
// widget background (issue #170).

import { createRequire } from 'node:module';
import { test } from 'node:test';
import assert from 'node:assert/strict';

const require = createRequire(import.meta.url);
const BackgroundStyle = require('../contents/ui/core/BackgroundStyle.js');

test('DIRECTIONS lists none first, then the four edges', () => {
    assert.deepEqual(BackgroundStyle.DIRECTIONS, ['none', 'top', 'bottom', 'left', 'right']);
});

test('normalizeDirection passes known values through', () => {
    for (const d of BackgroundStyle.DIRECTIONS)
        assert.equal(BackgroundStyle.normalizeDirection(d), d);
});

test('normalizeDirection falls back to none on junk', () => {
    for (const junk of ['', 'diagonal', undefined, null, 42])
        assert.equal(BackgroundStyle.normalizeDirection(junk), 'none');
});

test('isHorizontal is true only for the left/right fades', () => {
    assert.equal(BackgroundStyle.isHorizontal('left'), true);
    assert.equal(BackgroundStyle.isHorizontal('right'), true);
    assert.equal(BackgroundStyle.isHorizontal('top'), false);
    assert.equal(BackgroundStyle.isHorizontal('bottom'), false);
    assert.equal(BackgroundStyle.isHorizontal('none'), false);
    assert.equal(BackgroundStyle.isHorizontal('nonsense'), false);
});

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

test('none yields a flat fill — both stops at the configured opacity', () => {
    assert.equal(BackgroundStyle.startAlpha('none', 0.5), 0.5);
    assert.equal(BackgroundStyle.endAlpha('none', 0.5), 0.5);
});

test('a fade is transparent at the named edge and opaque at the other', () => {
    // position 0.0 = top (vertical) / left (horizontal).
    assert.equal(BackgroundStyle.startAlpha('top', 0.8), 0);
    assert.equal(BackgroundStyle.endAlpha('top', 0.8), 0.8);

    assert.equal(BackgroundStyle.startAlpha('bottom', 0.8), 0.8);
    assert.equal(BackgroundStyle.endAlpha('bottom', 0.8), 0);

    assert.equal(BackgroundStyle.startAlpha('left', 0.8), 0);
    assert.equal(BackgroundStyle.endAlpha('left', 0.8), 0.8);

    assert.equal(BackgroundStyle.startAlpha('right', 0.8), 0.8);
    assert.equal(BackgroundStyle.endAlpha('right', 0.8), 0);
});

test('an unknown direction paints like none, not like a fade', () => {
    assert.equal(BackgroundStyle.startAlpha('diagonal', 0.3), 0.3);
    assert.equal(BackgroundStyle.endAlpha('diagonal', 0.3), 0.3);
});

test('the opaque end is clamped too', () => {
    assert.equal(BackgroundStyle.endAlpha('top', 4), 1);
    assert.equal(BackgroundStyle.startAlpha('bottom', -2), 0);
});

test('featherPixels is a percentage of the shorter side', () => {
    assert.equal(BackgroundStyle.featherPixels(10, 400, 200), 20);
    assert.equal(BackgroundStyle.featherPixels(10, 200, 400), 20);
});

test('softness 0 means a crisp plate', () => {
    assert.equal(BackgroundStyle.featherPixels(0, 400, 200), 0);
});

test('featherPixels stays under the MultiEffect blurMax ceiling', () => {
    // A big widget at max softness would ask for hundreds of pixels;
    // anything past blurMax is silently ignored by the effect.
    assert.equal(BackgroundStyle.featherPixels(33, 4000, 4000), BackgroundStyle.MAX_FEATHER_PX);
    assert.ok(BackgroundStyle.MAX_FEATHER_PX <= 64);
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
