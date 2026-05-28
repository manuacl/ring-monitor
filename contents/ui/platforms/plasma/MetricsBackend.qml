import QtQuick
import QtQml.Models
import org.kde.ksysguard.sensors as Sensors
import "../../core/MetricsCatalog.js" as Catalog
import "SensorPicking.js" as SensorPicking

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
// gpu1, which broke on other hardware.
//
// A standalone build will ship a parallel MetricsBackend.qml backed by
// /proc reads or psutil, exposing the same public surface.

Item {
    id: backend

    // ── Public surface ──────────────────────────────────────────────
    //
    // coreValues re-evaluates on _coreTick — bumped whenever the
    // Instantiator gains/loses an item OR any per-core Sensor's value
    // changes. The function form (vs. a static list of `cpuN.value`)
    // is what lets it scale to any core count without code changes.
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
    readonly property var defaultPartitionIds: []

    // Last-good value per partition id, held across Sensor rebuilds. When the
    // partition set changes (USB plug/unplug) the Instantiator recreates ALL
    // disk Sensors, which read 0 until their first ksysguard sample — without
    // this cache the rings (and the centre average) would collapse to 0% and
    // recover. Keyed by the stable UUID, so it survives the rebuild.
    property var _lastPartValue: ({})

    function partitionValue(id) {
        backend._diskTick;
        for (var i = 0; i < diskPartInstantiator.count; i++) {
            var s = diskPartInstantiator.objectAt(i);
            if (s && s.partId === id) {
                if (s.status === Sensors.Sensor.Ready && typeof s.value === "number" && !isNaN(s.value)) {
                    backend._lastPartValue[id] = s.value;
                    return s.value;
                }
                // Sensor not Ready yet (e.g. just rebuilt) — hold last-good.
                return backend._lastPartValue[id] || 0;
            }
        }
        return backend._lastPartValue[id] || 0;
    }

    // ── Internal — id → Sensor instance lookup (universal aggregates) ──
    readonly property var sensorMap: ({
            cpu: cpuTotal,
            ram: ramSensor,
            swap: swapSensor,
            disk: diskSensor,
            cpuTemp: cpuTempSensor
        })

    readonly property var tempSensorMap: ({
            cpu: cpuTempSensor
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
    // Preferred aggregate for GPU usage. May not exist on systems with
    // a single discrete GPU exposed only at gpu/gpu0/usage — the
    // _gpuUsageValue helper falls back to the first Ready per-gpu
    // candidate in that case.
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
        // Avoid spurious Instantiator rebuilds when the set hasn't
        // actually changed (rowsInserted can fire for unrelated parts
        // of the tree).
        if (JSON.stringify(_coreUsageIds) !== JSON.stringify(classified.coreUsageIds))
            _coreUsageIds = classified.coreUsageIds;
        if (JSON.stringify(_gpuTempIds) !== JSON.stringify(classified.gpuTempIds))
            _gpuTempIds = classified.gpuTempIds;
        if (JSON.stringify(_gpuUsageIds) !== JSON.stringify(classified.gpuUsageIds))
            _gpuUsageIds = classified.gpuUsageIds;
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
        //
        // Semantics note since the `pickFirstReadyValue` refactor
        // (PR #25): the helper does NOT fall through to the next
        // candidate when a ready candidate has a falsy value — it
        // short-circuits via `return c.value || 0`, matching the
        // pre-refactor `gpuAllSensor.value || 0`. KSysGuard can
        // transiently report `status === Ready` with `value ===
        // undefined` during sensor discovery; both pre- and
        // post-refactor that yields `0` rather than the per-device
        // fallback. Locked in by the `tests/sensor-picking.test.mjs`
        // "ready candidate with null value wins and yields 0" case.
        // If we ever want true "try the next ready candidate"
        // semantics, that's a SensorPicking change (+ helper rename
        // to disambiguate from this short-circuit form), not a
        // local tweak.
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

    property int _diskTick: 0
    Instantiator {
        id: diskPartInstantiator
        model: diskPartitions.partitions
        delegate: Sensors.Sensor {
            required property var modelData
            readonly property string partId: modelData.id
            sensorId: modelData.sensorId
            onValueChanged: backend._diskTick++
        }
        onObjectAdded: backend._diskTick++
        onObjectRemoved: backend._diskTick++
    }
}
