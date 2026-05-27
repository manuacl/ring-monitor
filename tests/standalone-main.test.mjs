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
    // The match accepts whitespace variation but rejects a direct
    // `_anchor()` call from Component.onCompleted (which would
    // bypass the deferral and hit the wrong window-type).
    assert.match(
        SRC,
        /Component\.onCompleted\s*:\s*Qt\.callLater\(\s*_anchor\s*\)/,
        "Component.onCompleted must defer _anchor via Qt.callLater",
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
