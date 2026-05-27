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

test("ProcReader::read refuses paths outside /proc/ and /sys/", () => {
    // Review finding 🟠 PR #29: the allowlist is the entire mitigation,
    // so it must (a) check both prefixes, (b) return early before the
    // QFile open, and (c) cover the `read` method (statvfs is checked
    // separately by its own QML callers — see _diskMount validation).
    assert.match(
        SRC,
        /path\.startsWith\(\s*QStringLiteral\(\s*"\/proc\/"\s*\)\s*\)/,
        "must check path starts with /proc/",
    );
    assert.match(
        SRC,
        /path\.startsWith\(\s*QStringLiteral\(\s*"\/sys\/"\s*\)\s*\)/,
        "must check path starts with /sys/",
    );
    // The allowlist branch must `return {}` before the QFile open —
    // otherwise the file is opened and partial side effects (e.g.
    // bumping nr_open count in some weird /etc/ overlay) leak.
    assert.match(
        SRC,
        /!path\.startsWith[\s\S]*?!path\.startsWith[\s\S]*?return \{\};/,
        "must short-circuit with `return {};` before opening the file",
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
