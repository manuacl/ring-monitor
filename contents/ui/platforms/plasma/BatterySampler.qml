import QtQuick
import org.kde.ksysguard.sensors as Sensors
import "../../core/BatteryAggregate.js" as BatteryAggregate

// Plasma source for the battery ring — counterpart of the standalone
// BatteryStatus adapter, satisfying the same `battery` surface from
// ksysguard's power/<id>/chargePercentage and power/<id>/chargeRate
// sensors instead of /sys/class/power_supply.
//
// Discovery: ksysguard identifies each physical battery by its serial or
// UDI tail, not a fixed index. There is no aggregate power/all/chargePercentage
// leaf. So sensor ids are enumerated from a SensorTreeModel (the same
// pattern MetricsBackend uses for CPU cores and GPU devices): a
// power/*/chargePercentage walk collects the battery object prefixes,
// then two Instantiators spawn one Sensor per battery for the percent and
// rate leaves.
//
// Aggregation: weight:1 per battery (simple mean). ksysguard does not
// cheaply expose per-battery capacity, and most laptops have exactly one
// battery — equal weights yield the expected mean for multi-battery hosts too.
//
// A host without a battery produces zero discovered ids → aggregate()
// returns { percent: 0, charging: false, available: false }, so the ring
// is dropped from the strip rather than showing a dead 0% gauge.
//
// Public surface (mirrors the standalone adapter byte-for-byte):
//   battery (readonly property var) — { percent: 0..100, charging: bool,
//                                       available: bool }

Item {
    id: sampler

    // Discovered battery object prefixes, e.g. ["power/BAT0", "power/BAT1"].
    property var _batteryIds: []

    // Tick counter: bumped whenever an Instantiator delegate is added/removed
    // or any per-battery sensor value/status changes. Reading it as the
    // first expression in `battery` makes the binding re-evaluate on every
    // change — the standard QML workaround for Instantiator-driven readonly
    // bindings (see platforms/plasma/CLAUDE.md § "tick counter").
    property int _tick: 0

    // Aggregate { percent, charging, available } from all Ready batteries.
    readonly property var battery: {
        sampler._tick;
        var records = [];
        for (var i = 0; i < percentInst.count; i++) {
            var pct = percentInst.objectAt(i);
            var rate = rateInst.objectAt(i);
            if (!pct || !rate)
                continue;
            if (pct.status !== Sensors.Sensor.Ready)
                continue;
            var pv = pct.value;
            if (typeof pv !== "number" || !isFinite(pv))
                continue;
            records.push({
                "percent": pv,
                "weight": 1,
                // ksysguard chargeRate is signed: + charging, − discharging, 0
                // while full-on-AC (or briefly idle). It exposes no charge-state
                // enum and no AC-online sensor (ksystemstats power.cpp only wraps
                // Solid::Battery). So treat "not actively discharging" (rate ≥ 0)
                // as charging — a full battery on AC reads bright, matching the
                // standalone adapter's status="Full" → charging. Unavoidable edge:
                // a battery idle-at-rest off AC (rate exactly 0) also reads bright.
                "charging": (rate.status === Sensors.Sensor.Ready && typeof rate.value === "number" && rate.value >= 0)
            });
        }
        return BatteryAggregate.aggregate(records);
    }

    // Walk the SensorTreeModel for power/*/chargePercentage leaves and
    // extract the battery object prefix (e.g. "power/BAT0"). Called on
    // startup and again on every structural tree change.
    function _refresh() {
        var found = [];
        function visit(parent) {
            var rc = (parent === undefined) ? batteryTree.rowCount() : batteryTree.rowCount(parent);
            for (var i = 0; i < rc; i++) {
                var idx = (parent === undefined) ? batteryTree.index(i, 0) : batteryTree.index(i, 0, parent);
                var sid = batteryTree.data(idx, Sensors.SensorTreeModel.SensorId);
                if (sid && sid.indexOf("/chargePercentage") !== -1)
                    found.push(sid.replace("/chargePercentage", ""));
                visit(idx);
            }
        }
        visit(undefined);
        if (JSON.stringify(found) !== JSON.stringify(sampler._batteryIds))
            sampler._batteryIds = found;
    }

    Sensors.SensorTreeModel {
        id: batteryTree
    }

    Component.onCompleted: _refresh()
    Connections {
        target: batteryTree
        function onRowsInserted() {
            sampler._refresh();
        }
        function onRowsRemoved() {
            sampler._refresh();
        }
        function onModelReset() {
            sampler._refresh();
        }
    }

    // One chargePercentage Sensor per discovered battery.
    Instantiator {
        id: percentInst
        model: sampler._batteryIds
        delegate: Sensors.Sensor {
            required property string modelData
            sensorId: modelData + "/chargePercentage"
            onValueChanged: sampler._tick++
            onStatusChanged: sampler._tick++
        }
        onObjectAdded: sampler._tick++
        onObjectRemoved: sampler._tick++
    }

    // One chargeRate Sensor per discovered battery (signed: ≥0 = not discharging).
    Instantiator {
        id: rateInst
        model: sampler._batteryIds
        delegate: Sensors.Sensor {
            required property string modelData
            sensorId: modelData + "/chargeRate"
            onValueChanged: sampler._tick++
            onStatusChanged: sampler._tick++
        }
        onObjectAdded: sampler._tick++
        onObjectRemoved: sampler._tick++
    }
}
