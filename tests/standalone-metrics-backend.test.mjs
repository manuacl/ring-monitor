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
const PUBLIC_PROPS = ["coreValues", "loading", "availablePartitions", "defaultPartitionIds"];
const PUBLIC_FUNCS = ["metricValue", "metricRawTemp", "metricTempPercent", "partitionValue"];

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

test("standalone MetricsBackend wires disk multi-partition discovery", () => {
    // The disk metric is now per-filesystem: parse /proc/mounts, dedup by
    // device, label by volume name, pick the $HOME-bearing default. The
    // composefs-"/" hardcode is gone (it read ~100% on every rpm-ostree
    // host). Pin the DiskDiscovery wiring so it can't regress to statvfs("/").
    assert.match(SOURCE, /import\s+["']DiskDiscovery\.js["']\s+as\s+DiskDiscovery/, "must import the same-dir DiskDiscovery module");
    assert.match(SOURCE, /reader\.read\(["']\/proc\/mounts["']\)/, "must read /proc/mounts through the ProcReader helper");
    assert.match(SOURCE, /DiskDiscovery\.parseMounts\s*\(/, "must parse mounts via the pure helper");
    assert.match(SOURCE, /DiskDiscovery\.buildPartitions\s*\(/, "must build the deduped partition list via the pure helper");
    assert.match(SOURCE, /DiskDiscovery\.defaultOrFirst\s*\(/, "must resolve the default via defaultOrFirst (same helper the picker uses, incl. the first-partition fallback)");
    assert.match(SOURCE, /reader\.blockDeviceInfo\s*\(/, "must resolve uuid/label via ProcReader.blockDeviceInfo");
    assert.match(SOURCE, /reader\.canonicalHome\s*\(/, "must resolve $HOME via ProcReader.canonicalHome");
    assert.doesNotMatch(SOURCE, /_diskMount/, "the hardcoded composefs '/' mount must be gone");
});

test("standalone MetricsBackend reads per-partition usage via statvfs + df formula", () => {
    // partitionValue(id) statvfs's the selected partition's representative
    // mountpoint and applies df(1)'s formula (not the naive usagePercent,
    // which counts the ext4 5% root reservation as used).
    assert.match(SOURCE, /function\s+partitionValue\s*\(/, "must declare partitionValue(id)");
    assert.match(SOURCE, /reader\.statvfs\s*\(/, "partitionValue must call ProcReader.statvfs(...)");
    assert.match(
        SOURCE,
        /MemInfoParser\.diskUsagePercent\s*\(\s*disk\.total\s*,\s*disk\.free\s*,\s*disk\.available\s*\)/,
        "per-partition percent must use diskUsagePercent(total, free, available) so it matches `df`",
    );
});

test("standalone MetricsBackend exposes ram + disk through metricValue", () => {
    // metricValue must route the new ids to the freshly-sampled
    // backing properties. Catches the failure mode where the wiring
    // exists but the public function still returns 0 for ram/disk.
    assert.match(SOURCE, /id\s*===\s*["']ram["']/, "metricValue must branch on id === 'ram'");
    assert.match(SOURCE, /id\s*===\s*["']disk["']/, "metricValue must branch on id === 'disk'");
});

test("standalone MetricsBackend routes swap through metricValue (not hardcoded 0)", () => {
    // SCENARIO: the swap ring read a dead 0 on a host with active zram
    // because metricValue('swap') was hardcoded to `return 0`. Pin the
    // branch + the SwapTotal/SwapFree sampling so it can't regress.
    assert.match(SOURCE, /id\s*===\s*["']swap["'][\s\S]{0,40}_swapUsage/, "metricValue('swap') must return backend._swapUsage");
    assert.match(SOURCE, /_swapUsage\s*=\s*MemInfoParser\.usagePercent\(\s*mem\.swapTotal\s*,\s*mem\.swapFree\s*\)/, "must compute swap usage from the parsed SwapTotal/SwapFree");
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
    // Pin the actual argument, not just proximity of the _coerceTemp token:
    // a regression like _coerceTemp(0) or a wrong property must red the guard.
    assert.match(SOURCE, /function\s+metricRawTemp[\s\S]*?id\s*===\s*["']cpu["'][\s\S]*?_coerceTemp\(\s*backend\._cpuTempC\s*\)/, "metricRawTemp('cpu') must coerce backend._cpuTempC");
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
    // The cpuTemp / gpuTemp metric branches route through the coercer with
    // their OWN backing property as the argument — pin the property, not
    // just the _coerceTemp token's proximity, so _coerceTemp(0) or a
    // copy-paste using the wrong property reds the guard.
    assert.match(SOURCE, /["']cpuTemp["'][\s\S]{0,60}_coerceTemp\(\s*backend\._cpuTempC\s*\)/, "metricValue('cpuTemp') must coerce backend._cpuTempC");
    assert.match(SOURCE, /["']gpuTemp["'][\s\S]{0,60}_coerceTemp\(\s*backend\._gpuTempC\s*\)/, "metricValue('gpuTemp') must coerce backend._gpuTempC");
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
    assert.match(SOURCE, /function\s+metricRawTemp[\s\S]*?id\s*===\s*["']gpu["'][\s\S]*?_coerceTemp\(\s*backend\._gpuTempC\s*\)/, "metricRawTemp('gpu') must coerce backend._gpuTempC");
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
    // Polling cadence: 500 ms (2 Hz) to match the Plasma ksysguard
    // cadence — see platforms/standalone/CLAUDE.md. Use the interval
    // value as the marker — looser than full Timer block matching,
    // tighter than no assertion at all.
    assert.match(SOURCE, /Timer\s*{[\s\S]*?interval:\s*500/, "must declare a Timer with interval: 500ms");
});
