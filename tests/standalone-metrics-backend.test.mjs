import { test } from "node:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import assert from "node:assert";

// Text-level guard for the standalone MetricsBackend adapter. Same
// rationale as tests/metrics-backend.test.mjs (its Plasma counterpart):
// the file imports `RingMonitor.Standalone` (the ProcReader C++ helper
// registered via QML_ELEMENT), which is built by CMake locally but NOT
// in the Fedora 41 CI container (CI ships Qt6 + Kirigami, no cmake
// step for standalone/). A qmltestrunner-based smoke test would fail
// to load. Asserting the public surface as text catches the same
// class of bug (typo in a property name → silent undefined binding in
// production) without needing the helper available.
//
// Per platforms/standalone/CLAUDE.md § Same-surface rule, the
// standalone adapter must mirror the Plasma adapter byte-for-byte on
// the public surface main.qml consumes.

const __dirname = dirname(fileURLToPath(import.meta.url));
const SOURCE = readFileSync(join(__dirname, "..", "contents", "ui", "platforms", "standalone", "MetricsBackend.qml"), "utf8");

// Same public surface as platforms/plasma/MetricsBackend.qml.
const PUBLIC_PROPS = ["coreValues", "loading"];
const PUBLIC_FUNCS = ["metricValue", "metricRawTemp", "metricTempPercent"];

test("standalone MetricsBackend exposes the public properties main.qml depends on", () => {
    for (const name of PUBLIC_PROPS) {
        const pattern = new RegExp(`property\\s+\\w+\\s+${name}\\s*:`);
        assert.match(SOURCE, pattern, `standalone MetricsBackend.qml must declare property "${name}"`);
    }
});

test("standalone MetricsBackend exposes the public functions main.qml depends on", () => {
    for (const name of PUBLIC_FUNCS) {
        const pattern = new RegExp(`function\\s+${name}\\s*\\(`);
        assert.match(SOURCE, pattern, `standalone MetricsBackend.qml must declare function ${name}(...)`);
    }
});

