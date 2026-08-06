import QtQuick
import QtQml.Models
import org.kde.ksysguard.sensors as Sensors
import "TempSensorCatalog.js" as TempSensorCatalog

// Celsius-sensor discovery behind the sensorTemp picker (issue #164).
// Split out of MetricsBackend.qml to keep that adapter under the
// 500-line cap (same pattern as DiskIoSampler / ProcessSampler). Gated
// by `active`: only the config dialog turns discovery on, so the panel
// widget never probes the sensor tree for the picker.
//
// Two phases, with every decision deferred to the pure
// TempSensorCatalog module:
//   1. Walk the SensorTreeModel, keep leaf ids whose DisplayRole looks
//      like a temperature reading ("Composite (°C)") — drops regex/group
//      nodes and non-temperature leaves without probing them.
//   2. An Instantiator of live Sensors.Sensor over those candidates;
//      buildTempSensorEntries keeps the ones reporting Celsius + Ready
//      and shapes the [{id, label}] picker list.
//
// Public surface:
//   active  - gate; candidates and Sensor probes exist only while true.
//   sensors - [{id, label}] of every discovered Celsius sensor ([] while
//             gated off).

Item {
    id: discovery

    property bool active: false

    // Reactive surface; reads _entries, which _rebuild() only swaps when
    // the content actually changed (JSON compare — same guard as
    // MetricsBackend._refreshDiscovery). A fresh-but-identical array
    // would still re-notify consumers, and an editable ComboBox bound to
    // it as `model` resets its text on every reassignment.
    readonly property var sensors: discovery._entries

    property var _entries: []
    property var _candidateIds: []

    // Called directly from each probe's status flip and from Instantiator
    // adds/removes (inner Sensor property reads are not tracked by
    // bindings — the reason MetricsBackend uses tick counters; calling
    // the recompute from the signal sites achieves the same without one).

    function _rebuild() {
        var probed = [];
        for (var i = 0; i < sensorInstantiator.count; i++) {
            var s = sensorInstantiator.objectAt(i);
            if (s)
                probed.push({
                    "id": s.sensorId,
                    "name": s.name,
                    "unit": s.unit,
                    "ready": s.status === Sensors.Sensor.Ready
                });
        }
        var built = TempSensorCatalog.buildTempSensorEntries(probed);
        if (JSON.stringify(built) !== JSON.stringify(discovery._entries))
            discovery._entries = built;
    }

    Sensors.SensorTreeModel {
        id: sensorTree
    }

    function _refreshCandidates() {
        if (!discovery.active) {
            if (discovery._candidateIds.length > 0)
                discovery._candidateIds = [];
            return;
        }
        var out = [];
        function visit(parent) {
            var rc = parent === undefined ? sensorTree.rowCount() : sensorTree.rowCount(parent);
            for (var i = 0; i < rc; i++) {
                var idx = parent === undefined ? sensorTree.index(i, 0) : sensorTree.index(i, 0, parent);
                var id = sensorTree.data(idx, Sensors.SensorTreeModel.SensorId);
                if (id && sensorTree.rowCount(idx) === 0 && TempSensorCatalog.isTempCandidate(sensorTree.data(idx, Qt.DisplayRole)))
                    out.push(id);
                visit(idx);
            }
        }
        visit(undefined);
        // rowsInserted fires for unrelated tree sections, so only assign
        // on a real change — same JSON-compare guard as
        // MetricsBackend._refreshDiscovery, to avoid spurious
        // Instantiator rebuilds.
        if (JSON.stringify(discovery._candidateIds) !== JSON.stringify(out))
            discovery._candidateIds = out;
    }

    onActiveChanged: discovery._refreshCandidates()
    Component.onCompleted: discovery._refreshCandidates()

    Connections {
        target: sensorTree
        function onRowsInserted() {
            discovery._refreshCandidates();
        }
        function onRowsRemoved() {
            discovery._refreshCandidates();
        }
        function onModelReset() {
            discovery._refreshCandidates();
        }
    }

    Instantiator {
        id: sensorInstantiator
        model: discovery._candidateIds
        delegate: Sensors.Sensor {
            required property string modelData
            sensorId: modelData
            enabled: discovery.active
            onStatusChanged: discovery._rebuild()
        }
        onObjectAdded: discovery._rebuild()
        onObjectRemoved: discovery._rebuild()
    }
}
