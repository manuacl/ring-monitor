// Text-level guards for standalone/autostart.cpp. The codebase has
// no C++ unit-test harness (would require linking against Qt6Test +
// the autostart TU under CMake), so we follow the same pattern as
// config-store.test.mjs / metrics-backend.test.mjs: read the source
// as plain text and assert the behavioural contract.
//
// What we lock in here:
//
// 1. The Exec= line goes through `quoteExecArg(currentExecPath())`
//    — without this, an AppImage installed under a path with spaces
//    (e.g. `~/Applications/Ring Monitor.AppImage`) breaks autostart
//    silently because the XDG launcher tokenises on whitespace.
// 2. The XDG-spec escape order is preserved: backslash MUST be
//    escaped before `"`, `$`, and backtick — otherwise the inserted
//    backslashes from the later passes get doubled.
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

test("autostart.cpp wires quoteExecArg into the Exec= line", () => {
    // Whitespace-tolerant: matches the call regardless of formatting.
    assert.match(
        SRC,
        /quoteExecArg\s*\(\s*currentExecPath\s*\(\s*\)\s*\)/,
        "buildDesktopFileContent must wrap currentExecPath() through quoteExecArg",
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
    // The final return concatenates a leading `"`, the escaped arg,
    // and a trailing `"`. We assert both literal `"` chars appear in
    // the return path of quoteExecArg.
    const fnStart = SRC.indexOf("Autostart::quoteExecArg");
    assert.ok(fnStart >= 0, "quoteExecArg definition not found");
    const fnEnd = SRC.indexOf("}\n", fnStart);
    const body = SRC.slice(fnStart, fnEnd);
    assert.match(
        body,
        /QLatin1Char\('"'\)\s*\+[\s\S]*\+\s*QLatin1Char\('"'\)/,
        "return value must be wrapped in double quotes",
    );
});

test("setEnabled(false) removes the autostart file (no empty-rewrite)", () => {
    // Cheap regression guard — keep the existing `QFile::remove(path)`
    // pattern rather than truncating to an empty file.
    assert.match(
        SRC,
        /QFile::remove\(\s*path\s*\)/,
        "setEnabled(false) must call QFile::remove on the autostart file",
    );
});
