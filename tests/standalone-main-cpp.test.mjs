// Text-level guards for the standalone C++ entry point
// (`standalone/main.cpp`). Same Node-text-guard pattern as
// `autostart.test.mjs`, `desktop-hints.test.mjs`, `proc-reader.test.mjs`,
// and `standalone-main.test.mjs` (which covers the QML side). This
// file covers the C++ side specifically because `main.cpp` parses
// argv and decides whether to call `applyDesktopWindowHints` /
// `forceXWaylandUnderWayland`, and there's no Qt-runtime test that
// can drive `argc/argv` from outside.
//
// The contract these guards lock in:
//
//   1. `--open-settings` (and the `--settings` alias) parsed from
//      argv before QGuiApplication constructs.
//   2. The parsed flag is exposed to QML as the `settingsOnlyMode`
//      context property — the QML side reads that to skip the
//      rings window and show the SettingsDialog directly.
//   3. EWMH hints + XWayland forcing are skipped in settings-only
//      mode (the settings dialog is a normal floating window, not
//      a wallpaper-layer widget).

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const SRC = readFileSync(
    join(__dirname, "..", "standalone", "main.cpp"),
    "utf8",
);

test("main.cpp parses --open-settings (and --settings alias) from argv", () => {
    // Review finding 🟠 PR #32: a CLI recovery flag so users locked
    // out of right-click on DESKTOP-typed windows can still reach
    // the settings dialog.
    assert.match(
        SRC,
        /--open-settings/,
        "main.cpp must accept the --open-settings flag",
    );
    assert.match(
        SRC,
        /--settings/,
        "main.cpp must accept the --settings alias",
    );
});

test("main.cpp exposes settingsOnlyMode as a QML context property", () => {
    // The QML side (Main.qml) reads `settingsOnlyMode` to branch on
    // recovery mode — see `standalone-main.test.mjs`. Lock the
    // property NAME here so a rename can't silently drift.
    assert.match(
        SRC,
        /setContextProperty\([^)]*["']settingsOnlyMode["']/,
        "must register the parsed flag as a QML context property named settingsOnlyMode",
    );
});

test("settings-only mode skips EWMH hints and XWayland forcing", () => {
    // The settings dialog is a normal floating window — applying
    // _NET_WM_WINDOW_TYPE_DESKTOP / BELOW to it would hide the
    // recovery UI behind the wallpaper, defeating the whole point.
    // Same for QT_QPA_PLATFORM=xcb force: the settings dialog
    // doesn't need X11.
    assert.match(
        SRC,
        /if\s*\(\s*!openSettings\s*\)[\s\S]{0,200}?forceXWaylandUnderWayland\(\)/,
        "forceXWaylandUnderWayland must be gated on !openSettings",
    );
    assert.match(
        SRC,
        /if\s*\(\s*!openSettings\s*\)\s*\{[\s\S]*?applyDesktopWindowHints/,
        "applyDesktopWindowHints must be gated on !openSettings",
    );
});
