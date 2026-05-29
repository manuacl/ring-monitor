import { test } from "node:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import assert from "node:assert";

// Text-level guard for the MetricsBackend adapter. Same rationale as
// tests/config-store.test.mjs — see also memory note
// feedback_ci_no_plasma_runtime: MetricsBackend.qml imports
// `org.kde.ksysguard.sensors`, which is NOT in the CI Fedora 41
// container (CI installs only Qt6 + Kirigami). A qmltestrunner-based
// smoke test would fail to load.
//
// This Node test inspects the QML source as plain text and asserts
// that the adapter exposes the public surface main.qml depends on,
// plus the discovery + Instantiator pattern that replaced the
// hardcoded per-core / per-GPU sensor declarations.

const __dirname = dirname(fileURLToPath(import.meta.url));
const SOURCE = readFileSync(join(__dirname, "..", "contents", "ui", "platforms", "plasma", "MetricsBackend.qml"), "utf8");

// Public surface main.qml consumes.
const PUBLIC_PROPS = ["coreValues", "loading", "availableMetrics", "availablePartitions", "defaultPartitionIds", "removablePartitions", "removableTrackingActive"];
const PUBLIC_FUNCS = ["metricValue", "metricRawTemp", "metricTempPercent", "partitionValue"];

// Universal-id sensor instances — sensors whose ksysguard id is the
// same on every machine. Multi-arity sensors (per-core CPU, per-GPU)
// are discovered at runtime via SensorTreeModel and instantiated via
// Instantiator, not declared statically — see the dedicated tests
// further down.
const UNIVERSAL_SENSORS = [
    { id: "cpuTotal", binding: 'Catalog.sensorIdFor("cpu")' },
    { id: "ramSensor", binding: 'Catalog.sensorIdFor("ram")' },
    { id: "swapSensor", binding: 'Catalog.sensorIdFor("swap")' },
    { id: "diskSensor", binding: 'Catalog.sensorIdFor("disk")' },
    { id: "cpuTempSensor", binding: 'Catalog.tempSensorIdFor("cpu")' },
    { id: "gpuAllSensor", binding: '"gpu/all/usage"' }
];

test("MetricsBackend exposes the public properties main.qml depends on", () => {
    for (const name of PUBLIC_PROPS) {
        const pattern = new RegExp(`property\\s+\\w+\\s+${name}\\s*:`);
        assert.match(SOURCE, pattern, `MetricsBackend.qml must declare property "${name}"`);
    }
});

test("MetricsBackend exposes the public functions main.qml depends on", () => {
    for (const name of PUBLIC_FUNCS) {
        const pattern = new RegExp(`function\\s+${name}\\s*\\(`);
        assert.match(SOURCE, pattern, `MetricsBackend.qml must declare function ${name}(...)`);
    }
});

test("MetricsBackend declares the universal-id Sensor instances", () => {
    for (const { id, binding } of UNIVERSAL_SENSORS) {
        const idPattern = new RegExp(`id:\\s*${id}\\b`);
        assert.match(SOURCE, idPattern, `MetricsBackend.qml must declare a Sensor with id: ${id}`);

        // Escape regex metachars in `binding` since it can contain ( ) " .
        const escapedBinding = binding.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        const bindingPattern = new RegExp(`sensorId:\\s*${escapedBinding}`);
        assert.match(SOURCE, bindingPattern, `Sensor ${id} must bind sensorId: ${binding}`);
    }
});

// ── Dynamic discovery via SensorTreeModel ───────────────────────────

