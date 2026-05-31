import QtQuick
import RingMonitor.Standalone
import "ProcParser.js" as ProcParser
import "ProcStatParser.js" as ProcStatParser
import "../../core/ProcessRanking.js" as ProcessRanking

// Standalone source for the CPU-ring process tooltip (issue #69). Enumerates
// /proc and ranks the top processes by total-normalised CPU% — but ONLY while
// `active`, so there's no background process polling (the tooltip flips
// `active` true on hover via MetricsBackend.processSamplingActive). Split out
// of MetricsBackend.qml so that adapter stays under the 500-line cap and this
// stays a focused, separately-testable unit.
//
// Public surface (mirrored by the Plasma adapter's ProcessDataModel wiring):
//   active        - gate; sampling runs only while true.
//   topProcesses  - top-20 [{pid, name, cpuPercent}] by CPU%, ranked.
//   loadAverages  - [1, 5, 15]-min load averages for the tooltip footer.

Item {
    id: sampler

    property bool active: false
    readonly property var topProcesses: sampler._top
    readonly property var loadAverages: sampler._load

    property var _top: []
    property var _load: [0, 0, 0]
    // Previous samples for the delta: pid→{pid, name, jiffies}, and the
    // aggregate /proc/stat jiffy array (the denominator). Both null while
    // inactive so the first tick after a hover only seeds a baseline and the
    // second computes — a stale snapshot would yield a bogus first delta.
    property var _prevPids: null
    property var _prevAll: null

    ProcReader {
        id: reader
    }

    // Reads its OWN /proc/stat (independent of MetricsBackend's ring sampling)
    // so the per-process numerator and the system-wide denominator come from
    // the same interval. The extra read only happens while hovering — cheap.
    function _sample() {
        var stat = ProcStatParser.parseProcStat(reader.read("/proc/stat"));
        var totalDelta = (stat.all && sampler._prevAll) ? (ProcParser.sumJiffies(stat.all) - ProcParser.sumJiffies(sampler._prevAll)) : 0;
        sampler._prevAll = stat.all;

        var entries = reader.listDir("/proc");
        var curMap = {};
        for (var i = 0; i < entries.length; i++) {
            // Only numeric entries are pids; /proc also holds cpuinfo, meminfo, …
            if (!/^\d+$/.test(entries[i]))
                continue;
            var rec = ProcParser.parsePidStat(reader.read("/proc/" + entries[i] + "/stat"));
            if (rec)
                curMap[rec.pid] = rec;
        }
        sampler._top = ProcessRanking.rankByCpu(ProcParser.computePercents(sampler._prevPids, curMap, totalDelta));
        sampler._prevPids = curMap;
        sampler._load = ProcParser.parseLoadAvg(reader.read("/proc/loadavg"));
    }

    function _reset() {
        sampler._prevPids = null;
        sampler._prevAll = null;
        sampler._top = [];
        sampler._load = [0, 0, 0];
    }

    onActiveChanged: {
        if (!active)
            _reset();
    }

    // running:active stops the Timer the moment the tooltip closes — the
    // "no polling in the background" guarantee. triggeredOnStart seeds the
    // baseline immediately on hover so the second tick (≤500 ms later, within
    // the tooltip's show-delay) already has deltas to show.
    Timer {
        interval: 500
        running: sampler.active
        repeat: true
        triggeredOnStart: true
        onTriggered: sampler._sample()
    }
}
