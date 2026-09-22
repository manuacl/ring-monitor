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
