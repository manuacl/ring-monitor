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
