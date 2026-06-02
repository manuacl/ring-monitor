import QtQuick
import org.kde.ksysguard.sensors as Sensors
import "../../core/DiskMetrics.js" as DiskMetrics

// Plasma per-partition disk sensors, split out of MetricsBackend (the 500-line
// cap + the move from one to THREE ksysguard leaves per filesystem for the #68
// tooltip). Owns the dynamic Sensor instances (usedPercent for the ring value,
// total/free bytes for the tooltip figures) and the value reads. The discovery /
// label / mount surface (availablePartitions, removable, mounted set) stays in
// MetricsBackend; this consumes its outputs via the two input properties.
//
// Inputs:
//   partitions - [{id, label, sensorId}] from DiskPartitions (the Sensor model).
//   mounted    - [{uuid, label, mountpoint, fstype, removable}] from MountInfo
//                (findmnt) — the only source of mountpoint/fstype on Plasma.
// Surface (forwarded by MetricsBackend so MainContent sees one `metrics`):
//   partitionValue(id)  - the ring's usedPercent (ksysguard convention).
//   partitionDetail(id) - the #68 tooltip detail object (via the shared
//                         DiskMetrics.buildPartitionDetail assembler).

Item {
    id: diskSensors

    property var partitions: []
    property var mounted: []

    property int _tick: 0
    // Last-good usedPercent per id, held across Sensor rebuilds: a USB plug /
    // unplug recreates ALL delegates, which read 0 until their first ksysguard
    // sample — without this the rings (and the centre average) collapse to 0%
    // and recover. Keyed by the stable UUID, so it survives the rebuild.
    property var _lastValue: ({})

    Instantiator {
        id: inst
        model: diskSensors.partitions
        // Three ksysguard leaves per filesystem: usedPercent (the ring value) +
        // total / free bytes (the #68 tooltip figures). `enabled` stays default —
        // the daemon only pushes a subscribed sensor. TODO(#68 PR3): the
        // total/free leaves are only read on tooltip hover; once the tooltip
        // drives an `active` gate (like ProcessSampler), bind their `enabled` to
        // it so they're unsubscribed while no tooltip is shown. usedPercent stays
        // always-on (the ring needs it every tick).
        delegate: Item {
            required property var modelData
            readonly property string partId: modelData.id
            readonly property alias used: usedSensor
            readonly property alias total: totalSensor
            readonly property alias free: freeSensor
            Sensors.Sensor {
                id: usedSensor
                sensorId: modelData.sensorId
                onValueChanged: diskSensors._tick++
            }
            Sensors.Sensor {
                id: totalSensor
                sensorId: "disk/" + modelData.id + "/total"
                onValueChanged: diskSensors._tick++
            }
            Sensors.Sensor {
                id: freeSensor
                sensorId: "disk/" + modelData.id + "/free"
                onValueChanged: diskSensors._tick++
            }
        }
        onObjectAdded: diskSensors._tick++
        onObjectRemoved: diskSensors._tick++
    }

    // A ksysguard sensor's numeric value, or `fallback` when it hasn't resolved
    // (just-rebuilt, missing leaf, or daemon not reporting it yet).
    function _num(sensor, fallback) {
        if (sensor && sensor.status === Sensors.Sensor.Ready && typeof sensor.value === "number" && !isNaN(sensor.value))
            return sensor.value;
        return fallback;
    }

    function _delegateFor(id) {
        for (var i = 0; i < inst.count; i++) {
            var d = inst.objectAt(i);
            if (d && d.partId === id)
                return d;
        }
        return null;
    }

    // usedPercent from an already-resolved delegate (avoids a second
    // _delegateFor scan when partitionDetail already has it): the live sensor
    // value when Ready, else the last-good cache so a Sensor rebuild doesn't
    // blink the ring to 0%.
    function _usedPercent(d, id) {
        if (d) {
            var v = _num(d.used, NaN);
            if (!isNaN(v)) {
                diskSensors._lastValue[id] = v;
                return v;
            }
        }
        return diskSensors._lastValue[id] || 0;
    }

    function partitionValue(id) {
        diskSensors._tick;
        return _usedPercent(_delegateFor(id), id);
    }

    function partitionDetail(id) {
        diskSensors._tick;
        var label = id;
        var ps = diskSensors.partitions;
        for (var i = 0; i < ps.length; i++)
            if (ps[i].id === id) {
                label = ps[i].label;
                break;
            }
        var mountpoint = "";
        var fstype = "";
        var ms = diskSensors.mounted;
        for (var j = 0; j < ms.length; j++)
            if (ms[j].uuid === id) {
                mountpoint = ms[j].mountpoint;
                fstype = ms[j].fstype;
                break;
            }
        var d = _delegateFor(id);   // single scan: usedPercent + total + free
        var stats = {
            "usedPercent": _usedPercent(d, id),
            "totalBytes": d ? _num(d.total, 0) : 0,
            "freeBytes": d ? _num(d.free, 0) : 0
        };
        return DiskMetrics.buildPartitionDetail(id, {
            "label": label,
            "mountpoint": mountpoint,
            "fstype": fstype
        }, stats);
    }
}
