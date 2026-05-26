import QtQuick
import RingMonitor.Standalone
import "../../core/ProcStatParser.js" as ProcStatParser
import "../../core/MemInfoParser.js" as MemInfoParser

// Standalone counterpart of `platforms/plasma/MetricsBackend.qml`.
// Exposes the same public surface so the portable `core/MainContent`
// view stack renders unchanged on either host:
//
//   readonly property var coreValues
//   readonly property bool loading
//   function metricValue(id)
//   function metricRawTemp(id)
//   function metricTempPercent(id)
//
// Backend = single `Timer` polling once per second via the
// `ProcReader` C++ helper (`/proc/stat`, `/proc/meminfo`, `statvfs`
// on `/`), then deferring the parse + percent math to the pure
// modules in `core/`. Maximum work in `core/`, minimum in this
// adapter — same rule that drove the `SensorPicking` extraction
// (see [feedback-maximize-shared-code] memory).
//
// Scope at this stage (PR E): CPU usage (aggregate + per-core),
// RAM, disk. GPU (sysfs DRM + `nvidia-smi`), temperatures (hwmon),
// and swap land post-MVP.

Item {
    id: backend

    // ── Public surface ──────────────────────────────────────────────
    //
    // coreValues re-evaluates on _tick — bumped each Timer interval
    // once we have both a prev and a current sample. The function
    // form (vs. a static N-element list) scales to any core count
    // discovered at runtime.
    property int _tick: 0
    readonly property var coreValues: {
        backend._tick;
        return backend._coreUsage.slice();
    }

    // True until the second `/proc/stat` sample lands — CPU usage
    // requires two samples (the delta between them). RAM and disk
    // are point-in-time reads and would technically be ready on the
    // first tick, but gating them on the same flag keeps the warm-up
    // sweep visually consistent across all three rings.
    readonly property bool loading: backend._prev === null

    function metricValue(id) {
        backend._tick;
        if (id === "cpu")
            return backend._aggregateUsage;
        if (id === "ram")
            return backend._ramUsage;
        if (id === "disk")
            return backend._diskUsage;
        // swap / GPU / temps return 0 in PR E — added post-MVP.
        return 0;
    }

    function metricRawTemp(id) {
        return 0;  // PR D doesn't read hwmon yet.
    }

    function metricTempPercent(id) {
        return 0;
    }

    // ── Internal ────────────────────────────────────────────────────

    ProcReader {
        id: reader
    }

    property var _prev: null  // {all, cores} from the previous /proc/stat sample
    property real _aggregateUsage: 0
    property var _coreUsage: []
    property real _ramUsage: 0
    property real _diskUsage: 0

    // Root filesystem — matches the Plasma adapter's `disk/all/usedPercent`
    // surface closely enough for the MVP. A per-mount selector becomes
    // relevant only when multiple disks are exposed; configurable in
    // a follow-up if asked for.
    readonly property string _diskMount: "/"

    function _sample() {
        // ── /proc/stat (CPU) ────────────────────────────────────────
        var statRaw = reader.read("/proc/stat");
        var parsed = ProcStatParser.parseProcStat(statRaw);
        if (parsed.all && backend._prev) {
            backend._aggregateUsage = ProcStatParser.percentFromSample(backend._prev.all, parsed.all);
            var cores = [];
            // Iterate against the smaller of the two arrays so a
            // late-binding /proc/stat (core count growing) doesn't
            // crash. Drops the new core for this tick; it appears on
            // the next one when prev has it too.
            var n = Math.min(backend._prev.cores.length, parsed.cores.length);
            for (var i = 0; i < n; i++) {
                cores.push(ProcStatParser.percentFromSample(backend._prev.cores[i], parsed.cores[i]));
            }
            backend._coreUsage = cores;
        }
        if (parsed.all)
            backend._prev = parsed;
        // ── /proc/meminfo (RAM) ─────────────────────────────────────
        var memRaw = reader.read("/proc/meminfo");
        var mem = MemInfoParser.parseMemInfo(memRaw);
        backend._ramUsage = MemInfoParser.usagePercent(mem.total, mem.available);
        // ── statvfs(/) (disk) ───────────────────────────────────────
        var disk = reader.statvfs(backend._diskMount);
        backend._diskUsage = MemInfoParser.usagePercent(disk.total, disk.available);
        // Bump _tick last so all readonly properties depending on it
        // re-evaluate together after every metric has its fresh value.
        backend._tick++;
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: backend._sample()
    }
}
