import { test } from "node:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import assert from "node:assert";

// Text-level guard for ProcessSampler.qml — the standalone source for the
// CPU-ring process tooltip (issue #69). Same rationale as
// standalone-metrics-backend.test.mjs: the file imports `RingMonitor.Standalone`
// (the ProcReader C++ helper), absent from the CI container, so a
// qmltestrunner smoke test would fail to load. The ranking/parsing math itself
// is covered runtime-free in process-ranking.test.mjs + proc-parser.test.mjs;
// this guards the QML wiring those pure modules can't see.

const __dirname = dirname(fileURLToPath(import.meta.url));
const SRC = readFileSync(join(__dirname, "..", "contents", "ui", "platforms", "standalone", "ProcessSampler.qml"), "utf8");

test("ProcessSampler exposes the tooltip surface MetricsBackend forwards", () => {
    assert.match(SRC, /property\s+bool\s+active/, "must declare the `active` gate");
    assert.match(SRC, /property\s+var\s+topProcesses/, "must expose topProcesses");
    assert.match(SRC, /property\s+var\s+loadAverages/, "must expose loadAverages");
});

test("ProcessSampler enumerates /proc and ranks via the shared module", () => {
    assert.match(SRC, /import\s+RingMonitor\.Standalone/, "must import RingMonitor.Standalone (ProcReader)");
    assert.match(SRC, /ProcReader\s*{/, "must instantiate its own ProcReader");
    assert.match(SRC, /reader\.listDir\(["']\/proc["']\)/, "must list /proc to discover pid dirs");
    assert.match(SRC, /reader\.read\(["']\/proc\/["']\s*\+\s*entries\[i\]\s*\+\s*["']\/stat["']\)/, "must read each pid's /proc/<pid>/stat");
    assert.match(SRC, /reader\.read\(["']\/proc\/loadavg["']\)/, "must read /proc/loadavg for the footer");
    assert.match(SRC, /ProcParser\.computePercents\s*\(/, "must compute per-process % via ProcParser");
    assert.match(SRC, /ProcessRanking\.rankByCpu\s*\(/, "must rank + cap via the shared core/ProcessRanking");
});

test("ProcessSampler only samples while active (no background polling, #69)", () => {
    // The whole point of the gate: enumerating /proc is the heaviest read path,
    // so the Timer must be bound to `active` (the tooltip's hover state), NOT
    // left always-running like the MetricsBackend metric Timer.
    assert.match(SRC, /Timer\s*{[\s\S]*?running:\s*sampler\.active/, "the Timer's running must be bound to active");
    // Dropping the prev snapshot on deactivate prevents a stale first delta on
    // the next hover (the gap could be minutes; the jiffy delta would be huge).
    assert.match(SRC, /onActiveChanged:\s*{[\s\S]*?_reset\(\)/, "must reset the prev snapshot when active flips off");
});

test("ProcessSampler is Plasma-free (standalone isolation)", () => {
    // The standalone build ships zero org.kde.* beyond Kirigami. This sampler
    // touches /proc only — no ksysguard, no plasmoid.
    assert.doesNotMatch(SRC, /import\s+org\.kde\.(?!kirigami)/, "must not import a non-Kirigami org.kde.* module");
});

test("ProcessSampler exposes the RAM tooltip surface (issue #70)", () => {
    // Same-surface rule: the Plasma adapter exposes these three as readonly
    // properties; the standalone sampler must match byte-for-byte so the RAM
    // tooltip QML can bind without a platform branch.
    assert.match(SRC, /readonly\s+property\s+var\s+topMemProcesses/, "must expose topMemProcesses as a readonly property (not a function — frozen-binding trap)");
    assert.match(SRC, /readonly\s+property\s+real\s+memUsedKb/, "must expose memUsedKb as a readonly property");
    assert.match(SRC, /readonly\s+property\s+real\s+memTotalKb/, "must expose memTotalKb as a readonly property");
});

test("ProcessSampler builds memory ranking from curMap snapshot, no prev/cur delta", () => {
    // RSS is a point-in-time field — no delta required — so the ranking is
    // built from curMap directly. This means topMemProcesses has data on the
    // very first tick (unlike topProcesses, which needs a second tick for a
    // jiffy delta). Guard that rankByMemory is called and that rssPages is
    // converted via the cached pageKb factor.
    assert.match(SRC, /ProcessRanking\.rankByMemory\s*\(/, "must rank by memory via the shared core/ProcessRanking");
    assert.match(SRC, /rssKb\s*:\s*\w+\.rssPages\s*\*\s*pageKb/, "must convert rssPages → rssKb using the cached pageKb factor");
});

test("ProcessSampler caches pageSize once, never calls it inside the per-pid loop", () => {
    // reader.pageSize() is a C++ round-trip; calling it for every process on
    // every tick would be O(N) calls per tick instead of O(1). The value is
    // constant for the process lifetime, so it must be cached once.
    assert.match(SRC, /reader\.pageSize\s*\(\s*\)/, "must call reader.pageSize() to seed the cache");
    // The per-pid loop iterates over curMap entries. Guard that pageSize() is
    // not inside that loop by checking it is NOT called in the for…in block.
    const forInBlock = SRC.match(/for\s*\(\s*var\s+\w+\s+in\s+curMap\s*\)[\s\S]*?(?=\n\s*\/\/\s*Memory ranking|\n\s*var\s+memRaw|\n\s*sampler\._memTop)/);
    assert.ok(forInBlock, "must find the for…in curMap loop body");
    assert.doesNotMatch(forInBlock[0], /reader\.pageSize\s*\(/, "reader.pageSize() must NOT be called inside the per-pid loop (call it once and cache)");
});

test("ProcessSampler reads /proc/meminfo inside _sample, not on a background timer", () => {
    // The meminfo read must happen inside _sample() — which is gated on the
    // hover Timer — not at the MetricsBackend level or on an independent Timer.
    // This preserves the "no background polling while the tooltip is closed"
    // guarantee.
    assert.match(SRC, /reader\.read\(["']\/proc\/meminfo["']\)/, "must read /proc/meminfo for the RAM footer");
    assert.match(SRC, /MemInfoParser\.parseMemInfo\s*\(/, "must parse /proc/meminfo via MemInfoParser");
    // Confirm the read is wired to MemInfoParser (not MetricsBackend's own
    // reader) by checking the import is present in this file.
    assert.match(SRC, /import\s+["']MemInfoParser\.js["']\s+as\s+MemInfoParser/, "must import MemInfoParser.js");
});

test("ProcessSampler computes memUsedKb as total − available", () => {
    // MemTotal − MemAvailable is the kernel's honest "used" figure (same
    // formula as `free -h`). Guard the arithmetic so it can't regress to
    // MemTotal − MemFree (which counts reclaimable page cache as used).
    assert.match(SRC, /mem\.total\s*-\s*mem\.available/, "memUsedKb must be MemTotal − MemAvailable (not MemFree)");
    // Guard must be a null-check (the parser's missing-field sentinel), not
    // truthiness: available === 0 is a real reading (full OOM) and must yield
    // used = total, not the 0 fallback.
    assert.match(SRC, /mem\.total\s*!==\s*null\s*&&\s*mem\.available\s*!==\s*null/, "memUsedKb guard must null-check, not truthiness-check (available can be 0)");
});

test("ProcessSampler resets RAM surface in _reset()", () => {
    // When the tooltip closes (active → false) _reset() clears _memTop,
    // _memUsedKb, and _memTotalKb so a re-hover doesn't flash stale data
    // before the first tick fires.
    const resetBlock = SRC.match(/function\s+_reset\s*\(\s*\)\s*{[\s\S]*?}/);
    assert.ok(resetBlock, "must find the _reset() body");
    assert.match(resetBlock[0], /_memTop\s*=\s*\[\s*\]/, "_reset must clear _memTop");
    assert.match(resetBlock[0], /_memUsedKb\s*=\s*0/, "_reset must zero _memUsedKb");
    assert.match(resetBlock[0], /_memTotalKb\s*=\s*0/, "_reset must zero _memTotalKb");
});
