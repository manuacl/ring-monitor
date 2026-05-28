import QtQuick
import org.kde.ksysguard.sensors as Sensors
import "../../core/MetricsCatalog.js" as Catalog

// Plasma-side disk partition discovery, shared by two consumers:
//   - MetricsBackend.qml  → drives the per-partition Sensor instances + the
//                           availablePartitions surface for the live widget.
//   - configMetrics.qml   → feeds the partition checkboxes in the config
//                           dialog (which has no MetricsBackend of its own).
//
// ksysguard keys each mounted filesystem by UUID (disk/<uuid>/usedPercent)
// and labels the parent node (disk/<uuid>) with the volume label
// ("bazzite", "photos", …). We walk the SensorTreeModel, classify the
// usedPercent leaves via the pure Catalog helper, and pair each with its
// parent's display name.
//
// Public surface:
//   readonly property var partitions  - [{ id, label, sensorId }], one per
//                                       mounted filesystem (id = the UUID,
//                                       sensorId = disk/<uuid>/usedPercent).

Item {
    id: disk

    property int _tick: 0
    property var _partitions: []
    readonly property var partitions: {
        disk._tick;
        return disk._partitions.slice();
    }

    Sensors.SensorTreeModel {
        id: tree
    }

    // Walk every node, returning { ids: [...], labelByUuid: {uuid: label} }.
    // The FS label ("bazzite", "photos", …) lives on the parent node
    // (disk/<uuid>), whose own SensorId role can be empty (it's a grouping
    // node), so we can't look it up by id afterwards. Instead we carry each
    // node's display name down the recursion as `parentName`, and when we
    // reach a usedPercent leaf we record its parent's name as the label —
    // robust regardless of whether the parent is a subscribable sensor.
    function _walk() {
        var ids = [];
        var labelByUuid = {};
        function visit(parent, parentName) {
            var rc = (parent === undefined) ? tree.rowCount() : tree.rowCount(parent);
            for (var i = 0; i < rc; i++) {
                var idx = (parent === undefined) ? tree.index(i, 0) : tree.index(i, 0, parent);
                var id = tree.data(idx, Sensors.SensorTreeModel.SensorId) || "";
                var name = tree.data(idx, Qt.DisplayRole) || "";
                if (id)
                    ids.push(id);
                var m = /^disk\/([A-Za-z0-9_-]+)\/usedPercent$/.exec(id);
                if (m && id !== "disk/all/usedPercent")
                    labelByUuid[m[1]] = parentName;
                visit(idx, name);
            }
        }
        visit(undefined, "");
        return {
            "ids": ids,
            "labelByUuid": labelByUuid
        };
    }

    function _refresh() {
        var walked = disk._walk();
        var usageIds = Catalog.classifyDiscoveredIds(walked.ids).diskPartitionUsageIds;
        var parts = [];
        for (var i = 0; i < usageIds.length; i++) {
            var sid = usageIds[i];                  // disk/<uuid>/usedPercent
            var uuid = sid.split("/")[1];
            parts.push({
                "id": uuid,
                "label": walked.labelByUuid[uuid] || uuid,
                "sensorId": sid
            });
        }
        // Avoid churning consumers when the set hasn't actually changed.
        if (JSON.stringify(parts) !== JSON.stringify(disk._partitions)) {
            disk._partitions = parts;
            disk._tick++;
        }
    }

    Component.onCompleted: disk._refresh()
    Connections {
        target: tree
        function onRowsInserted() {
            disk._refresh();
        }
        function onRowsRemoved() {
            disk._refresh();
        }
        function onModelReset() {
            disk._refresh();
        }
    }
}
