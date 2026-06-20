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
const PUBLIC_PROPS = ["coreValues", "loading", "availableMetrics", "availablePartitions", "defaultPartitionIds", "removablePartitions", "removableTrackingActive", "mountedPartitionIds", "mountedAvailablePartitions", "processSamplingActive", "topProcesses", "topMemProcesses", "loadAverages", "memUsedKb", "memTotalKb", "diskIo", "diskIoSamplingActive"];
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

test("MetricsBackend gates the picker partition list on the live mount set (#58)", () => {
    // ksysguard's SensorTreeModel freezes on unmount and keeps listing a
    // just-unplugged filesystem, so the config picker would offer it as a live
    // selectable row. mountedAvailablePartitions must intersect availablePartitions
    // with the live findmnt set (mountedPartitionIds) via DiskMetrics.filterToMounted.
    assert.match(SOURCE, /import\s+"\.\.\/\.\.\/core\/DiskMetrics\.js"\s+as\s+DiskMetrics/, "must import core/DiskMetrics.js");
    assert.match(
        SOURCE,
        /mountedAvailablePartitions\s*:\s*DiskMetrics\.filterToMounted\(\s*backend\.availablePartitions\s*,\s*backend\.mountedPartitionIds\s*\)/,
        "mountedAvailablePartitions must be DiskMetrics.filterToMounted(availablePartitions, mountedPartitionIds)",
    );
});

test("MetricsBackend exposes the public functions main.qml depends on", () => {
    for (const name of PUBLIC_FUNCS) {
        const pattern = new RegExp(`function\\s+${name}\\s*\\(`);
        assert.match(SOURCE, pattern, `MetricsBackend.qml must declare function ${name}(...)`);
    }
});

