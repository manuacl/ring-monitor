// Text-level guards for the standalone recovery-mode QML root
// (`SettingsOnlyRoot.qml`). Loaded by `standalone/main.cpp` when the
// binary is launched with `--open-settings` / `--settings`. The file
// imports `RingMonitor.Standalone` (registered by the C++ build), so
// qmltestrunner-qt6 can't load it without the standalone binary
// linked — same Node-text-guard pattern as `standalone-main.test.mjs`
// and `standalone-metrics-backend.test.mjs`.
//
// The contract these guards lock in:
//
//   1. The root is a non-Window type (Item / QtObject). A top-level
//      `Window { visible: false }` would become the implicit
//      transient parent of any Window child instantiated inside
//      it, and the WM won't map a transient child while its parent
//      is unmapped — the SettingsDialog never appears on screen.
//      Verified live during the PR #37 verify pass.
//   2. ConfigStore + Theme + UpdateChecker are instantiated (the
//      SettingsDialog needs them) but MetricsBackend is NOT.
//      The whole point of the separate root is to avoid building
//      the metrics pipeline (Timer polling /proc + statvfs) for a
//      UI that never renders the rings.
//   3. The dialog is shown immediately on Component.onCompleted.
//   4. Qt.quit() is wired to the dialog's `onClosing` signal —
//      intent-driven (not visibility-based). A future programmatic
//      hide (modal color picker, hide-while-Apply-and-reopen)
//      must NOT kill the recovery process mid-edit.

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const SRC = readFileSync(
    join(__dirname, "..", "contents", "ui", "platforms", "standalone", "SettingsOnlyRoot.qml"),
    "utf8",
);

test("SettingsOnlyRoot uses a non-Window root (Item) to avoid transient-parent trap", () => {
    // A `Window { visible: false }` root would make the inner
    // SettingsDialog a transient child whose mapping is gated on
    // the (unmapped) parent — the dialog never appears. Verified
    // live during PR #37: with Window root, xwininfo found zero
    // ring-monitor windows after --open-settings; with Item, the
    // dialog mapped as expected. Lock the non-Window root in so a
    // future "let's make the host visible for X reason" refactor
    // can't quietly reintroduce the trap.
    assert.match(
        SRC,
        /^Item\s*{/m,
        "root component must be Item (not Window) to avoid the transient-parent mapping trap",
    );
    assert.doesNotMatch(
        SRC,
        /^Window\s*{/m,
        "root must NOT be a Window — the transient-parent gating would prevent the SettingsDialog from mapping",
    );
});

test("SettingsOnlyRoot wires ConfigStore + Theme + UpdateChecker, but NOT MetricsBackend", () => {
    // The SettingsDialog needs these three adapters to render its
    // bodies (MetricsBody reads configStore for the metric list,
    // AppearanceBody reads theme tokens, AboutBody reads
    // updateChecker for the version-available badge). MetricsBackend
    // is deliberately excluded — its Timer polls /proc/stat,
    // /proc/meminfo, and statvfs every second, which is pure waste
    // when nothing renders the values. Worse: statvfs on a stuck
    // network mount would block the GUI thread of the recovery
    // process.
    assert.match(
        SRC,
        /ConfigStore\s*{/,
        "must instantiate ConfigStore (SettingsDialog needs it)",
    );
    assert.match(
        SRC,
        /Theme\s*{/,
        "must instantiate Theme",
    );
    assert.match(
        SRC,
        /UpdateChecker\s*{/,
        "must instantiate UpdateChecker (AboutBody reads it)",
    );
    assert.doesNotMatch(
        SRC,
        /MetricsBackend\s*{/,
        "must NOT instantiate MetricsBackend — recovery mode doesn't render the rings, and Timer polling wastes /proc + statvfs syscalls (priority-4 PC-stability concern: stuck mount would block the GUI thread)",
    );
});

test("SettingsOnlyRoot shows the dialog on Component.onCompleted", () => {
    // The whole point of recovery mode is "I can't reach Settings
    // via right-click, give it to me directly". Lazy-loading the
    // dialog on a button click would defeat that.
    assert.match(
        SRC,
        /Component\.onCompleted\s*:\s*settingsDialog\.show\(\)/,
        "must show the dialog on Component.onCompleted",
    );
});

test("SettingsOnlyRoot quits on dialog `onClosing`, NOT on visibility transition", () => {
    // Using `onClosing` (intent-driven) instead of
    // `onVisibilityChanged === Window.Hidden` (state-driven) lets
    // a future feature transiently hide the dialog without killing
    // the recovery process — modal color picker, minimize-to-tray,
    // hide-while-Apply-and-reopen. The previous shape in Main.qml
    // had this fragility; the refactor fixes it.
    assert.match(
        SRC,
        /onClosing\s*:\s*Qt\.quit\(\)/,
        "must wire Qt.quit() to the dialog's onClosing signal (intent-driven)",
    );
    assert.doesNotMatch(
        SRC,
        /visibility\s*===\s*Window\.Hidden/,
        "must NOT key the quit on Window.visibility — a transient programmatic hide would kill the recovery process mid-edit",
    );
});
