import QtQuick
import QtQml.Models
import org.kde.ksysguard.sensors as Sensors
import "../../core/MetricsCatalog.js" as Catalog
import "../../core/DiskMetrics.js" as DiskMetrics
import "SensorPicking.js" as SensorPicking
import "MountInfo.js" as MountInfoJs

// Platform adapter: wraps the KSysGuard sensor system used by the
// Plasma build. Exposes the metric values main.qml needs as a stable
// surface — the internal sensor instances + sensorMap are
// implementation details, not part of the public API.
//
// Public surface:
//   readonly property var coreValues  - per-core CPU usage (length = nCores
//                                       discovered at runtime via SensorTreeModel)
//   readonly property bool loading    - true while critical aggregates are
//                                       not yet Sensor.Ready. MainContent
//                                       force-fills the rings to 100% during
//                                       this window for a "warming up"
//                                       visual signal.
//   function metricValue(id)          - latest value for one of the
//                                       Catalog metric ids
//   function metricRawTemp(id)        - latest raw °C reading for ids
//                                       that expose a temperature sensor
//                                       (cpu, gpu); 0 for others
//   function metricTempPercent(id)    - same value mapped to 0-100 via
//                                       Catalog.tempToPercent
//
// Universal aggregates (cpu/all/usage, memory/*, disk/all/usedPercent,
// cpu/all/averageTemperature) have stable single ids and stay bound
// directly. Multi-arity sensors (cpu/cpu*/usage, gpu/gpu*/temperature,
// gpu/gpu*/usage) are discovered at runtime via SensorTreeModel —
// fixes the dev-machine assumption of 6 cores + a discrete GPU on
// gpu1, which broke on other hardware. The standalone build ships a
// parallel MetricsBackend.qml exposing the same public surface.