test("MetricsBackend forwards the disk-I/O ring surface (issue #77)", () => {
    // The disk/all/{read,write} sensor reads live in the gated DiskIoSampler
    // child (keeps this adapter under the 500-line cap); the backend forwards
    // its reactive `io` + the gate, same surface as the standalone adapter.
    assert.match(SOURCE, /DiskIoSampler\s*{/, "must instantiate the DiskIoSampler child");
    assert.match(SOURCE, /property\s+var\s+diskIo\s*:\s*diskIoSampler\.io/, "diskIo must forward the sampler's io property");
    assert.match(SOURCE, /property\s+alias\s+diskIoSamplingActive\s*:\s*diskIoSampler\.active/, "diskIoSamplingActive must alias the sampler's active gate");
    assert.match(SOURCE, /"diskIo":\s*true/, 'availableMetrics map must flag "diskIo" available');
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

test("custom temperature sensor is configurable and exposed through both sensor maps", () => {
    assert.match(
        SOURCE,
        /property\s+string\s+sensorTempId\s*:\s*""/,
        "must expose an empty sensorTempId configuration input"
    );

    assert.match(
        SOURCE,
        /Sensors\.Sensor\s*{[\s\S]*?id:\s*sensorTempSensor[\s\S]*?sensorId:\s*backend\.sensorTempId[\s\S]*?}/,
        "must declare sensorTempSensor bound to backend.sensorTempId"
    );

    assert.match(
        SOURCE,
        /sensorMap:\s*\(\{[\s\S]*?sensorTemp:\s*sensorTempSensor[\s\S]*?\}\)/,
        "sensorMap must expose sensorTempSensor as sensorTemp"
    );

    assert.match(
        SOURCE,
        /tempSensorMap:\s*\(\{[\s\S]*?sensorTemp:\s*sensorTempSensor[\s\S]*?\}\)/,
        "tempSensorMap must expose sensorTempSensor as sensorTemp"
    );
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
    // dialog). The per-partition Sensor instances live in DiskPartitionSensors
    // (split out for the 500-line cap + the 3-leaf tooltip expansion, #68);
    // MetricsBackend feeds it the discovered list + the findmnt mount set and
    // forwards partitionValue / partitionDetail.
    assert.match(SOURCE, /DiskPartitions\s*{/, "must instantiate the DiskPartitions discovery adapter");
    assert.match(SOURCE, /DiskPartitionSensors\s*{/, "must instantiate the DiskPartitionSensors adapter");
    assert.match(SOURCE, /partitions:\s*diskPartitions\.partitions/, "DiskPartitionSensors must be driven by the discovered partition list");
    assert.match(SOURCE, /mounted:\s*mountInfo\.mounted/, "DiskPartitionSensors must receive the findmnt mount set (mountpoint/fstype)");
    assert.match(SOURCE, /function\s+partitionValue\s*\(id\)\s*{\s*return\s+diskSensors\.partitionValue\(id\)/, "partitionValue must forward to the DiskPartitionSensors adapter");
    assert.match(SOURCE, /function\s+partitionDetail\s*\(id\)\s*{\s*return\s+diskSensors\.partitionDetail\(id\)/, "partitionDetail must forward to the DiskPartitionSensors adapter");
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
    // MountInfo (findmnt), NOT ksysguard, so it self-heals on unplug. The
    // VALUE per ring still flows through the ksysguard partitionValue path —
    // MountInfo only governs the SET. The poll is gated so a disk-disabled
    // widget spawns no subprocess (#59 review finding 1).
    assert.match(SOURCE, /MountInfo\s*{/, "must instantiate the MountInfo mount adapter");
    assert.match(SOURCE, /active:\s*backend\.removableTrackingActive/, "MountInfo.active must be driven by removableTrackingActive (the poll gate)");
    assert.match(SOURCE, /property\s+var\s+removablePartitions\s*:/, "must declare removablePartitions");
    assert.match(SOURCE, /removablePartitions:\s*MountInfoJs\.removableList\(\s*mountInfo\.mounted\s*\)/, "removablePartitions must derive from mountInfo.mounted via MountInfo.removableList (which filters on the removable flag)");
});

test("MetricsBackend exposes mountedPartitionIds for the #58 live-mount self-heal gate", () => {
    // MainContent gates the manual disk selection on this live mount set so an
    // unmounted partition's ring disappears even though ksysguard's tree freezes.
    assert.match(SOURCE, /property\s+var\s+mountedPartitionIds\s*:/, "must declare mountedPartitionIds");
    assert.match(SOURCE, /mountedPartitionIds[\s\S]{0,200}mountInfo\.mounted/, "mountedPartitionIds must derive from mountInfo.mounted (the live set)");
});

test("availableMetrics gates each metric on its Sensor reaching Ready", () => {
    // A metric whose Sensor never reaches Ready (no such sensor on the
    // host) must be omitted so MainContent drops the dead 0% ring and the
    // picker greys the row. The list is built through the shared
    // Catalog.availableMetricsFrom helper from a per-metric readiness map:
    // cpu/cpuTemp/ram/swap/disk/sensorTemp gate on their static sensor status;
    // gpu/gpuTemp on the discovered-instantiator readiness helpers
    // (mirroring _gpuUsageValue / _gpuTempValue).
    assert.match(SOURCE, /property\s+var\s+availableMetrics\s*:/, "must declare readonly property var availableMetrics");
    assert.match(SOURCE, /Catalog\.availableMetricsFrom\s*\(/, "availableMetrics must build the list via the shared Catalog.availableMetricsFrom helper");
    assert.match(SOURCE, /"cpu":\s*cpuTotal\.status\s*===\s*Sensors\.Sensor\.Ready/, 'availableMetrics map must gate "cpu" on cpuTotal Ready');
    assert.match(SOURCE, /"swap":\s*swapSensor\.status\s*===\s*Sensors\.Sensor\.Ready/, 'availableMetrics map must gate "swap" on swapSensor Ready');
    assert.match(SOURCE, /"disk":\s*diskSensor\.status\s*===\s*Sensors\.Sensor\.Ready/, 'availableMetrics map must gate "disk" on diskSensor Ready');
    assert.match(
        SOURCE,
        /"sensorTemp":\s*backend\.sensorTempResolved/,
        'availableMetrics map must gate "sensorTemp" on backend.sensorTempResolved (configured id + sensorTempSensor Ready)'
    );
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

test("MetricsBackend forwards the CPU process tooltip to ProcessSampler (#69)", () => {
    // The ProcessDataModel enumeration lives in the ProcessSampler child so
    // this adapter stays under the 500-line cap; the backend just forwards the
    // same-surface bits (mirrors the standalone adapter's split).
    assert.match(SOURCE, /ProcessSampler\s*{/, "must instantiate the ProcessSampler child");
    assert.match(SOURCE, /property\s+alias\s+processSamplingActive\s*:\s*processSampler\.active/, "processSamplingActive must alias the sampler's active gate");
    assert.match(SOURCE, /topProcesses\s*:\s*processSampler\.topProcesses/, "topProcesses must forward the sampler's ranked list (a property, for binding reactivity)");
    assert.match(SOURCE, /loadAverages\s*:\s*processSampler\.loadAverages/, "loadAverages must forward the sampler's value");
    // ksysguard "usage" is per-core → the sampler must be told the core count
    // so it can divide to the chosen "total 0-100%" semantics.
    assert.match(SOURCE, /coreCount:\s*backend\.coreValues\.length/, "must pass coreCount (coreValues.length) so the sampler can normalise per-core usage to total");
});

test("MetricsBackend forwards the RAM tooltip surface from ProcessSampler (#70)", () => {
    // topMemProcesses / memUsedKb / memTotalKb are properties (not functions)
    // so UI bindings track them — frozen-binding trap documented in the repo:
    // a function call breaks reactivity because QML only tracks property reads.
    assert.match(SOURCE, /topMemProcesses\s*:\s*processSampler\.topMemProcesses/, "topMemProcesses must forward the sampler's memory-ranked list as a reactive property");
    assert.match(SOURCE, /memUsedKb\s*:\s*processSampler\.memUsedKb/, "memUsedKb must forward the sampler's value as a reactive property");
    assert.match(SOURCE, /memTotalKb\s*:\s*processSampler\.memTotalKb/, "memTotalKb must forward the sampler's value as a reactive property");
});

// ── GPU tooltip detail (issue #71) ──────────────────────────────────

const GPU_DETAIL_SOURCE = readFileSync(join(__dirname, "..", "contents", "ui", "platforms", "plasma", "GpuDetailSensors.qml"), "utf8");

test("MetricsBackend declares gpuDetailSamplingActive gate and gpuDetail property (#71)", () => {
    // gpuDetailSamplingActive gates the GpuDetailSensors subscription — the
    // daemon must not push detail leaves when no tooltip is shown.
    // gpuDetail is a readonly property var (not a function) so view bindings stay live.
    assert.match(SOURCE, /property\s+bool\s+gpuDetailSamplingActive\s*:/, "must declare property bool gpuDetailSamplingActive");
    assert.match(SOURCE, /readonly\s+property\s+var\s+gpuDetail\b/, "must declare readonly property var gpuDetail");
});

test("MetricsBackend instantiates GpuDetailSensors and wires gpuDeviceIds + active gate (#71)", () => {
    assert.match(SOURCE, /GpuDetailSensors\s*{/, "must instantiate the GpuDetailSensors child");
    assert.match(SOURCE, /gpuDeviceIds:\s*backend\._gpuDeviceIds/, "GpuDetailSensors.gpuDeviceIds must be driven by backend._gpuDeviceIds");
    assert.match(SOURCE, /active:\s*backend\.gpuDetailSamplingActive/, "GpuDetailSensors.active must be the gpuDetailSamplingActive gate");
});

test("MetricsBackend assigns _gpuDeviceIds from classifyDiscoveredIds in _refreshDiscovery (#71)", () => {
    assert.match(SOURCE, /property\s+var\s+_gpuDeviceIds\s*:/, "must declare property var _gpuDeviceIds");
    assert.match(SOURCE, /_gpuDeviceIds\s*=\s*classified\.gpuDeviceIds/, "_refreshDiscovery must update _gpuDeviceIds from the classified bucket");
});

test("GpuDetailSensors subscribes the aggregate VRAM sensors and gates them with active (#71)", () => {
    assert.match(GPU_DETAIL_SOURCE, /"gpu\/all\/usedVram"/, "must subscribe gpu/all/usedVram");
    assert.match(GPU_DETAIL_SOURCE, /"gpu\/all\/totalVram"/, "must subscribe gpu/all/totalVram");
    // Both must be gated: the daemon must not push detail leaves in the background.
    const enabledCount = (GPU_DETAIL_SOURCE.match(/enabled:\s*gpuDetail\.active/g) || []).length;
    assert.ok(enabledCount >= 2, `at least 2 sensors must carry enabled: gpuDetail.active (found ${enabledCount})`);
});

test("GpuDetailSensors builds per-device name/power/coreFrequency sensorIds from the Instantiator (#71)", () => {
    assert.match(GPU_DETAIL_SOURCE, /Instantiator\s*{[\s\S]*?id:\s*deviceInst/, "must declare Instantiator { id: deviceInst }");
    assert.match(GPU_DETAIL_SOURCE, /sensorId:\s*modelData\s*\+\s*["']\/name["']/, "must build name sensorId from modelData");
    assert.match(GPU_DETAIL_SOURCE, /sensorId:\s*modelData\s*\+\s*["']\/power["']/, "must build power sensorId from modelData");
    assert.match(GPU_DETAIL_SOURCE, /sensorId:\s*modelData\s*\+\s*["']\/coreFrequency["']/, "must build coreFrequency sensorId from modelData");
});

test("GpuDetailSensors uses _tick to drive reactive re-evaluation (#71)", () => {
    assert.match(GPU_DETAIL_SOURCE, /property\s+int\s+_tick\s*:/, "must declare property int _tick");
    assert.match(GPU_DETAIL_SOURCE, /onValueChanged:\s*gpuDetail\._tick\+\+/, "sensors must bump _tick onValueChanged");
    assert.match(GPU_DETAIL_SOURCE, /onObjectAdded:\s*gpuDetail\._tick\+\+/, "Instantiator must bump _tick onObjectAdded");
    assert.match(GPU_DETAIL_SOURCE, /onObjectRemoved:\s*gpuDetail\._tick\+\+/, "Instantiator must bump _tick onObjectRemoved");
});

test("GpuDetailSensors detail property reads _tick as a reactive dependency (#71)", () => {
    // Reading _tick as the first expression in the binding makes every field a
    // tracked dependency so the binding re-evaluates whenever any sensor value changes.
    assert.match(GPU_DETAIL_SOURCE, /readonly\s+property\s+var\s+detail\s*:\s*\{[\s\S]{0,50}gpuDetail\._tick/, "detail property must read _tick as its first reactive dependency");
});

test("Plasma MetricsBackend exposes gpuProcesses as readonly property var [] (#71)", () => {
    // Plasma has no per-process VRAM source — the empty-list property keeps the
    // cross-platform surface uniform so the view doesn't branch on the host.
    // Property (not function) so view bindings stay live.
    assert.match(SOURCE, /readonly\s+property\s+var\s+gpuProcesses\b/, "must declare readonly property var gpuProcesses");
    assert.match(SOURCE, /readonly\s+property\s+var\s+gpuProcesses\s*:\s*\[\s*\]/, "gpuProcesses must be an empty array literal");
});

// ── Custom temperature sensor picker (issue #164) ───────────────────

test("MetricsBackend exposes the always-live sensorTemp resolution surface (#164)", () => {
    // The ring and the config editor's validation line both read these —
    // they must NOT be gated by tempSensorDiscoveryActive.
    assert.match(SOURCE, /readonly\s+property\s+bool\s+sensorTempResolved\s*:/, "must declare readonly property bool sensorTempResolved");
    assert.match(
        SOURCE,
        /sensorTempResolved:\s*backend\.sensorTempId\.length\s*>\s*0\s*&&\s*sensorTempSensor\.status\s*===\s*Sensors\.Sensor\.Ready/,
        "sensorTempResolved must be: configured id AND sensorTempSensor Ready",
    );
    assert.match(SOURCE, /readonly\s+property\s+real\s+sensorTempValue\s*:/, "must declare readonly property real sensorTempValue");
    assert.match(SOURCE, /sensorTempValue:[\s\S]{0,120}sensorTempSensor\.value/, "sensorTempValue must read sensorTempSensor.value");
});

test("MetricsBackend gates Celsius-sensor discovery behind tempSensorDiscoveryActive (#164)", () => {
    // The picker list lives in the TempSensorDiscovery child (500-line
    // cap, same split as DiskIoSampler); the gate is an alias to the
    // child's `active`, exactly like diskIoSamplingActive — only the
    // config dialog turns it on, so the panel widget probes nothing.
    assert.match(SOURCE, /property\s+alias\s+tempSensorDiscoveryActive\s*:\s*tempSensorDiscovery\.active/, "tempSensorDiscoveryActive must alias the discovery child's active gate");
    assert.match(SOURCE, /readonly\s+property\s+var\s+tempSensors\s*:\s*tempSensorDiscovery\.sensors/, "tempSensors must forward the discovery adapter's list");
    assert.match(SOURCE, /TempSensorDiscovery\s*{[\s\S]*?id:\s*tempSensorDiscovery/, "must instantiate the TempSensorDiscovery child");
});

const TEMP_DISCOVERY_SOURCE = readFileSync(join(__dirname, "..", "contents", "ui", "platforms", "plasma", "TempSensorDiscovery.qml"), "utf8");

test("TempSensorDiscovery implements the two-phase discovery via the pure catalog (#164)", () => {
    // Phase 1: walk the SensorTreeModel and pre-filter leaves through
    // TempSensorCatalog.isTempCandidate (DisplayRole "… (°C)").
    assert.match(TEMP_DISCOVERY_SOURCE, /Sensors\.SensorTreeModel\s*{[\s\S]*?id:\s*sensorTree/, "must declare its own SensorTreeModel");
    assert.match(TEMP_DISCOVERY_SOURCE, /TempSensorCatalog\.isTempCandidate\s*\(/, "phase 1 must defer the candidate check to the pure catalog");
    assert.match(TEMP_DISCOVERY_SOURCE, /Sensors\.SensorTreeModel\.SensorId/, "the walk must read the SensorId role");
    // Phase 2: an Instantiator of live Sensors.Sensor probes the
    // candidates; buildTempSensorEntries keeps Celsius + Ready and
    // shapes the [{id, label}] list.
    assert.match(TEMP_DISCOVERY_SOURCE, /Instantiator\s*{[\s\S]*?model:\s*discovery\._candidateIds/, "phase 2 must be an Instantiator over the candidate ids");
    assert.match(TEMP_DISCOVERY_SOURCE, /TempSensorCatalog\.buildTempSensorEntries\s*\(/, "phase 2 must build the picker entries via the pure catalog");
    // Gated: no candidates (hence no Sensor subscriptions) while inactive.
    assert.match(TEMP_DISCOVERY_SOURCE, /if\s*\(\s*!discovery\.active\s*\)/, "the walk must bail out while the gate is off");
    assert.match(TEMP_DISCOVERY_SOURCE, /enabled:\s*discovery\.active/, "probe Sensors must be enabled only while the gate is on");
});

// ── Battery (BatterySampler) ─────────────────────────────────────────

const BATTERY_SOURCE = readFileSync(join(__dirname, "..", "contents", "ui", "platforms", "plasma", "BatterySampler.qml"), "utf8");

test("MetricsBackend instantiates BatterySampler and exposes battery accessor", () => {
    // BatterySampler owns the discovery + aggregation so MetricsBackend stays
    // under the 500-line cap; the backend forwards the reactive property.
    assert.match(SOURCE, /BatterySampler\s*{/, "must instantiate BatterySampler");
    assert.match(SOURCE, /id:\s*batterySampler\b/, "BatterySampler must have id: batterySampler");
    assert.match(SOURCE, /readonly\s+property\s+var\s+battery\s*:\s*batterySampler\.battery/, "battery must forward batterySampler.battery as a reactive property");
});

test('availableMetrics flags "battery" via batterySampler.battery.available', () => {
    // battery availability is derived from BatteryAggregate.aggregate —
    // false on a host with no battery sensors, so the ring is not shown.
    assert.match(SOURCE, /"battery":\s*batterySampler\.battery\.available/, 'availableMetrics map must gate "battery" on batterySampler.battery.available');
});

test("BatterySampler discovers batteries by walking the SensorTreeModel for chargePercentage leaves", () => {
    // ksysguard has no aggregate power/all/chargePercentage — each physical
    // battery appears as power/<id>/chargePercentage where <id> is the serial
    // or UDI tail. The sampler must enumerate the tree, not hardcode an id.
    assert.match(BATTERY_SOURCE, /SensorTreeModel\s*{[\s\S]*?id:\s*batteryTree/, "must declare SensorTreeModel { id: batteryTree }");
    assert.match(BATTERY_SOURCE, /chargePercentage/, "must search for chargePercentage leaves");
    assert.match(BATTERY_SOURCE, /function\s+_refresh\s*\(/, "must declare _refresh() discovery function");
});

test("BatterySampler uses Instantiators for per-battery percent and rate sensors", () => {
    assert.match(BATTERY_SOURCE, /Instantiator\s*{[\s\S]*?id:\s*percentInst/, "must declare Instantiator { id: percentInst }");
    assert.match(BATTERY_SOURCE, /Instantiator\s*{[\s\S]*?id:\s*rateInst/, "must declare Instantiator { id: rateInst }");
    assert.match(BATTERY_SOURCE, /sensorId:\s*modelData\s*\+\s*["']\/chargePercentage["']/, "percentInst must build sensorId from modelData + '/chargePercentage'");
    assert.match(BATTERY_SOURCE, /sensorId:\s*modelData\s*\+\s*["']\/chargeRate["']/, "rateInst must build sensorId from modelData + '/chargeRate'");
});

test("BatterySampler uses _tick to drive reactive battery re-evaluation", () => {
    assert.match(BATTERY_SOURCE, /property\s+int\s+_tick\s*:/, "must declare property int _tick");
    assert.match(BATTERY_SOURCE, /onValueChanged:\s*sampler\._tick\+\+/, "sensors must bump _tick onValueChanged");
    assert.match(BATTERY_SOURCE, /onObjectAdded:\s*sampler\._tick\+\+/, "Instantiator must bump _tick onObjectAdded");
    assert.match(BATTERY_SOURCE, /onObjectRemoved:\s*sampler\._tick\+\+/, "Instantiator must bump _tick onObjectRemoved");
});

test("BatterySampler battery property reads _tick as its first reactive dependency", () => {
    // Reading _tick first makes every field a tracked dependency so the binding
    // re-evaluates whenever any sensor value changes (standard tick-counter pattern).
    assert.match(BATTERY_SOURCE, /readonly\s+property\s+var\s+battery\s*:\s*\{[\s\S]{0,50}sampler\._tick/, "battery property must read _tick as its first reactive dependency");
});

test("BatterySampler imports BatteryAggregate and calls aggregate()", () => {
    assert.match(BATTERY_SOURCE, /import\s+["']\.\.\/\.\.\/core\/BatteryAggregate\.js["']\s+as\s+BatteryAggregate/, "must import core/BatteryAggregate.js with the correct relative path");
    assert.match(BATTERY_SOURCE, /BatteryAggregate\.aggregate\s*\(/, "battery binding must call BatteryAggregate.aggregate(records)");
});

test("BatterySampler treats a non-discharging battery (rate >= 0) as charging", () => {
    // SCENARIO: a laptop plugged in at 100% reports chargeRate == 0 (full, no
    // current). ksysguard exposes no charge-state enum and no AC-online sensor,
    // so charging is inferred from the signed rate. A `> 0` test would dim a
    // full-plugged battery, diverging from the standalone adapter (status="Full"
    // → charging). The threshold must be `>= 0` (not actively discharging).
    assert.match(BATTERY_SOURCE, /rate\.value\s*>=\s*0/, "charging must be inferred from rate.value >= 0");
    assert.doesNotMatch(BATTERY_SOURCE, /rate\.value\s*>\s*0/, "must not use rate.value > 0 (dims a full-plugged battery)");
});

test("BatterySampler re-runs discovery on batteryTree structural changes", () => {
    assert.match(BATTERY_SOURCE, /Connections\s*{[\s\S]*?target:\s*batteryTree[\s\S]*?onRowsInserted/, "must reconnect on batteryTree.onRowsInserted");
    assert.match(BATTERY_SOURCE, /Connections\s*{[\s\S]*?target:\s*batteryTree[\s\S]*?onRowsRemoved/, "must reconnect on batteryTree.onRowsRemoved");
});
