// Text-level guards for standalone/desktop_entry.cpp — the shared
// Exec= resolution used by BOTH the autostart writer (Autostart) and
// the application-menu writer (MenuEntry). Same plain-text inspection
// pattern as autostart.test.mjs (no C++ unit-test harness in-tree).
//
// What we lock in here — the subtle bits that, if they regress, break
// AppImage launches silently and would otherwise have to be re-proven
// in two writers:
//
// 1. execLine() = `env QT_QPA_PLATFORM=xcb ` + quoteExecArg(currentExecPath()).
//    Without the quote, an AppImage under a path with spaces
//    (`~/Applications/Ring Monitor.AppImage`) breaks launching: the
//    XDG launcher tokenises on whitespace.
// 2. The XDG-spec escape order: backslash MUST be escaped before `"`,
//    `$`, and backtick — otherwise the inserted backslashes from the
//    later passes get doubled.
// 3. currentExecPath() matches $APPDIR with a trailing slash, so a
//    sibling AppImage mount with a coincidental prefix doesn't hijack
//    the Exec path.

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

test("execLine wraps currentExecPath through quoteExecArg", () => {
    assert.match(
        SRC,
        /quoteExecArg\s*\(\s*currentExecPath\s*\(\s*\)\s*\)/,
        "execLine must wrap currentExecPath() through quoteExecArg",
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
