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
//   2. The parsed flag switches the QML root that's loaded —
//      `SettingsOnlyRoot` (recovery, dialog-only) vs `Main` (rings
//      widget). No `settingsOnlyMode` context property is exposed
//      anymore (the SettingsOnlyRoot refactor erased the eight-site
//      flag threading).
//   3. EWMH hints + XWayland forcing are skipped in recovery mode
//      (the settings dialog is a normal floating window, not a
//      wallpaper-layer widget).

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
    // out of right-click on the wallpaper-layer window can still reach
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

test("main.cpp loads SettingsOnlyRoot in recovery mode, Main otherwise", () => {
    // The SettingsOnlyRoot refactor swapped flag-threading for
    // root-swapping: --open-settings loads a minimal recovery QML
    // root, the normal launch loads the full widget. The choice
    // must be wired through engine.loadFromModule.
    assert.match(
        SRC,
        /openSettings\s*\?\s*["']SettingsOnlyRoot["']\s*:\s*["']Main["']/,
        "must pick SettingsOnlyRoot vs Main based on openSettings",
    );
    assert.match(
        SRC,
        /engine\.loadFromModule\(\s*["']RingMonitor\.Standalone["']\s*,\s*qmlRoot\s*\)/,
        "must pass the chosen root name to loadFromModule",
    );
    // Regression guard: the old `setContextProperty("settingsOnlyMode", ...)`
    // shape MUST be gone — leaving it would resurrect the eight-site
    // threading the refactor erased.
    assert.doesNotMatch(
        SRC,
        /setContextProperty\([^)]*settingsOnlyMode/,
        "must NOT setContextProperty(\"settingsOnlyMode\", ...) — recovery is a separate QML root now",
    );
});

test("main.cpp ties the app to its desktop entry (Wayland app_id)", () => {
    // PR H (AppImage): setDesktopFileName makes the Wayland compositor
    // map the surface to packaging/dev.manuacl.ringmonitor.desktop, so
    // the bundled icon + taskbar grouping resolve. The id must match
    // the .desktop basename and the autostart desktop id verbatim.
    assert.match(
        SRC,
        /setDesktopFileName\(\s*["']dev\.manuacl\.ringmonitor["']\s*\)/,
        "main.cpp must call setDesktopFileName(\"dev.manuacl.ringmonitor\")",
    );
});

test("settings-only mode skips EWMH hints and XWayland forcing", () => {
    // The settings dialog is a normal floating window — applying the
    // BELOW state (with skip-taskbar / skip-pager) to it would push the
    // recovery UI behind other windows, defeating the whole point.
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
