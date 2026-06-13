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
    // The bare "/proc" root must be allowed: cleanPath strips the trailing
    // slash, so "/proc" / "/proc/" both arrive as "/proc" and would miss the
    // "/proc/" prefix test. Process enumeration for the CPU-ring tooltip
    // (#69) lists "/proc" itself to find the pid dirs — a future refactor
    // that drops this exact-root clause silently re-blocks that enumeration
    // (listDir returns {} → an empty tooltip with no error).
    assert.match(
        SRC,
        /QStringList ProcReader::listDir[\s\S]*?cleaned != QStringLiteral\(\s*"\/proc"\s*\)/,
        'listDir must allow the bare "/proc" root (pid enumeration, #69)',
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

test("ProcReader exposes the async statvfs surface (issue #48)", () => {
    // The disk rings must read per-partition usage WITHOUT blocking the GUI
    // thread on an unresponsive mount. The header declares the non-blocking
    // pair + the completion signal.
    assert.match(
        HEADER,
        /Q_INVOKABLE\s+void\s+requestStatvfs\s*\(\s*const\s+QString\s*&/,
        "must declare Q_INVOKABLE void requestStatvfs(const QString &mount)",
    );
    assert.match(
        HEADER,
        /Q_INVOKABLE\s+QVariantMap\s+cachedStatvfs\s*\(\s*const\s+QString\s*&[^)]*\)\s*const/,
        "must declare Q_INVOKABLE QVariantMap cachedStatvfs(const QString &mount) const",
    );
    assert.match(
        HEADER,
        /signals:[\s\S]*?void\s+statvfsReady\s*\(\s*const\s+QString\s*&/,
        "must declare the statvfsReady(const QString &mount) signal",
    );
});

test("requestStatvfs runs statvfs on a detached worker thread (no GUI block, no exit hang)", () => {
    // A detached std::thread — NOT a QThreadPool — is deliberate: a pool's
    // dtor waitForDone() would block process exit forever on a mount stuck
    // in an uninterruptible statvfs; a detached thread is reaped by the OS
    // at exit instead. The blocking syscall must run off the GUI thread and
    // the result hop back via the event loop.
    assert.match(SRC, /std::thread/, "must spawn a std::thread for the blocking statvfs");
    assert.match(SRC, /\.detach\s*\(\s*\)/, "the worker thread must be detached (so a stuck mount can't hang process exit)");
    assert.doesNotMatch(SRC, /QThreadPool/, "must NOT use QThreadPool (its dtor would block exit on a hung mount)");
    assert.match(SRC, /QMetaObject::invokeMethod/, "must hop the result back to the GUI thread via QMetaObject::invokeMethod");
    assert.match(SRC, /QPointer<ProcReader>/, "must guard the queued delivery with a QPointer in case ProcReader is torn down first");
});

test("requestStatvfs dedups in-flight mounts and throttles re-reads", () => {
    // Idempotent by construction: a mount already being read is not
    // re-launched (so a hung mount freezes exactly one worker, not a pile),
    // and a mount read within the throttle window is skipped (so
    // re-evaluating the QML binding every render doesn't spin the syscall).
    assert.match(SRC, /m_statvfsInFlight\.contains\s*\(\s*mount\s*\)/, "must skip a mount that already has a worker in flight");
    assert.match(SRC, /m_statvfsInFlight\.insert\s*\(\s*mount\s*\)/, "must mark a mount in-flight before launching its worker");
    assert.match(SRC, /kStatvfsMinIntervalMs/, "must throttle re-reads against kStatvfsMinIntervalMs");
});

test("ProcReader::pageSize is Q_INVOKABLE and returns sysconf(_SC_PAGESIZE)", () => {
    // The QML sampler calls pageSize() once to convert rssPages (pages) from
    // /proc/<pid>/stat field 24 to KiB. Must be Q_INVOKABLE so QML can call
    // it, and must delegate to sysconf(_SC_PAGESIZE) — the POSIX call that
    // reports the actual kernel page size for this process.
    assert.match(
        HEADER,
        /Q_INVOKABLE\s+qlonglong\s+pageSize\s*\(\s*\)\s*const/,
        "must declare Q_INVOKABLE qlonglong pageSize() const",
    );
    assert.match(
        SRC,
        /qlonglong ProcReader::pageSize[\s\S]*?sysconf\s*\(\s*_SC_PAGESIZE\s*\)/,
        "pageSize() must call sysconf(_SC_PAGESIZE)",
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
