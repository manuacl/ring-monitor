// Text-level guards for standalone/autostart.cpp. The codebase has
// no C++ unit-test harness (would require linking against Qt6Test +
// the autostart TU under CMake), so we follow the same pattern as
// config-store.test.mjs / metrics-backend.test.mjs: read the source
// as plain text and assert the behavioural contract.
//
// The Exec= resolution (AppImage path + XDG quoting) now lives in
// standalone/desktop_entry.cpp, shared with MenuEntry — its escape
// order and $APPDIR-prefix guards are in desktop-entry.test.mjs. Here
// we only lock in what's specific to the autostart writer:
//
// 1. The Exec= line is built from desktop_entry::execLine() — so the
//    AppImage-path + quoting logic isn't re-implemented (and can't
//    drift from the menu-entry writer).
// 2. The autostart entry carries X-GNOME-Autostart-enabled=true.
// 3. `setEnabled(false)` removes the file rather than rewriting it
//    empty (cheap regression guard around the existing behaviour).

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const SRC = readFileSync(
    join(__dirname, "..", "standalone", "autostart.cpp"),
    "utf8",
);

test("autostart.cpp builds the Exec= line via desktop_entry::execLine", () => {
    // Whitespace-tolerant: matches the call regardless of formatting.
    // The shared helper is what carries quoteExecArg(currentExecPath()).
    assert.match(
        SRC,
        /desktop_entry::execLine\s*\(\s*\)/,
        "buildDesktopFileContent must use the shared desktop_entry::execLine()",
    );
});

test("autostart entry declares X-GNOME-Autostart-enabled", () => {
    assert.match(
        SRC,
        /X-GNOME-Autostart-enabled=true/,
        "the autostart .desktop must carry the GNOME autostart key",
    );
});

test("setEnabled routes writes/removes through the shared desktop_entry helpers", () => {
    // The mkpath + write + remove plumbing is shared with MenuEntry via
    // desktop_entry (atomic QSaveFile write, self-heal) — autostart must
    // delegate, not re-implement, so a fix to one writer covers both.
    assert.match(
        SRC,
        /desktop_entry::writeDesktopFile\(/,
        "setEnabled(true) must delegate to desktop_entry::writeDesktopFile",
    );
    assert.match(
        SRC,
        /desktop_entry::removeDesktopFile\(/,
        "setEnabled(false) must delegate to desktop_entry::removeDesktopFile",
    );
});

test("setEnabled emits enabledChanged so the view re-syncs on a failed write", () => {
    // The checkbox optimistically flips on click; emitting regardless of
    // write success lets it un-tick if the write failed.
    assert.match(SRC, /Q_EMIT\s+enabledChanged\(\)/, "setEnabled must emit enabledChanged after the write/remove attempt");
});
