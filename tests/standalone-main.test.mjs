// Text-level guards for the standalone Main.qml root Window. The
// file imports `QtQuick.Window` + `RingMonitor.Standalone` (the
// QML module registered by the C++ standalone build) and embeds
// the C++-backed `WindowAnchor` singleton, none of which load under
// the dev box's qmltestrunner-qt6 without the standalone binary
// linked in. So we inspect the source as plain text — the same
// pattern as `standalone-config-store.test.mjs` and
// `standalone-metrics-backend.test.mjs`.
//
// The contract these guards lock in:
//
//   1. The initial `_anchor()` call MUST be deferred via
//      `Qt.callLater` so it lands after `applyDesktopWindowHints`
//      has swapped the window-type to DESKTOP. A direct call hits
//      the gravity-shift scenario WindowAnchor exists to avoid.
//   2. Geometry re-anchor on Screen.width / Screen.height change
//      (resolution swap, primary-monitor change). Without this,
//      the existing _target* signals stay silent at default
//      ringSize because the screen-cap branch is inert.
//   3. Geometry re-anchor on `onScreenChanged` (window migrates
//      between same-resolution monitors — width/height wouldn't
//      fire).

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const SRC = readFileSync(
    join(__dirname, "..", "contents", "ui", "platforms", "standalone", "Main.qml"),
    "utf8",
);

test("initial _anchor() is deferred via Qt.callLater", () => {
    // The match accepts whitespace variation and a surrounding block
    // (the settings-only branch lives in the same `Component.onCompleted`)
    // but rejects a direct `_anchor()` call (which would bypass the
    // deferral and hit the wrong window-type).
    assert.match(
        SRC,
        /Qt\.callLater\(\s*_anchor\s*\)/,
        "the initial _anchor must be deferred via Qt.callLater",
    );
    // And the direct synchronous form must not exist anywhere — that's
    // exactly what the deferral exists to avoid.
    assert.doesNotMatch(
        SRC,
        /Component\.onCompleted\s*:\s*_anchor\s*\(\s*\)/,
        "Component.onCompleted must NOT call _anchor() directly (bypasses the deferral)",
    );
});

test("settings-only recovery mode is wired in Main.qml", () => {
    // Review finding 🟠 PR #32: right-click is the only entry to the
    // SettingsDialog, and a compositor regression on
    // `_NET_WM_WINDOW_TYPE_DESKTOP` (KWin / mutter) can swallow it.
    // The `--open-settings` argv flag (parsed in main.cpp) exposes
    // `settingsOnlyMode` as a context property; Main.qml reads it
    // through a `typeof ... !== 'undefined'` guard so qmltestrunner
    // contexts where the property isn't set still render the default
    // widget mode.
    assert.match(
        SRC,
        /settingsOnlyMode/,
        "Main.qml must reference the settingsOnlyMode context property",
    );
    assert.match(
        SRC,
        /typeof\s+settingsOnlyMode\s*!==\s*["']undefined["']/,
        "must guard the context-property lookup with typeof !== 'undefined' for qmltestrunner / hot-reload contexts",
    );
    // The main Window must hide in settings-only mode — otherwise the
    // frameless DESKTOP shell still tries to map alongside the
    // recovery dialog and the user gets back into the same trap.
    assert.match(
        SRC,
        /visible\s*:\s*!_settingsOnly/,
        "Window.visible must be `!_settingsOnly` so the rings stay hidden during recovery",
    );
    // Closing the dialog must terminate the process — there's no
    // widget UI to fall back to in settings-only mode.
    assert.match(
        SRC,
        /settingsDialog\.visibility\s*===\s*Window\.Hidden[\s\S]*?Qt\.quit\(\)/,
        "the SettingsDialog Hidden transition must call Qt.quit() in settings-only mode",
    );
});

test("Screen width/height changes trigger a re-anchor", () => {
    // Connections { target: root.Screen ... } is the canonical Qt
    // pattern for listening to the attached Screen's geometry. We
    // assert both onWidthChanged AND onHeightChanged are present —
    // a single dimension change is enough to strand the window if
    // only the other one is wired.
    assert.match(
        SRC,
        /Connections\s*{[\s\S]*?target\s*:\s*root\.Screen[\s\S]*?function\s+onWidthChanged\s*\([^)]*\)\s*{[\s\S]*?root\._anchor[\s\S]*?}/,
        "Screen.onWidthChanged must call root._anchor (via Qt.callLater)",
    );
    assert.match(
        SRC,
        /Connections\s*{[\s\S]*?target\s*:\s*root\.Screen[\s\S]*?function\s+onHeightChanged\s*\([^)]*\)\s*{[\s\S]*?root\._anchor[\s\S]*?}/,
        "Screen.onHeightChanged must call root._anchor (via Qt.callLater)",
    );
});

test("Window-level onScreenChanged also re-anchors", () => {
    // Catches the same-resolution dual-monitor case where the
    // attached Screen.width / Screen.height stay numerically equal
    // but the Window physically migrated to a different display
    // — the Connections above wouldn't fire.
    assert.match(
        SRC,
        /onScreenChanged\s*:[\s\S]{0,100}_anchor/,
        "onScreenChanged must trigger _anchor() so the window re-anchors when migrating between same-resolution monitors",
    );
});
