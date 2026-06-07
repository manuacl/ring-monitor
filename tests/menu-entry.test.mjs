// Text-level guards for standalone/menu_entry.cpp — the writer behind
// the "Show in application menu" toggle (issues #101 / #102). Same
// plain-text inspection pattern as autostart.test.mjs.
//
// What we lock in:
//
// 1. The launcher lands in the XDG applications dir
//    (writableLocation(ApplicationsLocation) = ~/.local/share/applications),
//    NOT the autostart dir — otherwise it never shows in the menu.
// 2. The Exec= line reuses the shared desktop_entry::execLine(), so
//    the AppImage-path + quoting logic isn't duplicated and can't
//    drift from the autostart writer.
// 3. The entry declares Type=Application + Icon= so it renders as a
//    real launcher.
// 4. setEnabled(false) removes the file (untick = remove the entry).

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const SRC = readFileSync(
    join(__dirname, "..", "standalone", "menu_entry.cpp"),
    "utf8",
);

test("menu entry path delegates to the shared desktop_entry::menuFilePath", () => {
    // The XDG dir resolution (ApplicationsLocation) lives in
    // desktop_entry.cpp — guarded there — so the orphan check and the
    // writer can't drift on the path.
    assert.match(
        SRC,
        /desktop_entry::menuFilePath\s*\(\s*\)/,
        "desktopFilePath must delegate to desktop_entry::menuFilePath()",
    );
});

test("menu_entry.cpp renders its content via desktop_entry::menuFileContent", () => {
    // The template (incl. the execLine() Exec= resolution) lives in
    // desktop_entry so the async copy worker can re-render the entry from
    // its thread; the writer must delegate, not own a second copy of it.
    // Template content (Type=Application, Icon, StartupWMClass, no
    // autostart key) is guarded in desktop-entry.test.mjs.
    assert.match(
        SRC,
        /desktop_entry::menuFileContent\s*\(\s*\)/,
        "buildDesktopFileContent must delegate to desktop_entry::menuFileContent()",
    );
});

test("setEnabled routes writes/removes through the shared desktop_entry helpers", () => {
    assert.match(SRC, /desktop_entry::writeDesktopFile\(/, "setEnabled(true) must delegate to desktop_entry::writeDesktopFile");
    assert.match(SRC, /desktop_entry::removeDesktopFile\(/, "setEnabled(false) must delegate to desktop_entry::removeDesktopFile");
});

test("setEnabled emits enabledChanged so the checkbox re-syncs on a failed write", () => {
    // Without this a failed write (unwritable dir / full disk) leaves the
    // checkbox showing 'enabled' while no .desktop exists.
    assert.match(SRC, /Q_EMIT\s+enabledChanged\(\)/, "setEnabled must emit enabledChanged after the write/remove attempt");
});

test("constructor self-heals a stale Exec= via desktop_entry::refreshIfStale", () => {
    // If the AppImage moved, the stored Exec= points at a dead path; the
    // constructor rewrites it so the menu entry never silently launches a
    // gone binary while the toggle claims it is healthy.
    const ctor = SRC.slice(SRC.indexOf("MenuEntry::MenuEntry"));
    assert.match(
        ctor.slice(0, ctor.indexOf("\n}")),
        /desktop_entry::refreshIfStale\(/,
        "the constructor must call desktop_entry::refreshIfStale to refresh a moved AppImage's launcher",
    );
});

test("setEnabled maintains the stable copy (#136)", () => {
    // Enable: kick the async copy (the entry converges to the stable path
    // when the worker finishes). Disable: the copy is removed iff no
    // other entry references it.
    const fn = SRC.slice(SRC.indexOf("MenuEntry::setEnabled"));
    const body = fn.slice(0, fn.indexOf("\n}\n"));
    assert.match(body, /desktop_entry::ensureStableCopyAsync\(\)/, "setEnabled(true) must kick ensureStableCopyAsync");
    assert.match(body, /desktop_entry::removeStableCopyIfOrphaned\(\)/, "setEnabled(false) must clean up an orphaned copy");
});

test("constructor kicks the stable-copy refresh only when the entry exists (#136)", () => {
    // A launch with the toggle off must not create the copy; a pre-copy
    // install (entry with an absolute Exec=) migrates here.
    const ctor = SRC.slice(SRC.indexOf("MenuEntry::MenuEntry"));
    const body = ctor.slice(0, ctor.indexOf("\n}\n"));
    assert.match(
        body,
        /if\s*\(\s*QFileInfo::exists\(\s*desktopFilePath\(\)\s*\)\s*\)\s*\n?\s*desktop_entry::ensureStableCopyAsync\(\)/,
        "the ctor must gate ensureStableCopyAsync on the entry existing",
    );
});