Item {
    id: backend

    property string sensorTempId: ""
    // ── Public surface ──────────────────────────────────────────────
    //
    // coreValues re-evaluates on _coreTick — bumped on Instantiator
    // adds/removes and on any per-core Sensor's value change — so it
    // scales to any core count without code changes.
    property int _coreTick: 0
    readonly property var coreValues: {
        backend._coreTick;
        var out = [];
        for (var i = 0; i < coreInstantiator.count; i++) {
            var s = coreInstantiator.objectAt(i);
            if (s)
                out.push(s.value || 0);
        }
        return out;
    }

    readonly property bool loading: cpuTotal.status !== Sensors.Sensor.Ready || ramSensor.status !== Sensors.Sensor.Ready

    // Catalog ids whose Sensor has reached Ready (docs/components.md § MetricsBackend).
    readonly property var availableMetrics: {
        // Read the gpu ticks first so the binding re-evaluates when a per-GPU
        // Instantiator's status changes — the readiness helpers walk those
        // instances, which QML can't track otherwise. The universal sensors'
        // .status reads below are tracked directly (Sensor.status has NOTIFY).
        backend._gpuUsageTick;
        backend._gpuTempTick;
        return Catalog.availableMetricsFrom({
            "cpu": cpuTotal.status === Sensors.Sensor.Ready,
            "cpuTemp": cpuTempSensor.status === Sensors.Sensor.Ready,
            "ram": ramSensor.status === Sensors.Sensor.Ready,
            "swap": swapSensor.status === Sensors.Sensor.Ready,
            "gpu": backend._gpuUsageReady(),
            "gpuTemp": backend._gpuTempReady(),
            "disk": diskSensor.status === Sensors.Sensor.Ready,
            // ksysguard exposes disk/all/{read,write} on any host with a disk
            // (no-op until the diskIo UI PR adds the catalog id — filtered to
            // METRIC_IDS).
            "diskIo": true,
            "sensorTemp": backend.sensorTempResolved
        });
    }

    // GPU readiness mirrors the value helpers: usage is ready when the
    // aggregate OR any per-GPU usage Sensor is Ready; temperature likewise.
    function _gpuUsageReady() {
        if (gpuAllSensor.status === Sensors.Sensor.Ready)
            return true;
        for (var i = 0; i < gpuUsageInstantiator.count; i++) {
            var s = gpuUsageInstantiator.objectAt(i);
            if (s && s.status === Sensors.Sensor.Ready)
                return true;
        }
        return false;
    }

    function _gpuTempReady() {
        for (var i = 0; i < gpuTempInstantiator.count; i++) {
            var s = gpuTempInstantiator.objectAt(i);
            if (s && s.status === Sensors.Sensor.Ready)
                return true;
        }
        return false;
    }

    function metricValue(id) {
        if (id === "gpu")
            return backend._gpuUsageValue;
        if (id === "gpuTemp")
            return backend._gpuTempValue;
        return Catalog.valueFromSensorMap(sensorMap, id);
    }

    function metricRawTemp(id) {
        if (id === "gpu")
            return backend._gpuTempValue;
        return Catalog.valueFromSensorMap(tempSensorMap, id);
    }

    function metricTempPercent(id) {
        return Catalog.tempToPercent(metricRawTemp(id));
    }

    // ── GPU tooltip detail (issue #71) ──────────────────────────────
    // Tooltip-only sensors live in GpuDetailSensors (gated by active) so
    // the daemon doesn't push them in the background. Usage/temp come from
    // the always-on ring sensors; gpuDetail merges both sources.
    property bool gpuDetailSamplingActive: false

    GpuDetailSensors {
        id: gpuDetailSensors
        gpuDeviceIds: backend._gpuDeviceIds
        active: backend.gpuDetailSamplingActive
    }

    // Reactive properties (not functions) so view bindings stay live (core/CLAUDE.md
    // § "Reactive argless data"): the PROPERTY gpuDetailSensors.detail + the reactive
    // _gpuUsageValue / _gpuTempValue all NOTIFY, so this binding re-evaluates.
    readonly property var gpuDetail: {
        var extra = gpuDetailSensors.detail;
        var usage = backend._gpuUsageReady() ? backend._gpuUsageValue : undefined;
        var temp = backend._gpuTempReady() ? backend._gpuTempValue : undefined;
        return {
            "model": extra.model,
            "usagePercent": usage,
            "vramUsedBytes": extra.vramUsedBytes,
            "vramTotalBytes": extra.vramTotalBytes,
            "tempC": temp,
            "powerW": extra.powerW,
            "clockMhz": extra.clockMhz
        };
    }

    // Plasma has no per-process VRAM source — empty list keeps the surface uniform.
    readonly property var gpuProcesses: []

    // ── CPU + RAM process tooltips (issues #69/#70) ──────────────────
    // Same surface as the standalone adapter; the ProcessDataModel enumeration
    // lives in the ProcessSampler child (running only while active) so this
    // adapter stays under the 500-line cap. topProcesses / topMemProcesses are
    // properties (not functions) so UI bindings track them and tooltip lists
    // refresh live.
    property alias processSamplingActive: processSampler.active
    readonly property var topProcesses: processSampler.topProcesses
    readonly property var topMemProcesses: processSampler.topMemProcesses
    readonly property var loadAverages: processSampler.loadAverages
    readonly property real memUsedKb: processSampler.memUsedKb
    readonly property real memTotalKb: processSampler.memTotalKb

    ProcessSampler {
        id: processSampler
        // ksysguard "usage" is per-core; the sampler divides by this to hit the
        // "total 0-100%" tooltip semantics. coreValues.length = discovered cores.
        coreCount: backend.coreValues.length
    }

    // ── Disk I/O throughput ring (issue #77) ─────────────────────────
    // Same surface as the standalone adapter; the disk/all/{read,write} sensor
    // reads live in the DiskIoSampler child (subscribed only while active) so
    // this adapter stays under the 500-line cap. `io` is a property (reactive)
    // carrying per-component byte/s + arc %; the gate keeps the daemon
    // unsubscribed while the ring is off-screen.
    property alias diskIoSamplingActive: diskIoSampler.active
    readonly property var diskIo: diskIoSampler.io

    DiskIoSampler {
        id: diskIoSampler
    }

    // ── Custom temperature sensor picker (issue #164) ────────────────
    // Resolved/value are always live (the sensorTemp ring reads them);
    // the picker list is gated — only the config dialog turns discovery
    // on (the gate pattern matches diskIoSamplingActive above; the
    // two-phase discovery itself is documented in TempSensorDiscovery).
    readonly property bool sensorTempResolved: backend.sensorTempId.length > 0 && sensorTempSensor.status === Sensors.Sensor.Ready
    readonly property real sensorTempValue: backend.sensorTempResolved && isFinite(sensorTempSensor.value) ? sensorTempSensor.value : NaN
    property alias tempSensorDiscoveryActive: tempSensorDiscovery.active
    readonly property var tempSensors: tempSensorDiscovery.sensors

    TempSensorDiscovery {
        id: tempSensorDiscovery
    }

    // ── Disk partitions (multi-ring) ─────────────────────────────────
    //
    // Discovery + labels come from the shared DiskPartitions adapter (also
    // used by the config dialog). defaultPartitionIds is empty on Plasma:
    // when the user has selected nothing, the disk ring stays the aggregate
    // disk/all gauge (MainContent's aggregate fallback) — ksysguard exposes
    // no mountpoint, so a "$HOME partition" default isn't computable here.
    readonly property var availablePartitions: diskPartitions.partitions.map(function (p) {
        return {
            "id": p.id,
            "label": p.label
        };
    })
    // availablePartitions intersected with the live mount set. ksysguard's
    // SensorTreeModel freezes on unmount (#58) and keeps listing a
    // just-unplugged filesystem, so the raw availablePartitions would offer a
    // dead partition as a selectable picker checkbox. Gating on the live
    // findmnt set (mountedPartitionIds) drops it; and since the config picker
    // feeds this SAME list to DiskMetrics.stalePartitions, a still-configured
    // unmounted partition then shows as a greyed stale row instead. Empty
    // mountedPartitionIds (poll not yet returned, or tracking off) → passthrough
    // (no gating during warm-up). Consumed by configMetrics.qml, which turns
    // removableTrackingActive on so the findmnt poll runs while the dialog is open.
    readonly property var mountedAvailablePartitions: DiskMetrics.filterToMounted(backend.availablePartitions, backend.mountedPartitionIds)
    // False until DiskPartitions' incremental tree walk has settled — the
    // config picker gates its destructive stale-row removal on this.
    readonly property bool partitionsReady: diskPartitions.ready
    readonly property var defaultPartitionIds: []

    // Live mounted-removable set (USB keys, SD cards), [{id, label}] keyed by
    // UUID — the data ksysguard can't give us (no mountpoint / removable flag)
    // and which freezes on unmount (#58). MainContent unions it with the manual
    // selection via DiskMetrics.resolveDiskRingIds, so a plugged key auto-shows a
    // ring and an unplugged one self-heals away with no trip through Settings.
    // The per-ring VALUE still comes from partitionValue(id): while a removable
    // is mounted ksysguard does expose its disk/<uuid>/usedPercent sensor (only
    // the set/unmount detection froze, which MountInfo sidesteps).
    readonly property var removablePartitions: MountInfoJs.removableList(mountInfo.mounted)
    // Every currently-mounted UUID (fixed + removable) per the live findmnt poll
    // — the authoritative "is this still mounted?" set MainContent gates the disk
    // ring on, so a stale partition (unplugged removable) loses its ring even
    // when it lingers in ksysguard's frozen tree (#58). Empty until the first
    // poll returns; MainContent treats empty as "no data, don't gate".
    readonly property var mountedPartitionIds: MountInfoJs.uuidList(mountInfo.mounted)
    // Gate for MountInfo's findmnt poll — main.qml sets it true whenever the disk
    // metric is enabled, so a widget without a disk ring spawns no subprocess
    // (#59 review finding 1). It is intentionally NOT also gated on
    // Plasmoid.expanded — see main.qml for why (that would break the inline
    // desktop auto-show, where `expanded` is a popup signal and isn't reliably true).
    property bool removableTrackingActive: false

    // Gate for the per-partition total/free byte sensors — set true by MainContent
    // while the disk tooltip is hovered, so the daemon isn't pushing them when no
    // tooltip is up (#68). Forwarded into the DiskPartitionSensors adapter.
    property alias diskTooltipActive: diskSensors.tooltipActive

    // Per-partition Sensor instances (usedPercent + total/free bytes) live in
    // the DiskPartitionSensors adapter below; partitionValue / partitionDetail
    // forward to it so MainContent still sees one `metrics` object.
    function partitionValue(id) {
        return diskSensors.partitionValue(id);
    }
    // Full per-partition detail for the disk-ring tooltip (#68): joins the
    // ksysguard usedPercent + total/free bytes with the findmnt mountpoint /
    // fstype / removable. Same shape as the standalone adapter.
    function partitionDetail(id) {
        return diskSensors.partitionDetail(id);
    }

    // ── Internal — id → Sensor instance lookup (universal aggregates) ──
    readonly property var sensorMap: ({
            cpu: cpuTotal,
            ram: ramSensor,
            swap: swapSensor,
            disk: diskSensor,
            cpuTemp: cpuTempSensor,
            sensorTemp: sensorTempSensor
        })

    readonly property var tempSensorMap: ({
            cpu: cpuTempSensor,
            sensorTemp: sensorTempSensor
        })

    // ── Internal — universal per-metric sensors ─────────────────────
    Sensors.Sensor {
        id: cpuTotal
        sensorId: Catalog.sensorIdFor("cpu")
    }
    Sensors.Sensor {
        id: ramSensor
        sensorId: Catalog.sensorIdFor("ram")
    }
    Sensors.Sensor {
        id: swapSensor
        sensorId: Catalog.sensorIdFor("swap")
    }
    Sensors.Sensor {
        id: diskSensor
        sensorId: Catalog.sensorIdFor("disk")
    }
    Sensors.Sensor {
        id: cpuTempSensor
        sensorId: Catalog.tempSensorIdFor("cpu")
    }

    Sensors.Sensor {
        id: sensorTempSensor
        sensorId: backend.sensorTempId
    }
    // Preferred aggregate for GPU usage. May not exist on systems with a
    // single discrete GPU exposed only at gpu/gpu0/usage — _gpuUsageValue
    // falls back to the first Ready per-gpu candidate in that case.
    Sensors.Sensor {
        id: gpuAllSensor
        sensorId: "gpu/all/usage"
    }

    // ── SensorTreeModel-driven discovery (multi-arity sensors) ──────
    //
    // The tree walks every subsystem at startup and again on every
    // structural change (rowsInserted/Removed/modelReset) so a sensor
    // appearing late — say a USB GPU hot-plug — is picked up without
    // a widget reload.
    Sensors.SensorTreeModel {
        id: sensorTree
    }

    property var _coreUsageIds: []
    property var _gpuTempIds: []
    property var _gpuUsageIds: []
    property var _gpuDeviceIds: []

    function _walkTreeAndCollectIds() {
        var out = [];
        function visit(parent) {
            var rc;
            if (parent === undefined) {
                rc = sensorTree.rowCount();
            } else {
                rc = sensorTree.rowCount(parent);
            }
            for (var i = 0; i < rc; i++) {
                var idx = (parent === undefined) ? sensorTree.index(i, 0) : sensorTree.index(i, 0, parent);
                var id = sensorTree.data(idx, Sensors.SensorTreeModel.SensorId);
                if (id)
                    out.push(id);
                visit(idx);
            }
        }
        visit(undefined);
        return out;
    }

    function _refreshDiscovery() {
        var classified = Catalog.classifyDiscoveredIds(_walkTreeAndCollectIds());
        // Guard against spurious Instantiator rebuilds: rowsInserted fires for
        // unrelated tree sections, so skip the assignment when nothing changed.
        if (JSON.stringify(_coreUsageIds) !== JSON.stringify(classified.coreUsageIds))
            _coreUsageIds = classified.coreUsageIds;
        if (JSON.stringify(_gpuTempIds) !== JSON.stringify(classified.gpuTempIds))
            _gpuTempIds = classified.gpuTempIds;
        if (JSON.stringify(_gpuUsageIds) !== JSON.stringify(classified.gpuUsageIds))
            _gpuUsageIds = classified.gpuUsageIds;
        if (JSON.stringify(_gpuDeviceIds) !== JSON.stringify(classified.gpuDeviceIds))
            _gpuDeviceIds = classified.gpuDeviceIds;
    }

    Component.onCompleted: _refreshDiscovery()
    Connections {
        target: sensorTree
        function onRowsInserted() {
            backend._refreshDiscovery();
        }
        function onRowsRemoved() {
            backend._refreshDiscovery();
        }
        function onModelReset() {
            backend._refreshDiscovery();
        }
    }

    // ── Dynamic Sensor instances driven by discovery ────────────────
    Instantiator {
        id: coreInstantiator
        model: backend._coreUsageIds
        delegate: Sensors.Sensor {
            required property string modelData
            sensorId: modelData
            // _coreTick bumps drive coreValues re-evaluation. The
            // Behavior on Ring.displayValue (400ms OutCubic) smooths
            // the ring sweep, so even a 1 Hz ksysguard tick reads
            // continuous.
            onValueChanged: backend._coreTick++
        }
        // Adds/removes also trigger the recompute so the array shrinks
        // / grows in lockstep with discovery.
        onObjectAdded: backend._coreTick++
        onObjectRemoved: backend._coreTick++
    }

    property int _gpuTempTick: 0
    readonly property real _gpuTempValue: {
        backend._gpuTempTick;
        var candidates = [];
        for (var i = 0; i < gpuTempInstantiator.count; i++) {
            var s = gpuTempInstantiator.objectAt(i);
            if (s)
                candidates.push({
                    "ready": s.status === Sensors.Sensor.Ready,
                    "value": s.value
                });
        }
        return SensorPicking.pickFirstReadyValue(candidates);
    }
    Instantiator {
        id: gpuTempInstantiator
        model: backend._gpuTempIds
        delegate: Sensors.Sensor {
            required property string modelData
            sensorId: modelData
            onValueChanged: backend._gpuTempTick++
            onStatusChanged: backend._gpuTempTick++
        }
        onObjectAdded: backend._gpuTempTick++
        onObjectRemoved: backend._gpuTempTick++
    }

    property int _gpuUsageTick: 0
    readonly property real _gpuUsageValue: {
        backend._gpuUsageTick;
        // Aggregate first — when ksysguard exposes it we trust it.
        // pickFirstReadyValue short-circuits on the first ready candidate
        // (returns `value || 0`), so a transient Ready+undefined sensor yields 0
        // rather than falling through to the per-device list — by design.
        // Locked in by tests/sensor-picking.test.mjs "ready candidate with null
        // value wins and yields 0".
        var candidates = [
            {
                "ready": gpuAllSensor.status === Sensors.Sensor.Ready,
                "value": gpuAllSensor.value
            }
        ];
        for (var i = 0; i < gpuUsageInstantiator.count; i++) {
            var s = gpuUsageInstantiator.objectAt(i);
            if (s)
                candidates.push({
                    "ready": s.status === Sensors.Sensor.Ready,
                    "value": s.value
                });
        }
        return SensorPicking.pickFirstReadyValue(candidates);
    }
    Connections {
        target: gpuAllSensor
        function onValueChanged() {
            backend._gpuUsageTick++;
        }
        function onStatusChanged() {
            backend._gpuUsageTick++;
        }
    }
    Instantiator {
        id: gpuUsageInstantiator
        model: backend._gpuUsageIds
        delegate: Sensors.Sensor {
            required property string modelData
            sensorId: modelData
            onValueChanged: backend._gpuUsageTick++
            onStatusChanged: backend._gpuUsageTick++
        }
        onObjectAdded: backend._gpuUsageTick++
        onObjectRemoved: backend._gpuUsageTick++
    }

    // ── Disk partitions ──────────────────────────────────────────────
    // Discovery (UUID + volume label per mounted filesystem) is shared with
    // the config dialog via this adapter; here it also drives a live Sensor
    // per partition so partitionValue(id) reads the current usedPercent.
    DiskPartitions {
        id: diskPartitions
    }

    // Live mounted/removable set (findmnt via plasma5support) — drives
    // removablePartitions above. Polls only while removableTrackingActive.
    MountInfo {
        id: mountInfo
        active: backend.removableTrackingActive
    }

    DiskPartitionSensors {
        id: diskSensors
        partitions: diskPartitions.partitions
        mounted: mountInfo.mounted
    }
}
