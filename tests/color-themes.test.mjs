// Tests for ColorThemes.js — themes catalog + resolveColor dispatch.

import { createRequire } from 'node:module';
import { test } from 'node:test';
import assert from 'node:assert/strict';

const require = createRequire(import.meta.url);
const ColorThemes = require('../contents/ui/core/ColorThemes.js');

const SYSTEM_HIGHLIGHT = '#abcdef';
const CUSTOM_LIGHT = '#111111';
const CUSTOM_DARK = '#222222';

test('THEMES has the 7 expected ids in the right order', () => {
    const ids = ColorThemes.THEMES.map(t => t.id);
    assert.deepEqual(ids, ['system', 'blue', 'green', 'orange', 'violet', 'red', 'custom']);
});

test('every theme entry has id + label', () => {
    for (const t of ColorThemes.THEMES) {
        assert.equal(typeof t.id, 'string');
        assert.ok(t.id.length > 0, `empty id on ${JSON.stringify(t)}`);
        assert.equal(typeof t.label, 'string');
        assert.ok(t.label.length > 0, `empty label on ${JSON.stringify(t)}`);
    }
});

test('predefined themes (non-system, non-custom) have both color variants', () => {
    for (const t of ColorThemes.THEMES) {
        if (t.id === 'system' || t.id === 'custom') continue;
        assert.equal(typeof t.lightColor, 'string', `${t.id}.lightColor`);
        assert.equal(typeof t.darkColor, 'string', `${t.id}.darkColor`);
        assert.match(t.lightColor, /^#[0-9a-f]{6}$/i, `${t.id}.lightColor format`);
        assert.match(t.darkColor, /^#[0-9a-f]{6}$/i, `${t.id}.darkColor format`);
    }
});

test('resolveColor system: forwards systemHighlight regardless of isDark', () => {
    assert.equal(ColorThemes.resolveColor('system', false, SYSTEM_HIGHLIGHT, CUSTOM_LIGHT, CUSTOM_DARK), SYSTEM_HIGHLIGHT);
    assert.equal(ColorThemes.resolveColor('system', true,  SYSTEM_HIGHLIGHT, CUSTOM_LIGHT, CUSTOM_DARK), SYSTEM_HIGHLIGHT);
});

test('resolveColor custom: picks customLight when isDark=false, customDark when true', () => {
    assert.equal(ColorThemes.resolveColor('custom', false, SYSTEM_HIGHLIGHT, CUSTOM_LIGHT, CUSTOM_DARK), CUSTOM_LIGHT);
    assert.equal(ColorThemes.resolveColor('custom', true,  SYSTEM_HIGHLIGHT, CUSTOM_LIGHT, CUSTOM_DARK), CUSTOM_DARK);
});

test('resolveColor predefined themes: returns light variant when isDark=false', () => {
    for (const t of ColorThemes.THEMES) {
        if (t.id === 'system' || t.id === 'custom') continue;
        assert.equal(
            ColorThemes.resolveColor(t.id, false, SYSTEM_HIGHLIGHT, CUSTOM_LIGHT, CUSTOM_DARK),
            t.lightColor,
            `${t.id} should return lightColor when isDark=false`,
        );
    }
});

test('resolveColor predefined themes: returns dark variant when isDark=true', () => {
    for (const t of ColorThemes.THEMES) {
        if (t.id === 'system' || t.id === 'custom') continue;
        assert.equal(
            ColorThemes.resolveColor(t.id, true, SYSTEM_HIGHLIGHT, CUSTOM_LIGHT, CUSTOM_DARK),
            t.darkColor,
            `${t.id} should return darkColor when isDark=true`,
        );
    }
});

test('resolveColor unknown id: falls back to system (returns systemHighlight)', () => {
    assert.equal(ColorThemes.resolveColor('nonexistent', false, SYSTEM_HIGHLIGHT, CUSTOM_LIGHT, CUSTOM_DARK), SYSTEM_HIGHLIGHT);
    assert.equal(ColorThemes.resolveColor('',            true,  SYSTEM_HIGHLIGHT, CUSTOM_LIGHT, CUSTOM_DARK), SYSTEM_HIGHLIGHT);
});

test('DEFAULT_HIGHLIGHT is the Kirigami blue', () => {
    assert.equal(ColorThemes.DEFAULT_HIGHLIGHT, '#3daee9');
});

test('resolveSharedRingColor: system theme forwards the highlight regardless of mode/scheme', () => {
    assert.equal(ColorThemes.resolveSharedRingColor('system', 'auto',  true,  SYSTEM_HIGHLIGHT, CUSTOM_LIGHT, CUSTOM_DARK), SYSTEM_HIGHLIGHT);
    assert.equal(ColorThemes.resolveSharedRingColor('system', 'light', true,  SYSTEM_HIGHLIGHT, CUSTOM_LIGHT, CUSTOM_DARK), SYSTEM_HIGHLIGHT);
});

test('resolveSharedRingColor: custom theme pairs effectiveIsDark with the L/D pick', () => {
    assert.equal(ColorThemes.resolveSharedRingColor('custom', 'auto',  false, SYSTEM_HIGHLIGHT, CUSTOM_LIGHT, CUSTOM_DARK), CUSTOM_LIGHT);
    assert.equal(ColorThemes.resolveSharedRingColor('custom', 'auto',  true,  SYSTEM_HIGHLIGHT, CUSTOM_LIGHT, CUSTOM_DARK), CUSTOM_DARK);
    assert.equal(ColorThemes.resolveSharedRingColor('custom', 'dark',  false, SYSTEM_HIGHLIGHT, CUSTOM_LIGHT, CUSTOM_DARK), CUSTOM_DARK);
    assert.equal(ColorThemes.resolveSharedRingColor('custom', 'light', true,  SYSTEM_HIGHLIGHT, CUSTOM_LIGHT, CUSTOM_DARK), CUSTOM_LIGHT);
});

test('effectiveIsDark auto: returns the detected systemIsDark verbatim', () => {
    assert.equal(ColorThemes.effectiveIsDark('auto', true),  true);
    assert.equal(ColorThemes.effectiveIsDark('auto', false), false);
});

test('effectiveIsDark light: forces false regardless of systemIsDark', () => {
    assert.equal(ColorThemes.effectiveIsDark('light', true),  false);
    assert.equal(ColorThemes.effectiveIsDark('light', false), false);
});

test('effectiveIsDark dark: forces true regardless of systemIsDark', () => {
    assert.equal(ColorThemes.effectiveIsDark('dark', true),  true);
    assert.equal(ColorThemes.effectiveIsDark('dark', false), true);
});

test('effectiveIsDark unknown mode: falls back to auto (returns systemIsDark)', () => {
    assert.equal(ColorThemes.effectiveIsDark('nonexistent', true),  true);
    assert.equal(ColorThemes.effectiveIsDark('',            false), false);
});

const SYSTEM_TEXT = '#abcdef';
const CUSTOM_TEXT_LIGHT = '#101010';
const CUSTOM_TEXT_DARK = '#f0f0f0';

test('resolveTextColor system: forwards systemText regardless of isDark', () => {
    assert.equal(ColorThemes.resolveTextColor('system', false, SYSTEM_TEXT, CUSTOM_TEXT_LIGHT, CUSTOM_TEXT_DARK), SYSTEM_TEXT);
    assert.equal(ColorThemes.resolveTextColor('system', true,  SYSTEM_TEXT, CUSTOM_TEXT_LIGHT, CUSTOM_TEXT_DARK), SYSTEM_TEXT);
});

test('resolveTextColor custom: picks customLight when isDark=false, customDark when true', () => {
    assert.equal(ColorThemes.resolveTextColor('custom', false, SYSTEM_TEXT, CUSTOM_TEXT_LIGHT, CUSTOM_TEXT_DARK), CUSTOM_TEXT_LIGHT);
    assert.equal(ColorThemes.resolveTextColor('custom', true,  SYSTEM_TEXT, CUSTOM_TEXT_LIGHT, CUSTOM_TEXT_DARK), CUSTOM_TEXT_DARK);
});

test('resolveTextColor unknown mode: falls back to system (returns systemText)', () => {
    assert.equal(ColorThemes.resolveTextColor('nonexistent', false, SYSTEM_TEXT, CUSTOM_TEXT_LIGHT, CUSTOM_TEXT_DARK), SYSTEM_TEXT);
    assert.equal(ColorThemes.resolveTextColor('',            true,  SYSTEM_TEXT, CUSTOM_TEXT_LIGHT, CUSTOM_TEXT_DARK), SYSTEM_TEXT);
});
