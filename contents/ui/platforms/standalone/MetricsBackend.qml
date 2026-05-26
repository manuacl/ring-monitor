import QtQuick
import RingMonitor.Standalone
import "../../core/ProcStatParser.js" as ProcStatParser

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
// Backend = `Timer` polling `/proc/stat` once per second via the
// `ProcReader` C++ helper, then deferring the parse + delta math to
// the pure `ProcStatParser` module in `core/`. Maximum work in
// `core/`, minimum in this adapter — same rule that drove the
// `SensorPicking` extraction (see [feedback-maximize-shared-code]
// memory).
//
// Scope at this stage (PR D): CPU usage (aggregate + per-core) only.
// RAM (`/proc/meminfo`) + disk (`statvfs`) land in PR E. GPU
// (sysfs DRM + `nvidia-smi`) and temperatures (hwmon) land
// post-MVP.

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

    // True until the second `/proc/stat` sample lands — usage
    // requires two samples (the delta between them).
    readonly property bool loading: backend._prev === null

    function metricValue(id) {
        if (id === "cpu") {
            backend._tick;
            return backend._aggregateUsage;
        }
        // RAM / swap / disk / GPU / temps return 0 in PR D — added
        // by PR E and post-MVP follow-ups.
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

    property var _prev: null  // {all, cores} from the previous sample
    property real _aggregateUsage: 0
    property var _coreUsage: []

    function _sample() {
        var raw = reader.read("/proc/stat");
        var parsed = ProcStatParser.parseProcStat(raw);
        if (!parsed.all)
            return;  // unreadable / malformed — try again next tick.
        if (backend._prev) {
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
            backend._tick++;
        }
        backend._prev = parsed;
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: backend._sample()
    }
}