test("MetricsBackend declares a SensorTreeModel for runtime discovery", () => {
    assert.match(SOURCE, /Sensors\.SensorTreeModel\s*{\s*[\s\S]*?id:\s*sensorTree/, "SensorTreeModel { id: sensorTree } must be declared so the walker can read it");
});

test("MetricsBackend walks the tree and delegates classification to MetricsCatalog", () => {
    // The walker is _walkTreeAndCollectIds; classification (per-core,
    // per-GPU temp/usage) happens in the pure Catalog helper.
    assert.match(SOURCE, /function\s+_walkTreeAndCollectIds\s*\(/, "must declare _walkTreeAndCollectIds()");
    assert.match(SOURCE, /Catalog\.classifyDiscoveredIds\s*\(/, "_refreshDiscovery() must call Catalog.classifyDiscoveredIds(...) so the regex bucketing stays pure-JS-testable");
});

test("MetricsBackend re-runs discovery on tree structural changes", () => {
    // Late-arriving sensors (e.g. hot-plug, slow ksysguard backends)
    // must be picked up without a widget reload.
    assert.match(SOURCE, /Connections\s*{[\s\S]*?target:\s*sensorTree[\s\S]*?onRowsInserted/, "must reconnect on sensorTree.onRowsInserted");
    assert.match(SOURCE, /Connections\s*{[\s\S]*?target:\s*sensorTree[\s\S]*?onRowsRemoved/, "must reconnect on sensorTree.onRowsRemoved");
});

test("MetricsBackend uses an Instantiator to spawn per-core Sensor instances", () => {
    // Replaces the previous 6 hardcoded cpu0..cpu5 declarations — the
    // Instantiator scales to any core count discovered at runtime.
    assert.match(SOURCE, /Instantiator\s*{[\s\S]*?id:\s*coreInstantiator[\s\S]*?model:\s*backend\._coreUsageIds/, "must declare Instantiator { id: coreInstantiator; model: backend._coreUsageIds }");
});

test("MetricsBackend uses Instantiators for per-GPU temp and usage candidates", () => {
    assert.match(SOURCE, /Instantiator\s*{[\s\S]*?id:\s*gpuTempInstantiator[\s\S]*?model:\s*backend\._gpuTempIds/, "must declare Instantiator { id: gpuTempInstantiator; model: backend._gpuTempIds }");
    assert.match(SOURCE, /Instantiator\s*{[\s\S]*?id:\s*gpuUsageInstantiator[\s\S]*?model:\s*backend\._gpuUsageIds/, "must declare Instantiator { id: gpuUsageInstantiator; model: backend._gpuUsageIds }");
});

test("coreValues binding walks the Instantiator and applies the || 0 fallback", () => {
    // The defensive `|| 0` matters — KSysGuard returns NaN for
    // not-yet-ready sensors, and the Ring expects numbers.
    assert.match(SOURCE, /coreInstantiator\.objectAt\s*\(\s*i\s*\)/, "coreValues must read each Sensor via coreInstantiator.objectAt(i)");
    assert.match(SOURCE, /s\.value\s*\|\|\s*0/, "coreValues must coerce undefined / NaN values to 0");
});

// ── Public-surface bindings unchanged from the static era ───────────

test("metricValue delegates to Catalog.valueFromSensorMap for universal ids", () => {
    assert.match(SOURCE, /Catalog\.valueFromSensorMap\s*\(\s*sensorMap\s*,\s*id\s*\)/, "metricValue(id) must call Catalog.valueFromSensorMap(sensorMap, id) for ids not handled by the dynamic helpers");
});

test("metricRawTemp delegates to Catalog.valueFromSensorMap with tempSensorMap", () => {
    assert.match(SOURCE, /Catalog\.valueFromSensorMap\s*\(\s*tempSensorMap\s*,\s*id\s*\)/, "metricRawTemp(id) must call Catalog.valueFromSensorMap(tempSensorMap, id)");
});

test("metricTempPercent delegates to Catalog.tempToPercent", () => {
    assert.match(SOURCE, /Catalog\.tempToPercent\s*\(/, "metricTempPercent(id) must call Catalog.tempToPercent(...)");
});

test("metricValue dispatches gpu and gpuTemp ids to the dynamic helpers", () => {
    // _gpuUsageValue / _gpuTempValue scan the per-GPU Instantiators for
    // the first Ready sensor — without this dispatch the dynamic path
    // would never be exercised.
    assert.match(SOURCE, /if\s*\(\s*id\s*===\s*"gpu"\s*\)\s*return\s+backend\._gpuUsageValue/, 'metricValue must short-circuit id === "gpu" to backend._gpuUsageValue');
    assert.match(SOURCE, /if\s*\(\s*id\s*===\s*"gpuTemp"\s*\)\s*return\s+backend\._gpuTempValue/, 'metricValue must short-circuit id === "gpuTemp" to backend._gpuTempValue');
});

test("MetricsBackend imports SensorPicking and delegates the 'first ready wins' picking", () => {
    // The two dynamic getters (_gpuTempValue, _gpuUsageValue) used to
    // duplicate a `for (i) { if (s.status === Ready) return s.value }`
    // block. The picking algorithm is now SensorPicking.pickFirstReadyValue
    // — a plasma-only pure module living beside this adapter in
    // platforms/plasma/ (not core/: only the Plasma backend uses it),
    // testable in Node. The QML side just maps each Sensor to a
    // {ready, value} pair and passes the list down.
    assert.match(SOURCE, /import\s+["']SensorPicking\.js["']\s+as\s+SensorPicking/, "MetricsBackend.qml must import the same-dir SensorPicking module (platforms/plasma/)");
    const callCount = (SOURCE.match(/SensorPicking\.pickFirstReadyValue\s*\(/g) || []).length;
    assert.equal(callCount, 2, "expected exactly two pickFirstReadyValue call sites (_gpuTempValue, _gpuUsageValue)");
});

test("MetricsBackend wires disk partitions via the shared DiskPartitions adapter", () => {
    // Discovery + labels come from DiskPartitions (also used by the config
    // dialog); a per-partition Sensor Instantiator backs partitionValue(id).
    assert.match(SOURCE, /DiskPartitions\s*{/, "must instantiate the DiskPartitions discovery adapter");
    assert.match(SOURCE, /model:\s*diskPartitions\.partitions/, "the disk Instantiator must be driven by the discovered partition list");
    assert.match(SOURCE, /partId:\s*modelData\.id/, "each disk Sensor delegate must expose its partition id");
    assert.match(SOURCE, /sensorId:\s*modelData\.sensorId/, "each disk Sensor must bind the discovered usedPercent sensorId");
    // defaultPartitionIds is empty on Plasma (aggregate fallback — no
    // mountpoint to match $HOME against).
    assert.match(SOURCE, /defaultPartitionIds:\s*\[\s*\]/, "Plasma defaultPartitionIds must be empty (aggregate fallback)");
});

test("MetricsBackend forwards DiskPartitions.ready as partitionsReady", () => {
    // The config picker gates its destructive stale-row removal on this — the
    // SensorTreeModel walk populates incrementally, so a non-empty partition
    // list does not mean discovery is complete (issue #49 review).
    assert.match(SOURCE, /partitionsReady:\s*diskPartitions\.ready/, "must forward diskPartitions.ready as partitionsReady");
});

test("MetricsBackend exposes a live removable-mount set gated by removableTrackingActive", () => {
    // Auto-show of USB rings (#58 Phase 2): the removable set comes from
    // MountInfo (lsblk), NOT ksysguard, so it self-heals on unplug. The
    // VALUE per ring still flows through the ksysguard partitionValue path —
    // MountInfo only governs the SET. The poll is gated so a disk-disabled
    // widget spawns no subprocess (#59 review finding 1).
    assert.match(SOURCE, /MountInfo\s*{/, "must instantiate the MountInfo lsblk adapter");
    assert.match(SOURCE, /active:\s*backend\.removableTrackingActive/, "MountInfo.active must be driven by removableTrackingActive (the poll gate)");
    assert.match(SOURCE, /property\s+var\s+removablePartitions\s*:/, "must declare removablePartitions");
    assert.match(SOURCE, /mountInfo\.mounted/, "removablePartitions must derive from mountInfo.mounted");
    assert.match(SOURCE, /\.removable\b/, "removablePartitions must filter on the removable flag");
});

test("availableMetrics gates each metric on its Sensor reaching Ready", () => {
    // A metric whose Sensor never reaches Ready (no such sensor on the
    // host) must be omitted so MainContent drops the dead 0% ring and the
    // picker greys the row. The list is built through the shared
    // Catalog.availableMetricsFrom helper from a per-metric readiness map:
    // cpu/cpuTemp/ram/swap/disk gate on their static sensor status;
    // gpu/gpuTemp on the discovered-instantiator readiness helpers
    // (mirroring _gpuUsageValue / _gpuTempValue).
    assert.match(SOURCE, /property\s+var\s+availableMetrics\s*:/, "must declare readonly property var availableMetrics");
    assert.match(SOURCE, /Catalog\.availableMetricsFrom\s*\(/, "availableMetrics must build the list via the shared Catalog.availableMetricsFrom helper");
    assert.match(SOURCE, /"cpu":\s*cpuTotal\.status\s*===\s*Sensors\.Sensor\.Ready/, 'availableMetrics map must gate "cpu" on cpuTotal Ready');
    assert.match(SOURCE, /"swap":\s*swapSensor\.status\s*===\s*Sensors\.Sensor\.Ready/, 'availableMetrics map must gate "swap" on swapSensor Ready');
    assert.match(SOURCE, /"disk":\s*diskSensor\.status\s*===\s*Sensors\.Sensor\.Ready/, 'availableMetrics map must gate "disk" on diskSensor Ready');
    assert.match(SOURCE, /function\s+_gpuUsageReady\s*\(/, "must declare _gpuUsageReady() helper");
    assert.match(SOURCE, /function\s+_gpuTempReady\s*\(/, "must declare _gpuTempReady() helper");
    assert.match(SOURCE, /"gpu":\s*backend\._gpuUsageReady\(\)/, 'availableMetrics map must gate "gpu" via _gpuUsageReady()');
    assert.match(SOURCE, /"gpuTemp":\s*backend\._gpuTempReady\(\)/, 'availableMetrics map must gate "gpuTemp" via _gpuTempReady()');
});

test("loading binding watches the universal aggregates' status", () => {
    // loading drives the 100%-fill warming-up animation in MainContent.
    // It must clear once cpuTotal AND ramSensor reach Sensor.Ready,
    // not before — otherwise the rings would jump to actual values
    // before the first valid tick.
    assert.match(SOURCE, /loading:\s*cpuTotal\.status\s*!==\s*Sensors\.Sensor\.Ready/, "loading must depend on cpuTotal.status");
    assert.match(SOURCE, /ramSensor\.status\s*!==\s*Sensors\.Sensor\.Ready/, "loading must also depend on ramSensor.status");
});
