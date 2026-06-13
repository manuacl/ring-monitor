import QtQuick
import RingMonitor.Standalone
import "ProcParser.js" as ProcParser
import "ProcStatParser.js" as ProcStatParser
import "MemInfoParser.js" as MemInfoParser
import "../../core/ProcessRanking.js" as ProcessRanking

// Standalone source for the CPU-ring and RAM-ring process tooltips (issues
// #69 / #70). Enumerates /proc and ranks the top processes by CPU% or RSS —
// but ONLY while `active`, so there's no background process polling (the
// tooltip flips `active` true on hover via MetricsBackend.processSamplingActive).
// Split out of MetricsBackend.qml so that adapter stays under the 500-line cap
// and this stays a focused, separately-testable unit.
//
// Public surface (mirrored by the Plasma adapter's ProcessDataModel wiring):
//   active           - gate; sampling runs only while true.
//   topProcesses     - top-20 [{pid, name, cpuPercent}] by CPU%, ranked.
//   loadAverages     - [1, 5, 15]-min load averages for the CPU tooltip footer.
//   topMemProcesses  - top-20 [{pid, name, rssKb}] by RSS, ranked.
//   memUsedKb        - MemTotal − MemAvailable in kB (RAM tooltip footer).
//   memTotalKb       - MemTotal in kB (RAM tooltip footer).

Item {
    id: sampler

    property bool active: false
    readonly property var topProcesses: sampler._top
    readonly property var loadAverages: sampler._load
    readonly property var topMemProcesses: sampler._memTop
    readonly property real memUsedKb: sampler._memUsedKb
    readonly property real memTotalKb: sampler._memTotalKb

    property var _top: []
    property var _load: [0, 0, 0]
    property var _memTop: []
    // memUsedKb = MemTotal − MemAvailable; see MemInfoParser.js header for
    // why MemAvailable (not MemFree) is the honest "free" denominator.
    property real _memUsedKb: 0
    property real _memTotalKb: 0
    // Previous samples for the delta: pid→{pid, name, jiffies}, and the
    // aggregate /proc/stat jiffy array (the denominator). Both null while
    // inactive so the first tick after a hover only seeds a baseline and the
    // second computes — a stale snapshot would yield a bogus first delta.
    property var _prevPids: null
    property var _prevAll: null
    // pageSize is constant per process lifetime; cache once to avoid a
    // C++ call inside the per-pid loop (reader.pageSize() / 1024 = kB/page).
    property real _pageKb: 0

    ProcReader {
        id: reader
    }

    Component.onCompleted: {
        // Cache page size once at startup: sysconf(_SC_PAGESIZE) is constant
        // for the lifetime of the process; calling it inside the per-pid loop
        // would invoke a C++ round-trip for every process every tick.
        sampler._pageKb = reader.pageSize() / 1024;
    }

    // Reads its OWN /proc/stat (independent of MetricsBackend's ring sampling)
    // so the per-process numerator and the system-wide denominator come from
    // the same interval. The extra read only happens while hovering — cheap.
    //
    // NOTE: the per-pid loop below does one synchronous reader.read() per
    // process on the GUI thread each tick. For typical desktop process counts
    // (~hundreds) that's a few ms, and it's gated on hover — acceptable for v1.
    // On a server-class host (thousands of processes) it could jank; moving the
    // enumeration to a worker thread (like statvfs, issue #48) is the follow-up
    // if that ever bites.
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

        // Memory ranking uses the current snapshot directly — RSS needs no
        // prev/cur delta, so the RAM tooltip has data on the very first tick.
        var pageKb = sampler._pageKb;
        var memRecs = [];
        for (var pid in curMap) {
            if (!Object.prototype.hasOwnProperty.call(curMap, pid))
                continue;
            var r = curMap[pid];
            memRecs.push({
                pid: r.pid,
                name: r.name,
                rssKb: r.rssPages * pageKb
            });
        }
        sampler._memTop = ProcessRanking.rankByMemory(memRecs);

        // RAM footer: MemTotal and MemUsed = MemTotal − MemAvailable.
        // MemAvailable is the kernel's own estimate of reclaimable memory,
        // which is what users mean by "free" — see MemInfoParser.js header.
        var memRaw = reader.read("/proc/meminfo");
        var mem = MemInfoParser.parseMemInfo(memRaw);
        sampler._memTotalKb = (mem.total !== null) ? mem.total : 0;
        // Null-check (the parser's missing-field sentinel), NOT truthiness:
        // available === 0 is a real reading (full OOM) and must yield used = total.
        sampler._memUsedKb = (mem.total !== null && mem.available !== null) ? (mem.total - mem.available) : 0;
    }

    function _reset() {
        sampler._prevPids = null;
        sampler._prevAll = null;
        sampler._top = [];
        sampler._load = [0, 0, 0];
        sampler._memTop = [];
        sampler._memUsedKb = 0;
        sampler._memTotalKb = 0;
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
