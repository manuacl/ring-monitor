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

test("menu_entry.cpp builds the Exec= line via desktop_entry::execLine", () => {
    assert.match(
        SRC,
        /desktop_entry::execLine\s*\(\s*\)/,
        "buildDesktopFileContent must use the shared desktop_entry::execLine() rather than re-implementing AppImage-path resolution",
    );
});

test("menu entry declares a launcher (Type=Application + Icon)", () => {
    assert.match(SRC, /Type=Application/, "must declare Type=Application");
    assert.match(SRC, /Icon=/, "must declare an Icon so it renders in the menu");
    // The autostart-only key must NOT leak into the menu entry.
    assert.doesNotMatch(
        SRC,
        /X-GNOME-Autostart-enabled/,
        "the menu entry must not carry the autostart key",
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
    // Enable: the copy must exist BEFORE the content is rendered, since
    // execLine() only points Exec= at it once it exists. Disable: the
    // copy is removed iff no other entry references it.
    const fn = SRC.slice(SRC.indexOf("MenuEntry::setEnabled"));
    const body = fn.slice(0, fn.indexOf("\n}\n"));
    const ensureIdx = body.search(/desktop_entry::ensureStableCopy\(\)/);
    const writeIdx = body.search(/desktop_entry::writeDesktopFile\(/);
    assert.ok(ensureIdx >= 0, "setEnabled(true) must call ensureStableCopy");
    assert.ok(writeIdx >= 0 && ensureIdx < writeIdx, "ensureStableCopy must precede writeDesktopFile");
    assert.match(body, /desktop_entry::removeStableCopyIfOrphaned\(\)/, "setEnabled(false) must clean up an orphaned copy");
});

test("constructor refreshes the stable copy only when the entry exists (#136)", () => {
    // A launch with the toggle off must not create the copy; a pre-copy
    // install (entry with an absolute Exec=) migrates here.
    const ctor = SRC.slice(SRC.indexOf("MenuEntry::MenuEntry"));
    const body = ctor.slice(0, ctor.indexOf("\n}\n"));
    assert.match(
        body,
        /if\s*\(\s*QFileInfo::exists\(\s*desktopFilePath\(\)\s*\)\s*\)\s*\n?\s*desktop_entry::ensureStableCopy\(\)/,
        "the ctor must gate ensureStableCopy on the entry existing",
    );
});

test("menu entry declares StartupWMClass for taskbar grouping", () => {
    // The launched window should group under the launcher icon. The
    // standalone window's WM_CLASS is the binary basename.
    assert.match(
        SRC,
        /StartupWMClass=ring-monitor-standalone/,
        "buildDesktopFileContent must set StartupWMClass to the standalone window's WM_CLASS",
    );
});
