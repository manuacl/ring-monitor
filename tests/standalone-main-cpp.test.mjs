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

test("main.cpp self-heals stale launcher entries on every startup (#126)", () => {
    // The autostart / menu .desktop files embed the versioned AppImage
    // path; after an update that path is stale and login launches the old
    // binary. main.cpp constructs both helpers on startup so their ctors
    // run refreshIfStale on EVERY launch — not only when Settings is opened
    // (the only prior instantiation site). refreshIfStale itself is gated to
    // AppImage runs, so a dev build constructing these is a no-op.
    assert.match(
        SRC,
        /Autostart\s+\w+\s*;/,
        "main.cpp must construct an Autostart on startup so its ctor refreshes a stale entry",
    );
    assert.match(
        SRC,
        /MenuEntry\s+\w+\s*;/,
        "main.cpp must construct a MenuEntry on startup so its ctor refreshes a stale entry",
    );
    // Must come after the single-instance defer paths (which return early),
    // i.e. before the engine is built but reached only by the real widget.
    const autostartIdx = SRC.search(/Autostart\s+\w+\s*;/);
    const engineIdx = SRC.search(/QQmlApplicationEngine\s+engine/);
    assert.ok(autostartIdx >= 0 && engineIdx >= 0 && autostartIdx < engineIdx, "the launcher refresh must run before the QML engine is constructed");
});

test("main.cpp picks a window strategy and gates both X11 calls on X11Ewmh (PR C2)", () => {
    // One decideWindowStrategy() call drives the pre-app platform setup
    // and the post-load per-window integration.
    assert.match(
        SRC,
        /decideWindowStrategy\(\s*openSettings\s*\)/,
        "main.cpp must call decideWindowStrategy(openSettings) once",
    );
    // PER-WINDOW layer-shell: main.cpp must NOT call the global
    // useLayerShell() — that sets QT_WAYLAND_SHELL_INTEGRATION process-wide
    // and turns every window (context menu popup, settings dialog) into a
    // fullscreen layer surface. The layer role is opted into per-window via
    // WaylandLayerShell::configure() (LayerShellQt::Window::get) instead,
    // so popups/dialogs stay normal xdg-shell. SCENARIO: the fullscreen,
    // un-closeable right-click menu the global call produced.
    assert.doesNotMatch(
        SRC,
        /LayerShellQt::Shell::useLayerShell\s*\(/,
        "main.cpp must NOT call LayerShellQt::Shell::useLayerShell() — per-window opt-in keeps popups/dialogs normal (fullscreen-menu regression guard)",
    );
    // Both X11-only calls are gated on strategy == X11Ewmh, so the
    // WaylandLayerShell and Floating (recovery) paths get neither: no
    // QT_QPA_PLATFORM force, no EWMH hints.
    assert.match(
        SRC,
        /strategy\s*==\s*ringmonitor::WindowStrategy::X11Ewmh\s*\)\s*ringmonitor::forceXWaylandUnderWayland\(\)/,
        "forceXWaylandUnderWayland must be gated on strategy == X11Ewmh",
    );
    assert.match(
        SRC,
        /if\s*\(\s*strategy\s*==\s*ringmonitor::WindowStrategy::X11Ewmh\s*\)\s*\{[\s\S]*?applyDesktopWindowHints/,
        "applyDesktopWindowHints must be gated on strategy == X11Ewmh",
    );
});
