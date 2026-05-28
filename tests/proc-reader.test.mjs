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

test("ProcReader::listDir shares the read() /proc-/sys allowlist", () => {
    // listDir is the directory-listing companion used for hwmon /
    // thermal CPU-temp discovery. It must carry the same cleanPath +
    // prefix guard as read() — otherwise it becomes an arbitrary
    // directory-enumeration primitive reachable from every QML leaf.
    assert.match(
        SRC,
        /QStringList ProcReader::listDir[\s\S]*?QDir::cleanPath\s*\(\s*path\s*\)/,
        "listDir must run its argument through QDir::cleanPath before the allowlist",
    );
    assert.match(
        SRC,
        /QStringList ProcReader::listDir[\s\S]*?cleaned\.startsWith\(\s*QStringLiteral\(\s*"\/proc\/"\s*\)\s*\)[\s\S]*?cleaned\.startsWith\(\s*QStringLiteral\(\s*"\/sys\/"\s*\)\s*\)[\s\S]*?return \{\};/,
        "listDir must refuse (return {}) paths outside the /proc-/sys allowlist",
    );
    assert.match(
        SRC,
        /qWarning\(\)[\s\S]*?listDir refused[\s\S]*?allowlist/,
        "listDir must qWarning when refusing a path outside the allowlist",
    );
    // Excludes . and .. so callers don't have to filter them out.
    assert.match(
        SRC,
        /entryList\([^)]*QDir::NoDotAndDotDot/,
        "listDir must pass QDir::NoDotAndDotDot to entryList",
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

test("ProcReader exposes blockDeviceInfo + canonicalHome for disk discovery", () => {
    // DiskDiscovery.js needs a stable id (fs UUID) + friendly label
    // (volume label) per partition, and the resolved $HOME to pick the
    // default. Both are declared Q_INVOKABLE in the header.
    assert.match(
        HEADER,
        /Q_INVOKABLE\s+QVariantMap\s+blockDeviceInfo\s*\(\s*\)\s*const/,
        "must declare Q_INVOKABLE QVariantMap blockDeviceInfo() const",
    );
    assert.match(
        HEADER,
        /Q_INVOKABLE\s+QString\s+canonicalHome\s*\(\s*\)\s*const/,
        "must declare Q_INVOKABLE QString canonicalHome() const",
    );
});

test("blockDeviceInfo walks both by-uuid and by-label, resolves to device", () => {
    // The id must be the fs UUID (stable across reboots / sd* reordering)
    // and the label the volume label — mirrors ksysguard's Plasma keying.
    assert.match(SRC, /\/dev\/disk\/by-uuid/, "must enumerate /dev/disk/by-uuid");
    assert.match(SRC, /\/dev\/disk\/by-label/, "must enumerate /dev/disk/by-label");
    // canonicalFilePath resolves the by-uuid/by-label symlink to /dev/sdaN.
    assert.match(
        SRC,
        /canonicalFilePath\s*\(\s*\)/,
        "must resolve the symlink to its device via canonicalFilePath",
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
