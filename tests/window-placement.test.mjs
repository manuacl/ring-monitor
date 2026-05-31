// TDD spec for WindowPlacement.
//
// Run:  node --test tests/window-placement.test.mjs
//
// Implementation: contents/ui/platforms/standalone/WindowPlacement.js.
// Dual-loaded by QML (standalone Main.qml _anchor()) and Node via the
// module.exports shim at the bottom. The corner → (origin | anchor
// edges) math is the single source of truth shared by the X11 and
// Wayland-layer-shell host paths (issue #98).

import { createRequire } from "node:module";
import { test } from "node:test";
import assert from "node:assert/strict";

const require = createRequire(import.meta.url);
const WP = require("../contents/ui/platforms/standalone/WindowPlacement.js");

const SCREEN_W = 1920;
const SCREEN_H = 1080;
const WIN_W = 200;
const WIN_H = 600;

// ── cornerToAnchorSpec ──────────────────────────────────────────────

test("cornerToAnchorSpec maps each corner to its two anchored edges", () => {
    assert.deepEqual(WP.cornerToAnchorSpec("top-left"), { left: true, top: true });
    assert.deepEqual(WP.cornerToAnchorSpec("top-right"), { left: false, top: true });
    assert.deepEqual(WP.cornerToAnchorSpec("bottom-left"), { left: true, top: false });
    assert.deepEqual(WP.cornerToAnchorSpec("bottom-right"), { left: false, top: false });
});

test("cornerToAnchorSpec falls back to top-right on an unknown corner", () => {
    assert.deepEqual(WP.cornerToAnchorSpec("nonsense"), { left: false, top: true });
    assert.deepEqual(WP.cornerToAnchorSpec(""), { left: false, top: true });
    assert.deepEqual(WP.cornerToAnchorSpec(undefined), { left: false, top: true });
});

// ── computeX11Origin ────────────────────────────────────────────────

test("computeX11Origin places each corner with zero margins", () => {
    const o = (c) => WP.computeX11Origin(c, SCREEN_W, SCREEN_H, WIN_W, WIN_H, 0, 0);
    assert.deepEqual(o("top-left"), { x: 0, y: 0 });
    assert.deepEqual(o("top-right"), { x: 1720, y: 0 });
    assert.deepEqual(o("bottom-left"), { x: 0, y: 480 });
    assert.deepEqual(o("bottom-right"), { x: 1720, y: 480 });
});

test("computeX11Origin insets margins from the anchored edge", () => {
    // top-left: margins push right + down from (0,0).
    assert.deepEqual(WP.computeX11Origin("top-left", SCREEN_W, SCREEN_H, WIN_W, WIN_H, 30, 40), { x: 30, y: 40 });
    // bottom-right: margins pull left + up from the far corner.
    assert.deepEqual(WP.computeX11Origin("bottom-right", SCREEN_W, SCREEN_H, WIN_W, WIN_H, 30, 40), { x: 1690, y: 440 });
});

test("computeX11Origin reproduces the historic top-right anchor (pre-#98 default)", () => {
    // windowMargin used to inset top + right uniformly; the new default
    // corner top-right with equal X/Y margins must match it.
    const m = 20;
    assert.deepEqual(
        WP.computeX11Origin("top-right", SCREEN_W, SCREEN_H, WIN_W, WIN_H, m, m),
        { x: SCREEN_W - WIN_W - m, y: m }
    );
});

test("computeX11Origin treats an unknown corner as top-right", () => {
    assert.deepEqual(
        WP.computeX11Origin("garbage", SCREEN_W, SCREEN_H, WIN_W, WIN_H, 0, 0),
        WP.computeX11Origin("top-right", SCREEN_W, SCREEN_H, WIN_W, WIN_H, 0, 0)
    );
});
