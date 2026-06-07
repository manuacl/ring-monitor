// Text-level guards for standalone/desktop_entry.cpp — the shared
// Exec= resolution used by BOTH the autostart writer (Autostart) and
// the application-menu writer (MenuEntry). Same plain-text inspection
// pattern as autostart.test.mjs (no C++ unit-test harness in-tree).
//
// What we lock in here — the subtle bits that, if they regress, break
// AppImage launches silently and would otherwise have to be re-proven
// in two writers:
//
// 1. execLine() = `env QT_QPA_PLATFORM=xcb ` + quoteExecArg(<target>),
//    where <target> prefers the stable copy (#136) and falls back to
//    currentExecPath(). Without the quote, an AppImage under a path
//    with spaces (`~/Applications/Ring Monitor.AppImage`) breaks
//    launching: the XDG launcher tokenises on whitespace.
// 2. The XDG-spec escape order: backslash MUST be escaped before `"`,
//    `$`, and backtick — otherwise the inserted backslashes from the
//    later passes get doubled.
// 3. currentExecPath() matches $APPDIR with a trailing slash, so a
//    sibling AppImage mount with a coincidental prefix doesn't hijack
//    the Exec path.
// 4. The stable copy (#136): version-independent path, atomic replace,
//    AppImage-gated, removed only when orphaned.

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const SRC = readFileSync(
    join(__dirname, "..", "standalone", "desktop_entry.cpp"),
    "utf8",
);

test("execLine prefers the stable copy and falls back to the live path (#136)", () => {
    const fn = SRC.slice(SRC.indexOf("QString execLine()"));
    const body = fn.slice(0, fn.indexOf("\n}\n"));
    // Version-stamped AppImage filenames die on upgrade; the stable copy's
    // path never does. The fallback covers a copy that couldn't be created
    // (unwritable ~/.local/bin) — a healed Exec= beats a dangling one.
    assert.match(body, /runningAsAppImage\(\)/, "the stable-copy preference must be gated on AppImage runs");
    assert.match(body, /stableExecPath\(\)/, "execLine must reference the stable copy");
    assert.match(body, /currentExecPath\(\)/, "execLine must keep the live-path fallback");
    assert.match(body, /quoteExecArg\(/, "the chosen target must go through quoteExecArg");
});

test("stableExecPath is a fixed, version-independent path", () => {
    // The permanence is the whole point of #136 — a version stamp in the
    // basename would recreate the bug the copy exists to fix.
    assert.match(
        SRC,
        /\.local\/bin\/ring-monitor\.AppImage/,
        "the stable copy must live at ~/.local/bin/ring-monitor.AppImage (no version stamp)",
    );
});

test("ensureStableCopyAsync is gated on runningAsAppImage (no dev-build shadowing)", () => {
    // A throwaway source build must never overwrite the stable copy a real
    // AppImage install relies on at login.
    const fn = SRC.slice(SRC.indexOf("void ensureStableCopyAsync()"));
    const body = fn.slice(0, fn.indexOf("\n}\n"));
    assert.match(
        body,
        /!\s*runningAsAppImage\(\)\s*\)?\s*\n?\s*return/,
        "ensureStableCopyAsync must bail when not running as an AppImage",
    );
});

test("the staleness check no-ops when running FROM the copy itself", () => {
    // A login launch runs the copy: the copy IS the source, so copying
    // would clobber the file backing our own FUSE mount. Canonical compare
    // so a symlinked ~/.local/bin still matches.
    const fn = SRC.slice(SRC.indexOf("bool stableCopyStale("));
    const body = fn.slice(0, fn.indexOf("\n}\n"));
    assert.match(
        body,
        /\.canonicalFilePath\(\)\s*==\s*\w+\.canonicalFilePath\(\)/,
        "stableCopyStale must compare source and copy canonically and bail when they are the same file",
    );
});

