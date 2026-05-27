// Text-level guards for the standalone `ProcReader` C++ helper.
// `standalone/proc_reader.cpp` exposes a `Q_INVOKABLE QString read(...)`
// to every QML context in the standalone build. Same text-guard pattern
// as `autostart.test.mjs`, `desktop-hints.test.mjs`, and
// `standalone-main.test.mjs`.
//
// The contract these guards lock in:
//
//   1. `read()` checks the path is under `/proc/` or `/sys/` BEFORE
//      opening the file. Without the allowlist, the helper becomes an
//      arbitrary file-read primitive accessible from every QML leaf —
//      a leaf doing `reader.read("/etc/shadow")` would otherwise
//      succeed if the binary runs with read access to that file.
//
//   2. The refusal path emits a `qWarning` so accidental misuse is
//      greppable in the journal, not silently truncated to "".
//
//   3. No Plasma headers — standalone isolation invariant.

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const SRC = readFileSync(
    join(__dirname, "..", "standalone", "proc_reader.cpp"),
    "utf8",
);
const HEADER = readFileSync(
    join(__dirname, "..", "standalone", "proc_reader.h"),
    "utf8",
);

test("ProcReader::read allowlist applies to cleanPath-normalised input", () => {
    // The allowlist is a dev-time sanity check (the widget runs as
    // the user, so this isn't a privilege boundary — see proc_reader.h).
    // But the comment promises "/proc/ and /sys/ only", which only
    // holds if `..` is resolved BEFORE the prefix check; otherwise
    // `reader.read("/proc/../etc/passwd")` would pass the prefix
    // gate and the kernel would dereference the `..` on open.
    // QDir::cleanPath normalises `..` lexically (no filesystem
    // touch) — must run before the `startsWith` checks.
    assert.match(
        SRC,
        /QDir::cleanPath\s*\(\s*path\s*\)/,
        "must run path through QDir::cleanPath before the allowlist",
    );
    // The `startsWith` checks must operate on the cleaned variable,
    // not the raw `path` argument.
    assert.match(
        SRC,
        /cleaned\.startsWith\(\s*QStringLiteral\(\s*"\/proc\/"\s*\)\s*\)/,
        "must check cleaned.startsWith(\"/proc/\")",
    );
    assert.match(
        SRC,
        /cleaned\.startsWith\(\s*QStringLiteral\(\s*"\/sys\/"\s*\)\s*\)/,
        "must check cleaned.startsWith(\"/sys/\")",
    );
    // The QFile open must use the cleaned path too — otherwise the
    // kernel-level `..` resolution happens against the original.
    assert.match(
        SRC,
        /QFile\s+file\s*\(\s*cleaned\s*\)/,
        "must open QFile(cleaned), not QFile(path)",
    );
    // Short-circuit before open — otherwise we leak the open attempt
    // (file descriptor bump, possible audit log line on locked-down
    // distros).
    assert.match(
        SRC,
        /!cleaned\.startsWith[\s\S]*?!cleaned\.startsWith[\s\S]*?return \{\};/,
        "must `return {};` before opening the file when the allowlist refuses",
    );
});

test("ProcReader::read includes <QDir> for cleanPath", () => {
    // QDir::cleanPath lives in <QDir>; without the include the file
    // would fail to compile.
    assert.match(
        SRC,
        /#include\s*<QDir>/,
        "must include <QDir> for QDir::cleanPath",
    );
});

test("ProcReader::read warns on refused paths", () => {
    // Silently returning "" matches the I/O-error contract callers
    // already handle, but accidental misuse should be greppable in the
    // journal so a developer notices their leaf is wrong.
    assert.match(
        SRC,
        /qWarning\(\)[\s\S]*?refused[\s\S]*?allowlist/,
        "must qWarning when refusing a path outside the allowlist",
    );
});

test("proc_reader includes no Plasma headers (standalone isolation)", () => {
    assert.doesNotMatch(
        SRC,
        /#include\s*<plasma\//,
        "proc_reader.cpp must not include Plasma headers",
    );
    assert.doesNotMatch(
        HEADER,
        /#include\s*<plasma\//,
        "proc_reader.h must not include Plasma headers",
    );
});