test("standalone MetricsBackend wires ProcReader + ProcStatParser", () => {
    assert.match(SOURCE, /ProcReader\s*{/, "must instantiate the ProcReader QML element");
    assert.match(SOURCE, /import\s+RingMonitor\.Standalone/, "must import RingMonitor.Standalone (where ProcReader is registered)");
    assert.match(SOURCE, /ProcStatParser\.parseProcStat\s*\(/, "must call ProcStatParser.parseProcStat on the raw text");
    assert.match(SOURCE, /ProcStatParser\.percentFromSample\s*\(/, "must call ProcStatParser.percentFromSample to derive the % between two samples");
});

test("standalone MetricsBackend wires RAM via /proc/meminfo + MemInfoParser", () => {
    assert.match(SOURCE, /reader\.read\(["']\/proc\/meminfo["']\)/, "must read /proc/meminfo through the ProcReader helper");
    assert.match(SOURCE, /MemInfoParser\.parseMemInfo\s*\(/, "must call MemInfoParser.parseMemInfo on the raw text");
    assert.match(SOURCE, /MemInfoParser\.usagePercent\s*\(/, "must compute the RAM percent through the shared usagePercent helper");
});

test("standalone MetricsBackend wires disk via statvfs(/)", () => {
    assert.match(SOURCE, /reader\.statvfs\s*\(/, "must call ProcReader.statvfs(...) for disk usage");
    // The default mount is "/" — matches the plan's MVP scope. A
    // future per-mount selector is allowed to override this, but the
    // current default must stay on root.
    assert.match(SOURCE, /["']\/["']/, "must reference the root mount '/' for the default disk path");
    // Review finding 🟠 PR #30: disk usage must use df(1)'s formula
    // via diskUsagePercent, not the naive usagePercent (which counts
    // the ext4 5% root reservation as used and reports a non-zero
    // percent on a freshly-formatted empty disk). Lock the wiring in.
    assert.match(
        SOURCE,
        /MemInfoParser\.diskUsagePercent\s*\(\s*disk\.total\s*,\s*disk\.free\s*,\s*disk\.available\s*\)/,
        "disk percent must be computed via diskUsagePercent(total, free, available) so it matches `df`",
    );
});

test("standalone MetricsBackend exposes ram + disk through metricValue", () => {
    // metricValue must route the new ids to the freshly-sampled
    // backing properties. Catches the failure mode where the wiring
    // exists but the public function still returns 0 for ram/disk.
    assert.match(SOURCE, /id\s*===\s*["']ram["']/, "metricValue must branch on id === 'ram'");
    assert.match(SOURCE, /id\s*===\s*["']disk["']/, "metricValue must branch on id === 'disk'");
});

test("standalone MetricsBackend wires CPU temperature via CpuTempDiscovery", () => {
    // CPU temp has no fixed sysfs path — the backend enumerates
    // /sys/class/hwmon (+ /sys/class/thermal fallback) and delegates
    // the "which entry is the CPU" decision to the pure module.
    assert.match(SOURCE, /import\s+["']CpuTempDiscovery\.js["']\s+as\s+CpuTemp/, "must import the same-dir CpuTempDiscovery module (platforms/standalone/)");
    assert.match(SOURCE, /reader\.listDir\s*\(/, "must enumerate sysfs via ProcReader.listDir");
    assert.match(SOURCE, /\/sys\/class\/hwmon/, "must scan /sys/class/hwmon");
    assert.match(SOURCE, /\/sys\/class\/thermal/, "must fall back to /sys/class/thermal");
    assert.match(SOURCE, /CpuTemp\.pickCpuHwmonDir\s*\(/, "must pick the CPU hwmon chip via the pure helper");
    assert.match(SOURCE, /CpuTemp\.pickCpuTempInput\s*\(/, "must pick the CPU temp input via the pure helper");
    assert.match(SOURCE, /CpuTemp\.pickCpuThermalZone\s*\(/, "must pick the CPU thermal zone via the pure helper");
    assert.match(SOURCE, /CpuTemp\.parseTempCelsius\s*\(/, "must parse the millidegrees reading via the pure helper");
});

test("standalone MetricsBackend exposes cpuTemp as a raw-°C metric", () => {
    // MainContent treats cpuTemp (Catalog.isTempMetric) as raw °C from
    // metricValue, and uses metricRawTemp('cpu') + metricTempPercent('cpu')
    // for the merged split ring — both must be wired.
    assert.match(SOURCE, /id\s*===\s*["']cpuTemp["']/, "metricValue must branch on id === 'cpuTemp'");
    assert.match(SOURCE, /function\s+metricRawTemp[\s\S]*?id\s*===\s*["']cpu["'][\s\S]*?_coerceTemp/, "metricRawTemp('cpu') must return the coerced °C");
    assert.match(SOURCE, /function\s+metricTempPercent[\s\S]*?Catalog\.tempToPercent\s*\(/, "metricTempPercent must map through Catalog.tempToPercent");
});

test("standalone MetricsBackend coerces an unresolved temp to 0 (same-surface with Plasma)", () => {
    // A temp sensor reads NaN until resolved; the public surface must
    // return 0 then, matching the Plasma adapter (valueFromSensorMap
    // returns 0 for an unread sensor). Otherwise a consumer doing
    // arithmetic gets NaN on standalone but 0 on Plasma.
    //
    // Assert intent (a coercer that finiteness-checks its arg and yields
    // 0 otherwise), not the exact ternary spelling — so a harmless
    // rewrite / qmlformat reflow doesn't red the guard.
    const body = SOURCE.match(/function\s+_coerceTemp\s*\(\s*\w+\s*\)\s*{([\s\S]*?)}/);
    assert.ok(body, "must declare function _coerceTemp(celsius)");
    assert.match(body[1], /isFinite/, "_coerceTemp must finiteness-check before returning");
    assert.match(body[1], /\b0\b/, "_coerceTemp must yield 0 when not finite");
    // The cpuTemp / gpuTemp metric branches route through the coercer
    // rather than returning the raw NaN-bearing property.
    assert.match(SOURCE, /["']cpuTemp["'][\s\S]{0,60}_coerceTemp/, "metricValue('cpuTemp') must return the coerced value");
    assert.match(SOURCE, /["']gpuTemp["'][\s\S]{0,60}_coerceTemp/, "metricValue('gpuTemp') must return the coerced value");
});

test("standalone MetricsBackend wires NVIDIA GPU usage + temperature via NvmlReader", () => {
    // GPU comes from the NVML C++ helper (dlopen'd libnvidia-ml), not a
    // subprocess. The adapter instantiates it, samples each tick, and
    // only commits values when the sample is available (non-NVIDIA hosts
    // report available:false → metrics stay 0).
    assert.match(SOURCE, /NvmlReader\s*{/, "must instantiate the NvmlReader QML element");
    assert.match(SOURCE, /import\s+RingMonitor\.Standalone/, "must import RingMonitor.Standalone (where NvmlReader is registered)");
    assert.match(SOURCE, /\.sample\s*\(\s*\)/, "must call NvmlReader.sample()");
    assert.match(SOURCE, /\.available\b/, "must gate on the sample's available flag");
    assert.match(SOURCE, /id\s*===\s*["']gpu["'][\s\S]*?_gpuUsage/, "metricValue('gpu') must return GPU usage");
    assert.match(SOURCE, /id\s*===\s*["']gpuTemp["']/, "metricValue must branch on id === 'gpuTemp'");
    assert.match(SOURCE, /function\s+metricRawTemp[\s\S]*?id\s*===\s*["']gpu["'][\s\S]*?_coerceTemp/, "metricRawTemp('gpu') must return the coerced GPU °C");
});

test("standalone MetricsBackend re-resolves the temp path within a bounded warm-up window", () => {
    // A hwmon driver modprobed shortly after autostart (login before the
    // sensor modules load) must be picked up — but a machine with NO CPU
    // temp sensor must not re-walk /sys forever. So the retry is bounded:
    // resolve while empty AND under a max attempt count, then give up.
    assert.match(SOURCE, /property\s+int\s+_cpuTempMaxResolveAttempts/, "must declare a bounded max-attempts property");
    assert.match(
        SOURCE,
        /!\s*backend\._cpuTempPath\s*&&\s*backend\._cpuTempResolveAttempts\s*<\s*backend\._cpuTempMaxResolveAttempts/,
        "_sample must gate the re-resolve on both an empty path AND the attempt bound",
    );
    assert.match(SOURCE, /_cpuTempResolveAttempts\+\+|_cpuTempResolveAttempts\s*=\s*backend\._cpuTempResolveAttempts\s*\+\s*1/, "must increment the attempt counter so the retry terminates");
});

test("standalone MetricsBackend polls on a Timer", () => {
    // Polling cadence: once per second is the contract documented in
    // platforms/standalone/CLAUDE.md. Use the interval value as the
    // marker — looser than full Timer block matching, tighter than no
    // assertion at all.
    assert.match(SOURCE, /Timer\s*{[\s\S]*?interval:\s*1000/, "must declare a Timer with interval: 1000ms");
});