test("the AppImage copy runs on a DETACHED worker with in-flight dedup", () => {
    // The copy (>100 MB) froze the first post-upgrade launch when it ran
    // inline in the QML ctors. Detached (not pooled): a QThreadPool dtor
    // would block process exit on a copy stuck on a hung mount — same
    // rationale as ProcReader's statvfs worker. The atomic in-flight guard
    // means a hung copy freezes one thread, never a pile.
    const fn = SRC.slice(SRC.indexOf("void ensureStableCopyAsync()"));
    const body = fn.slice(0, fn.indexOf("\n}\n"));
    assert.match(body, /std::thread\(/, "the copy must run on a std::thread, not the GUI thread");
    assert.match(body, /\.detach\(\)/, "the worker must be detached so a stuck copy cannot wedge process exit");
    assert.match(body, /std::atomic<bool>[\s\S]*?\.exchange\(true\)/, "an atomic in-flight guard must drop re-entrant requests");
});

test("the worker re-renders BOTH entries and re-checks orphaning after the copy lands", () => {
    // Entries rendered before the copy existed carry the live-path
    // fallback; without this convergence pass they would keep the
    // version-stamped Exec= until the NEXT launch. The orphan re-check
    // covers a disable that raced the copy.
    const fn = SRC.slice(SRC.indexOf("void ensureStableCopyAsync()"));
    const body = fn.slice(0, fn.indexOf("\n}\n"));
    assert.match(
        body,
        /refreshIfStale\(\s*autostartFilePath\(\)\s*,\s*autostartFileContent\(\)\s*\)/,
        "the worker must re-render the autostart entry after the copy",
    );
    assert.match(
        body,
        /refreshIfStale\(\s*menuFilePath\(\)\s*,\s*menuFileContent\(\)\s*\)/,
        "the worker must re-render the menu entry after the copy",
    );
    assert.match(body, /removeStableCopyIfOrphaned\(\)/, "the worker must re-run the orphan check (disable racing the copy)");
});

test("the stable-copy replace is atomic (sibling temp + rename(2))", () => {
    // A still-running login instance may have the old copy FUSE-mounted;
    // rename(2) keeps its inode alive while new launches see the fresh
    // file. QFile::rename refuses an existing destination, so the POSIX
    // call is used directly.
    const fn = SRC.slice(SRC.indexOf("bool writeStableCopy("));
    const body = fn.slice(0, fn.indexOf("\n}\n"));
    assert.match(
        body,
        /QFile::copy\([^,]+,\s*tmp\s*\)/,
        "the payload copy must target the sibling temp file, never the destination directly",
    );
    assert.match(body, /::rename\(/, "the temp file must be moved over the destination via POSIX rename(2)");
});

test("a chmod failure ABORTS the swap; a setFileTime failure only warns", () => {
    // Non-executable copy behind Exec= = login fails with EACCES and no
    // visible error → abort and keep the previous launchable copy. A lost
    // mtime only costs a redundant re-copy next launch → warn + continue.
    const fn = SRC.slice(SRC.indexOf("bool writeStableCopy("));
    const body = fn.slice(0, fn.indexOf("\n}\n"));
    assert.match(
        body,
        /if\s*\(!QFile::setPermissions\([\s\S]*?QFile::remove\(\s*tmp\s*\);\s*\n\s*return false/,
        "a setPermissions failure must remove the temp file and abort",
    );
    assert.match(
        body,
        /if\s*\(!f\.open\([\s\S]*?\|\|\s*!f\.setFileTime\(/,
        "the open and setFileTime returns must both be checked",
    );
    // Every failure path leaves a greppable journal trace — a silent
    // failure either resurrects #136 invisibly or re-copies forever.
    const warnings = (body.match(/qWarning\(/g) || []).length;
    assert.ok(warnings >= 4, `every writeStableCopy failure path must qWarning (found ${warnings}, expected >=4)`);
});

test("the mtime handle opens ReadWrite — QFile WriteOnly implies Truncate", () => {
    // SCENARIO: a 'cleanup' to WriteOnly would WIPE the bytes just copied
    // (QIODevice docs: for file devices, WriteOnly implies Truncate unless
    // combined with ReadWrite/Append). setFileTime only needs an open
    // handle; ReadWrite is the non-destructive way to get one.
    const fn = SRC.slice(SRC.indexOf("bool writeStableCopy("));
    const body = fn.slice(0, fn.indexOf("\n}\n"));
    assert.match(body, /f\.open\(QIODevice::ReadWrite\)/, "the setFileTime handle must open ReadWrite");
    assert.doesNotMatch(body, /f\.open\(QIODevice::WriteOnly\)/, "WriteOnly would truncate the fresh copy");
});

test("the .desktop templates live in desktop_entry (worker-renderable)", () => {
    // The async worker re-renders entries from its own thread; templates
    // on the writer QObjects would force cross-thread object access.
    const auto = SRC.slice(SRC.indexOf("QString autostartFileContent()"));
    const autoBody = auto.slice(0, auto.indexOf("\n}\n"));
    assert.match(autoBody, /X-GNOME-Autostart-enabled=true/, "the autostart template must carry the GNOME autostart key");
    assert.match(autoBody, /Exec=%1/, "the autostart template must render Exec= from execLine()");
    const menu = SRC.slice(SRC.indexOf("QString menuFileContent()"));
    const menuBody = menu.slice(0, menu.indexOf("\n}\n"));
    assert.match(menuBody, /Type=Application/, "the menu template must declare Type=Application");
    assert.match(menuBody, /StartupWMClass=ring-monitor-standalone/, "the menu template must set StartupWMClass to the window's WM_CLASS");
    assert.doesNotMatch(menuBody, /X-GNOME-Autostart-enabled/, "the autostart-only key must not leak into the menu template");
});

test("removeStableCopyIfOrphaned spares the copy while either entry references it", () => {
    const fn = SRC.slice(SRC.indexOf("void removeStableCopyIfOrphaned()"));
    const body = fn.slice(0, fn.indexOf("\n}\n"));
    assert.match(body, /autostartFilePath\(\)/, "the orphan check must probe the autostart entry");
    assert.match(body, /menuFilePath\(\)/, "the orphan check must probe the menu entry");
    assert.match(
        body,
        /QFile::remove\(\s*stableExecPath\(\)\s*\)/,
        "the copy must be removed once neither entry exists",
    );
});

test("the two entry paths resolve to their XDG dirs", () => {
    // Centralised here (not in the writers) so the orphan check can probe
    // both without reaching into the writer classes.
    assert.match(
        SRC,
        /QStandardPaths::ConfigLocation\s*\)[\s\S]{0,80}?\/autostart\//,
        "autostartFilePath must resolve under ConfigLocation/autostart",
    );
    assert.match(
        SRC,
        /QStandardPaths::writableLocation\(\s*QStandardPaths::ApplicationsLocation\s*\)/,
        "menuFilePath must resolve to ApplicationsLocation (~/.local/share/applications)",
    );
});

test("execLine carries the env QT_QPA_PLATFORM=xcb prefix", () => {
    // Drives XWayland under Wayland so the EWMH window hints apply.
    assert.match(
        SRC,
        /env QT_QPA_PLATFORM=xcb /,
        "execLine must prefix the Exec value with env QT_QPA_PLATFORM=xcb",
    );
});

test("quoteExecArg escapes backslash before the other reserved chars", () => {
    // Find the four replace() calls in source order and assert the
    // first one targets the backslash literal — the spec's escape
    // order is load-bearing (later passes insert backslashes that
    // would otherwise get doubled).
    const replaces = [...SRC.matchAll(/replace\(QLatin1Char\('([^']+)'\)/g)].map(
        (m) => m[1],
    );
    assert.ok(
        replaces.length >= 4,
        `expected ≥4 replace() calls in quoteExecArg, found ${replaces.length}`,
    );
    assert.equal(
        replaces[0],
        "\\\\",
        "backslash must be the first character escaped",
    );
    // The other three chars must all be covered, in any order.
    const rest = new Set(replaces.slice(1, 4));
    for (const ch of ['"', "$", "`"]) {
        assert.ok(rest.has(ch), `quoteExecArg must escape ${ch}`);
    }
});

test("quoteExecArg wraps the result in double quotes", () => {
    const fnStart = SRC.indexOf("quoteExecArg(const QString");
    assert.ok(fnStart >= 0, "quoteExecArg definition not found");
    const fnEnd = SRC.indexOf("}\n", fnStart);
    const body = SRC.slice(fnStart, fnEnd);
    assert.match(
        body,
        /QLatin1Char\('"'\)\s*\+[\s\S]*\+\s*QLatin1Char\('"'\)/,
        "return value must be wrapped in double quotes",
    );
});

test("runningAsAppImage matches APPDIR with a trailing slash", () => {
    // A bare `self.startsWith(appDir)` matches a different AppImage
    // mount whose ID coincidentally shares a prefix (Limux/Ghostty
    // terminal hosting our binary from a sibling mount). Requiring
    // the trailing `/` enforces a directory-boundary match.
    assert.match(
        SRC,
        /self\.startsWith\(\s*QString::fromLocal8Bit\(\s*appDir\s*\)\s*\+\s*QLatin1Char\(\s*'\/'\s*\)\s*\)/,
        "the APPDIR prefix check must require a trailing slash so a coincidental prefix from a sibling mount does not match",
    );
});

test("currentExecPath returns $APPIMAGE only via the runningAsAppImage gate", () => {
    // The AppImage-vs-dev decision lives in one predicate so refreshIfStale
    // can reuse it. currentExecPath must branch on it, not re-implement the
    // env-var check.
    const fn = SRC.slice(SRC.indexOf("currentExecPath()"));
    const body = fn.slice(0, fn.indexOf("\n}\n"));
    assert.match(body, /runningAsAppImage\(\)/, "currentExecPath must branch on runningAsAppImage()");
    assert.match(body, /qgetenv\("APPIMAGE"\)/, "currentExecPath must return the $APPIMAGE path on the AppImage branch");
});

test("refreshIfStale is gated on runningAsAppImage (no dev-build hijack)", () => {
    // #126: a fixed-path dev / source build must NOT rewrite the user's
    // installed-AppImage launcher to point at the throwaway binary. The
    // self-heal therefore bails early unless we're an AppImage run — and
    // this guard precedes the file-exists check so a dev build never even
    // reads the entry.
    const fn = SRC.slice(SRC.indexOf("refreshIfStale(const QString"));
    const body = fn.slice(0, fn.indexOf("\n}\n"));
    assert.match(body, /!\s*runningAsAppImage\(\)\s*\)?\s*\n?\s*return false/, "refreshIfStale must return false when not running as an AppImage");
    const gateIdx = body.search(/runningAsAppImage\(\)/);
    const existsIdx = body.search(/QFileInfo::exists\(\s*path\s*\)/);
    assert.ok(gateIdx >= 0 && existsIdx >= 0 && gateIdx < existsIdx, "the runningAsAppImage gate must precede the file-exists check");
});

test("writeDesktopFile uses QSaveFile for an atomic write", () => {
    // A crash / power loss mid-write must not leave a truncated launcher;
    // QSaveFile commits via atomic rename, keeping the old file until the
    // new one is complete.
    assert.match(SRC, /QSaveFile\s+\w+\(\s*path\s*\)/, "writeDesktopFile must write through a QSaveFile");
    assert.match(SRC, /\.commit\(\)/, "writeDesktopFile must commit() the QSaveFile (the atomic rename)");
});

test("writeDesktopFile mkpaths the parent dir and reports failure", () => {
    const fn = SRC.slice(SRC.indexOf("writeDesktopFile(const QString"));
    const body = fn.slice(0, fn.indexOf("\n}\n"));
    assert.match(body, /mkpath\(/, "writeDesktopFile must create the parent dir (fresh profiles lack it)");
    // The mkpath guard returns false rather than silently succeeding.
    assert.match(body, /!\s*QDir\(\)\.mkpath\([\s\S]*?return false/, "writeDesktopFile must return false when mkpath fails");
    // open failure and a short write also bail out false.
    assert.match(body, /return false/, "writeDesktopFile must have a failure return path");
});

test("refreshIfStale rewrites only when the existing content differs", () => {
    const fn = SRC.slice(SRC.indexOf("refreshIfStale(const QString"));
    const body = fn.slice(0, fn.indexOf("\n}\n"));
    // No-op when the file is absent…
    assert.match(body, /QFileInfo::exists\(\s*path\s*\)/, "refreshIfStale must no-op when the file is absent");
    // …or when the rendered content already matches (compare, then rewrite).
    assert.match(body, /==\s*content/, "refreshIfStale must compare the existing file against the freshly-rendered content");
    assert.match(body, /writeDesktopFile\(/, "refreshIfStale must rewrite via writeDesktopFile when stale");
});

test("the .desktop basename is a single shared constant", () => {
    // Both writers reference desktop_entry::kDesktopFileName so a plugin-id
    // rename can't leave one pointing at a stale basename.
    const HDR = readFileSync(join(__dirname, "..", "standalone", "desktop_entry.h"), "utf8");
    assert.match(HDR, /kDesktopFileName\s*=\s*"dev\.manuacl\.ringmonitor\.desktop"/, "desktop_entry.h must define the shared kDesktopFileName constant");
});
