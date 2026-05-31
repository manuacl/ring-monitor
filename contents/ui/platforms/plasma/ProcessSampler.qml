import QtQuick
import org.kde.ksysguard.sensors as Sensors
import org.kde.ksysguard.process as Process
import "../../core/ProcessRanking.js" as ProcessRanking

// Plasma source for the CPU-ring process tooltip (issue #69) — the counterpart
// of platforms/standalone/ProcessSampler.qml, satisfying the same surface
// (active / topProcesses / loadAverages) from `org.kde.ksysguard.process`
// `ProcessDataModel` instead of /proc. Split out of MetricsBackend.qml so that
// adapter stays under the 500-line cap and this stays a focused unit.
//
// ProcessDataModel: rows = processes, columns = enabledAttributes (in order),
// read via data(index(row, col), Value). It only updates while `enabled`, so
// binding that to `active` is the "no background process polling" gate (#69).
//
// CPU NORMALISATION: ksysguard's "usage" attribute is PER-CORE (a fully-busy
// thread reads ~100%, the total across processes can reach coreCount*100 —
// confirmed in libksysguard processes.cpp: the jiffy delta is divided by
// elapsed time only, never by the processor count). To match the chosen "total
// 0-100%" tooltip semantics (rows sum toward the aggregate ring) we divide each
// reading by coreCount here. The standalone /proc path is already total-
// normalised (delta over the system-wide jiffy delta), so only this side divides.

Item {
    id: sampler

    property bool active: false
    // Injected by MetricsBackend (= coreValues.length). max(1, …) guards the
    // divide before per-core discovery has populated.
    property int coreCount: 1
    readonly property var topProcesses: sampler._top
    readonly property var loadAverages: [_load1.value || 0, _load5.value || 0, _load15.value || 0]

    property var _top: []

    // Column order follows enabledAttributes: 0 = name, 1 = pid, 2 = usage.
    Process.ProcessDataModel {
        id: procModel
        enabled: sampler.active
        flatList: true
        enabledAttributes: ["name", "pid", "usage"]
    }

    function _collect() {
        var rows = procModel.rowCount();
        var ncores = Math.max(1, sampler.coreCount);
        var records = [];
        for (var r = 0; r < rows; r++) {
            var name = procModel.data(procModel.index(r, 0), Process.ProcessDataModel.Value);
            var pid = procModel.data(procModel.index(r, 1), Process.ProcessDataModel.Value);
            var usage = procModel.data(procModel.index(r, 2), Process.ProcessDataModel.Value);
            records.push({
                "pid": pid,
                "name": name,
                "cpuPercent": (usage || 0) / ncores
            });
        }
        sampler._top = ProcessRanking.rankByCpu(records);
    }

    onActiveChanged: {
        if (active)
            _collect();
        else
            sampler._top = [];
    }

    // Load averages for the tooltip footer (ksysguard cpu/loadaverages/*).
    // On a host without the sensor, status stays unresolved and value || 0 → 0.
    Sensors.Sensor {
        id: _load1
        sensorId: "cpu/loadaverages/loadaverage1"
    }
    Sensors.Sensor {
        id: _load5
        sensorId: "cpu/loadaverages/loadaverage5"
    }
    Sensors.Sensor {
        id: _load15
        sensorId: "cpu/loadaverages/loadaverage15"
    }

    // ProcessDataModel self-updates at its own interval while enabled; this
    // Timer just snapshots + re-ranks it on a coarse cadence (running only
    // while active — same "no background polling" gate as the standalone
    // sampler). triggeredOnStart fills the list immediately on hover.
    Timer {
        interval: 1000
        running: sampler.active
        repeat: true
        triggeredOnStart: true
        onTriggered: sampler._collect()
    }
}
