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
// GPU sampling was extracted into GpuSampler.qml (issue #71). The always-on
// NVML + AMD/Intel sysfs logic and the new tooltip-gated detail surface live
// there; MetricsBackend wires the sampler and forwards its values.
const GPU_SOURCE = readFileSync(join(__dirname, "..", "contents", "ui", "platforms", "standalone", "GpuSampler.qml"), "utf8");

// Same public surface as platforms/plasma/MetricsBackend.qml.
const PUBLIC_PROPS = ["coreValues", "loading", "availableMetrics", "availablePartitions", "defaultPartitionIds", "processSamplingActive", "topProcesses", "loadAverages", "diskIo", "diskIoSamplingActive", "topMemProcesses", "memUsedKb", "memTotalKb"];
const PUBLIC_FUNCS = ["metricValue", "metricRawTemp", "metricTempPercent", "partitionValue", "partitionDetail"];

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

test("standalone MetricsBackend forwards the disk-I/O ring surface (issue #77)", () => {
    // The throughput sampling lives in the gated DiskIoSampler child (keeps
    // this adapter under the 500-line cap); the backend just forwards its
    // reactive `io` snapshot + the on-screen gate, and flags diskIo available.
    assert.match(SOURCE, /DiskIoSampler\s*{/, "must instantiate the DiskIoSampler child");
    assert.match(SOURCE, /property\s+var\s+diskIo\s*:\s*diskIoSampler\.io/, "diskIo must forward the sampler's io property");
    assert.match(SOURCE, /property\s+alias\s+diskIoSamplingActive\s*:\s*diskIoSampler\.active/, "diskIoSamplingActive must alias the sampler's active gate");
    assert.match(SOURCE, /"diskIo":\s*true/, 'availableMetrics map must flag "diskIo" available (/proc/diskstats always exists)');
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

test("standalone MetricsBackend reads per-partition usage via async statvfs + df formula", () => {
    // partitionValue(id) must NOT call the synchronous reader.statvfs() —
    // that blocks the GUI thread on an unresponsive mount (stale NFS, hung
    // autofs, spun-down USB), issue #48. Instead it kicks a background
    // refresh (requestStatvfs) and reads the last-good cache (cachedStatvfs),
    // applying df(1)'s formula (not the naive usagePercent, which counts the
    // ext4 5% root reservation as used).
    assert.match(SOURCE, /function\s+partitionValue\s*\(/, "must declare partitionValue(id)");
    // Anchor on the real definition (indented `function … {`), not the
    // surface-doc comment line that also says "function partitionValue(id)".
    const partFn = SOURCE.match(/\n {4}function\s+partitionValue\s*\([^)]*\)\s*{[\s\S]*?\n {4}}/);
    assert.ok(partFn, "must find the partitionValue body");
    assert.doesNotMatch(partFn[0], /reader\.statvfs\s*\(/, "partitionValue must NOT call the blocking reader.statvfs() (would freeze the GUI on a hung mount)");
    assert.match(partFn[0], /reader\.requestStatvfs\s*\(/, "partitionValue must kick a background refresh via reader.requestStatvfs(...)");
    assert.match(partFn[0], /reader\.cachedStatvfs\s*\(/, "partitionValue must read the last-good value via reader.cachedStatvfs(...)");
    assert.match(
        partFn[0],
        /MemInfoParser\.diskUsagePercent\s*\(\s*disk\.total\s*,\s*disk\.free\s*,\s*disk\.available\s*\)/,
        "per-partition percent must use diskUsagePercent(total, free, available) so it matches `df`",
    );
});

test("standalone partitionDetail assembles the #68 tooltip detail without blocking", () => {
    // Same shape as the Plasma adapter, via the shared assembler. Bytes ride the
    // SAME off-GUI-thread statvfs cache as partitionValue (no blocking statvfs).
    const detFn = SOURCE.match(/\n {4}function\s+partitionDetail\s*\([^)]*\)\s*{[\s\S]*?\n {4}}/);
    assert.ok(detFn, "must find the partitionDetail body");
    assert.doesNotMatch(detFn[0], /reader\.statvfs\s*\(/, "partitionDetail must NOT call the blocking reader.statvfs()");
    assert.match(detFn[0], /reader\.cachedStatvfs\s*\(/, "partitionDetail must read bytes from the cached (non-blocking) statvfs");
    assert.match(detFn[0], /DiskMetrics\.buildPartitionDetail\s*\(/, "partitionDetail must delegate assembly to the shared DiskMetrics helper");
});

test("standalone MetricsBackend re-renders disk rings when an async statvfs lands", () => {
    // Without a tick bump on statvfsReady the rings would only refresh on
    // the 500 ms Timer, lagging a freshly-arrived value by up to a tick.
    // A dedicated _partTick (not the shared _tick) keeps a disk-only update
    // from re-running the CPU/RAM/GPU bindings.
    assert.match(SOURCE, /property\s+int\s+_partTick/, "must declare a _partTick counter for async statvfs re-render");
    assert.match(
        SOURCE,
        /onStatvfsReady\s*\([^)]*\)\s*{[\s\S]*?_partTick\+\+/,
        "must bump _partTick from a reader.statvfsReady handler",
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
    assert.match(SOURCE, /["']gpuTemp["'][\s\S]{0,60}_coerceTemp\(\s*gpuSampler\.tempC\s*\)/, "metricValue('gpuTemp') must coerce gpuSampler.tempC (GPU temp now forwarded from GpuSampler)");
});

test("standalone MetricsBackend wires NVIDIA GPU usage + temperature via GpuSampler", () => {
    // GPU sampling is delegated to the GpuSampler child component (issue #71
    // extraction). MetricsBackend instantiates it, calls sample() each tick,
    // and reads usage/tempC/available/tempAvailable from the sampler's
    // readonly properties. The NvmlReader + NVML logic lives inside GpuSampler.
    assert.match(SOURCE, /GpuSampler\s*{/, "must instantiate the GpuSampler child component");
    assert.match(SOURCE, /gpuSampler\.sample\s*\(\s*\)/, "MetricsBackend must call gpuSampler.sample() each tick");
    assert.match(SOURCE, /id\s*===\s*["']gpu["'][\s\S]*?gpuSampler\.usage/, "metricValue('gpu') must return gpuSampler.usage");
    assert.match(SOURCE, /id\s*===\s*["']gpuTemp["']/, "metricValue must branch on id === 'gpuTemp'");
    assert.match(SOURCE, /function\s+metricRawTemp[\s\S]*?id\s*===\s*["']gpu["'][\s\S]*?_coerceTemp\(\s*gpuSampler\.tempC\s*\)/, "metricRawTemp('gpu') must coerce gpuSampler.tempC");
    // GpuSampler: NvmlReader + sample() internals
    assert.match(GPU_SOURCE, /NvmlReader\s*{/, "GpuSampler must instantiate the NvmlReader QML element");
    assert.match(GPU_SOURCE, /import\s+RingMonitor\.Standalone/, "GpuSampler must import RingMonitor.Standalone (where NvmlReader is registered)");
    assert.match(GPU_SOURCE, /gpuReader\.sample\s*\(\s*gpuSampler\.detailActive\s*\)/, "GpuSampler must call gpuReader.sample(gpuSampler.detailActive) — passes the gate so detail keys come back only when armed");
    assert.match(GPU_SOURCE, /\.available\b/, "GpuSampler must gate on the sample's available flag");
});

test("standalone MetricsBackend exposes gpuDetailSamplingActive + gpuDetail() for the GPU tooltip (#71)", () => {
    // MetricsBackend forwards the detail gate and snapshot so MainContent can
    // arm the sampler and read the tooltip data without knowing about GpuSampler.
    assert.match(SOURCE, /property\s+bool\s+gpuDetailSamplingActive/, "must declare gpuDetailSamplingActive (the cross-platform gate name, default false)");
    assert.match(SOURCE, /detailActive\s*:\s*backend\.gpuDetailSamplingActive/, "GpuSampler.detailActive must be bound to backend.gpuDetailSamplingActive");
    assert.match(SOURCE, /function\s+gpuDetail\s*\(\s*\)/, "must declare gpuDetail() to forward the sampler's detail snapshot");
    assert.match(SOURCE, /gpuSampler\.gpuDetail\s*\(\s*\)/, "gpuDetail() must delegate to gpuSampler.gpuDetail()");
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

test("standalone MetricsBackend exposes availableMetrics gating swap + gpu on their data source", () => {
    // Same-surface with the Plasma adapter (availableMetrics in PUBLIC_PROPS
    // above). The list is built through the shared Catalog.availableMetricsFrom
    // helper from a per-metric flag map: cpu/ram/disk always; cpuTemp once the
    // sysfs path resolves; swap only when SwapTotal > 0; gpu when NVML (NVIDIA)
    // or sysfs gpu_busy_percent (AMD) reports a device; gpuTemp when there is a
    // temp source (NVML or sysfs hwmon, includes Intel-temp-only) AND a finite
    // reading — no dead 0°C ring while the temp query keeps failing.
    assert.match(SOURCE, /property\s+var\s+availableMetrics\s*:/, "must declare readonly property var availableMetrics");
    assert.match(SOURCE, /Catalog\.availableMetricsFrom\s*\(/, "availableMetrics must build the list via the shared Catalog.availableMetricsFrom helper");
    assert.match(SOURCE, /_swapAvailable\s*=\s*mem\.swapTotal\s*>\s*0/, "must set _swapAvailable from mem.swapTotal > 0");
    // _gpuAvailable / _gpuTempAvailable: liveness model lives in GpuSampler;
    // MetricsBackend reads the results via gpuSampler.available / .tempAvailable.
    assert.match(GPU_SOURCE, /_gpuAvailable\s*=\s*nvml\.available/, "GpuSampler must set _gpuAvailable from the NVML sample's available flag (NVIDIA path)");
    assert.match(GPU_SOURCE, /sysfsUsageValid\s*=\s*true/, "GpuSampler must set sysfsUsageValid when AMD sysfs busy read succeeds (liveness gate for _gpuAvailable)");
    assert.match(GPU_SOURCE, /_gpuAvailable\s*=\s*nvml\.available\s*\|\|\s*sysfsUsageValid/, "GpuSampler must derive _gpuAvailable from liveness (sysfsUsageValid), not path non-emptiness");
    assert.match(SOURCE, /"cpuTemp":\s*backend\._cpuTempPath\s*!==\s*""/, 'availableMetrics map must gate "cpuTemp" on _cpuTempPath resolving');
    assert.match(SOURCE, /"swap":\s*backend\._swapAvailable/, 'availableMetrics map must gate "swap" on _swapAvailable');
    assert.match(SOURCE, /"gpu":\s*gpuSampler\.available/, 'availableMetrics map must gate "gpu" on gpuSampler.available (forwarded from GpuSampler)');
    // gpuTemp gates on gpuSampler.tempAvailable so Intel temp-only shows.
    assert.match(SOURCE, /"gpuTemp":\s*gpuSampler\.tempAvailable\s*&&\s*isFinite\(\s*gpuSampler\.tempC\s*\)/, 'availableMetrics map must gate "gpuTemp" on gpuSampler.tempAvailable AND a finite gpuSampler.tempC');
});

test("standalone availableMetrics binding does not depend on _tick (no per-poll churn)", () => {
    // SCENARIO (review #1): an earlier version read `backend._tick;` inside
    // the availableMetrics binding, so it re-evaluated every 500 ms and
    // returned a fresh array identity each tick — which churned
    // MainContent's enabledList → Repeater.model and rebuilt every Ring
    // delegate at 2 Hz (animation reset, statvfs re-kick). The binding must
    // depend only on the capability properties (each carries its own NOTIFY),
    // not on the periodic tick.
    const binding = SOURCE.match(/readonly\s+property\s+var\s+availableMetrics\s*:\s*Catalog\.availableMetricsFrom\s*\(\{[\s\S]*?\}\)/);
    assert.ok(binding, "must find the availableMetrics binding");
    assert.doesNotMatch(binding[0], /backend\._tick/, "availableMetrics must NOT read backend._tick (would rebuild the ring strip every poll)");
});

test("standalone MetricsBackend exposes removablePartitions + mountedPartitionIds for auto-show parity", () => {
    // Phase 4 auto-show: MainContent unions the manual selection with the
    // live removable set and gates manual ids on the live mount set. These
    // two properties feed DiskMetrics.resolveDiskRingIds (same surface the
    // Plasma adapter exposes). removablePartitions classifies each mounted
    // filesystem via DiskMetrics.isRemovableMount(mountpoint).
    assert.match(SOURCE, /import\s+["']\.\.\/\.\.\/core\/DiskMetrics\.js["']\s+as\s+DiskMetrics/, "must import the shared core/DiskMetrics module");
    assert.match(SOURCE, /property\s+var\s+removablePartitions\s*:/, "must declare a removablePartitions property");
    assert.match(SOURCE, /property\s+var\s+mountedPartitionIds\s*:/, "must declare a mountedPartitionIds property");
    assert.match(SOURCE, /DiskMetrics\.isRemovableMount\s*\(/, "removablePartitions must classify mounts via DiskMetrics.isRemovableMount");
});

test("GpuSampler wires AMD/Intel GPU via GpuDiscovery sysfs", () => {
    // AMD: gpu_busy_percent (usage) + hwmon temp. Intel: hwmon temp only
    // (i915-perf usage deferred — elevated perms). Discovery deferred to
    // the first non-NVIDIA tick via _resolveGpuPaths() with the same
    // bounded-retry pattern as CPU temp. This logic lives in GpuSampler,
    // extracted from MetricsBackend when the 500-line cap was reached.
    assert.match(GPU_SOURCE, /import\s+["']GpuDiscovery\.js["']\s+as\s+GpuDisc/, "GpuSampler must import GpuDiscovery.js");
    assert.match(GPU_SOURCE, /GpuDisc\.discoverGpu\s*\(/, "GpuSampler must call GpuDisc.discoverGpu to resolve AMD/Intel sysfs paths");
    assert.match(GPU_SOURCE, /function\s+_resolveGpuPaths\s*\(/, "GpuSampler must declare _resolveGpuPaths() to wire the sysfs paths on startup");
    assert.match(GPU_SOURCE, /property\s+string\s+_gpuBusyPath/, "GpuSampler must declare _gpuBusyPath for the gpu_busy_percent sysfs file");
    assert.match(GPU_SOURCE, /property\s+string\s+_gpuTempPath/, "GpuSampler must declare _gpuTempPath for the hwmon temp sysfs file");
    assert.match(GPU_SOURCE, /property\s+string\s+_gpuVendor/, "GpuSampler must declare _gpuVendor (diagnostic: 'amd'|'intel'|'')");
    // Sysfs reads happen only after the path is resolved and non-empty.
    assert.match(GPU_SOURCE, /gpuSampler\._gpuBusyPath[\s\S]{0,200}gpuSampler\.reader\.read\(\s*gpuSampler\._gpuBusyPath\s*\)/, "GpuSampler must read gpu_busy_percent when _gpuBusyPath is set");
    assert.match(GPU_SOURCE, /gpuSampler\._gpuTempPath[\s\S]{0,200}gpuSampler\.reader\.read\(\s*gpuSampler\._gpuTempPath\s*\)/, "GpuSampler must read the hwmon temp file when _gpuTempPath is set");
    assert.match(GPU_SOURCE, /GpuDisc\.parseTempCelsius\s*\(/, "GpuSampler must parse the sysfs temp via GpuDisc.parseTempCelsius (millidegrees → °C)");
    // _gpuTempAvailable: liveness model — derived from this tick's sysfs read success.
    // Fixes: Intel temp-only host shows gpuTemp ring without spurious usage ring.
    // Fixes: AMD eGPU hot-unplug — ring must disappear, not freeze at last-good value.
    assert.match(GPU_SOURCE, /property\s+bool\s+_gpuTempAvailable/, "GpuSampler must declare _gpuTempAvailable for the gpuTemp availability gate");
    assert.match(GPU_SOURCE, /sysfsTempValid\s*=\s*true/, "GpuSampler must set sysfsTempValid when AMD/Intel sysfs temp read succeeds (liveness gate for _gpuTempAvailable)");
    assert.match(GPU_SOURCE, /_gpuTempAvailable\s*=\s*nvml\.available\s*\|\|\s*sysfsTempValid/, "GpuSampler must derive _gpuTempAvailable from liveness (sysfsTempValid), not path non-emptiness");
    // Resolve loop: runs only when NVML is unavailable; retries while a STILL-EXPECTED
    // path is empty so a late-loaded hwmon is picked up after the other path resolved.
    // Fixes (#83): && closed the gate the moment one path landed (AMD gpu_busy_percent
    // present at boot but amdgpu hwmon settling seconds later → temp ring lost all session).
    // #106: temp-only vendors (Intel/nouveau) have no busy path, so the busy-path term is
    // gated on needBusyPath — otherwise the gate would re-walk /sys every tick forever.
    assert.match(GPU_SOURCE, /needBusyPath\s*&&\s*!gpuSampler\._gpuBusyPath\)\s*\|\|\s*!gpuSampler\._gpuTempPath/, "GpuSampler resolve gate retries while a still-expected path is empty; busy path required only for vendors that have one (#83/#106)");
    assert.match(GPU_SOURCE, /if\s*\(\s*!nvml\.available\s*\)/, "GpuSampler sysfs resolve+read branch must be gated on !nvml.available");
    assert.match(GPU_SOURCE, /gpuPathsIncomplete\s*&&\s*gpuSampler\._gpuResolveAttempts\s*<\s*gpuSampler\._gpuMaxResolveAttempts/, "GpuSampler resolve gate must be bounded by the attempt cap");
    // AMD detail paths — AMD power is in microwatts on amdgpu, divided by 1e6.
    assert.match(GPU_SOURCE, /\/\s*1e6/, "GpuSampler must divide AMD power1_input (microwatts) by 1e6 to get watts");
});

test("standalone MetricsBackend polls on a Timer", () => {
    // Polling cadence: 500 ms (2 Hz) to match the Plasma ksysguard
    // cadence — see platforms/standalone/CLAUDE.md. Use the interval
    // value as the marker — looser than full Timer block matching,
    // tighter than no assertion at all.
    assert.match(SOURCE, /Timer\s*{[\s\S]*?interval:\s*500/, "must declare a Timer with interval: 500ms");
});

test("standalone MetricsBackend forwards the CPU process tooltip to ProcessSampler (#69)", () => {
    // The /proc enumeration lives in the ProcessSampler child (own ProcReader
    // + Timer) so this adapter stays under the 500-line cap; the backend just
    // forwards the same-surface bits. Guarding the forwarding (not the
    // enumeration, which is ProcessSampler's own guard) keeps the wiring honest.
    assert.match(SOURCE, /ProcessSampler\s*{/, "must instantiate the ProcessSampler child");
    assert.match(SOURCE, /property\s+alias\s+processSamplingActive\s*:\s*processSampler\.active/, "processSamplingActive must alias the sampler's active gate");
    assert.match(SOURCE, /topProcesses\s*:\s*processSampler\.topProcesses/, "topProcesses must forward the sampler's ranked list (a property, for binding reactivity)");
    assert.match(SOURCE, /loadAverages\s*:\s*processSampler\.loadAverages/, "loadAverages must forward the sampler's value");
});

test("standalone MetricsBackend forwards the RAM tooltip surface from ProcessSampler (#70)", () => {
    // Same-surface rule: topMemProcesses / memUsedKb / memTotalKb must be
    // forwarded as readonly properties (not functions) so a UI binding on the
    // RAM-ring tooltip updates live as the sampler re-ranks. Reactive argless
    // data = readonly property — the frozen-binding trap applies here too.
    assert.match(SOURCE, /topMemProcesses\s*:\s*processSampler\.topMemProcesses/, "topMemProcesses must forward the sampler's RAM-ranked list");
    assert.match(SOURCE, /memUsedKb\s*:\s*processSampler\.memUsedKb/, "memUsedKb must forward the sampler's computed value");
    assert.match(SOURCE, /memTotalKb\s*:\s*processSampler\.memTotalKb/, "memTotalKb must forward the sampler's computed value");
});

test("standalone MetricsBackend exposes gpuProcesses() forwarding to GpuSampler (#71)", () => {
    // NVIDIA-only process list for the GPU tooltip. Plasma returns []; standalone
    // populates it via NVML while detailActive. MetricsBackend must forward it so
    // MainContent doesn't need to know about GpuSampler directly.
    assert.match(SOURCE, /function\s+gpuProcesses\s*\(\s*\)/, "must declare function gpuProcesses()");
    assert.match(SOURCE, /gpuSampler\.gpuProcesses\s*\(\s*\)/, "gpuProcesses() must delegate to gpuSampler.gpuProcesses()");
});

test("GpuSampler enumerates NVIDIA processes via runningProcesses + dedupeByPid + parsePidStat (#71)", () => {
    // SCENARIO: NVML returns compute + graphics entries for the same pid — dedupeByPid
    // collapses them before /proc reads so each pid is only stat'd once. parsePidStat
    // resolves the name; a process that exits between the NVML snapshot and the /proc
    // read yields an empty-string name (tolerated).
    assert.match(GPU_SOURCE, /import\s+["']ProcParser\.js["']\s+as\s+ProcParser/, "GpuSampler must import ProcParser.js");
    assert.match(GPU_SOURCE, /import\s+["']\.\.\/\.\.\/core\/GpuTooltipModel\.js["']\s+as\s+GpuModel/, "GpuSampler must import core/GpuTooltipModel.js");
    assert.match(GPU_SOURCE, /property\s+var\s+_gpuProcesses\s*:/, "GpuSampler must declare _gpuProcesses backing state");
    assert.match(GPU_SOURCE, /gpuReader\.runningProcesses\s*\(\s*\)/, "GpuSampler must call gpuReader.runningProcesses() inside the NVML detail branch");
    assert.match(GPU_SOURCE, /GpuModel\.dedupeByPid\s*\(/, "GpuSampler must collapse NVML duplicates via GpuModel.dedupeByPid before /proc reads");
    assert.match(GPU_SOURCE, /ProcParser\.parsePidStat\s*\(/, "GpuSampler must resolve pid→name via ProcParser.parsePidStat");
    assert.match(GPU_SOURCE, /function\s+gpuProcesses\s*\(\s*\)/, "GpuSampler must declare gpuProcesses() on its public surface");
});
