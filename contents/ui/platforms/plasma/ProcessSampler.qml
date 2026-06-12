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
    readonly property var loadAverages: [load1Sensor.value || 0, load5Sensor.value || 0, load15Sensor.value || 0]

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
        // Math.max(1, …) guards the divide. Transient under-division if the user
        // hovers within the first ~500 ms before per-core discovery fills
        // coreValues (coreCount 0 → divide by 1 → per-core values shown): it
        // self-corrects on the next 1 s tick, and the tooltip's own 500 ms
        // show-delay makes the first-frame window practically unreachable.
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

    // Only clear on deactivate; the Timer below (triggeredOnStart) is the single
    // first-sample path on activate — calling _collect() here too would enumerate
    // the model twice per hover-enter (and the first scan races ProcessDataModel's
    // post-enable repopulation, so it'd see a stale/empty model anyway). Mirrors
    // the standalone sampler, which also resets here and samples from the Timer.
    onActiveChanged: if (!active)
        sampler._top = []

    // Load averages for the tooltip footer (ksysguard cpu/loadaverages/*).
    // On a host without the sensor, status stays unresolved and value || 0 → 0.
    // `enabled: active` so ksysguard isn't subscribed in the background when the
    // tooltip is never hovered — matches the ProcessDataModel gate and the
    // standalone path (which reads /proc/loadavg only while sampling).
    Sensors.Sensor {
        id: load1Sensor
        sensorId: "cpu/loadaverages/loadaverage1"
        enabled: sampler.active
    }
    Sensors.Sensor {
        id: load5Sensor
        sensorId: "cpu/loadaverages/loadaverage5"
        enabled: sampler.active
    }
    Sensors.Sensor {
        id: load15Sensor
        sensorId: "cpu/loadaverages/loadaverage15"
        enabled: sampler.active
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
