import QtQuick
import RingMonitor.Standalone
import "ProcStatParser.js" as ProcStatParser
import "MemInfoParser.js" as MemInfoParser
import "CpuTempDiscovery.js" as CpuTemp
import "../../core/MetricsCatalog.js" as Catalog

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
// Scope: CPU usage (aggregate + per-core), RAM, disk, and CPU
// temperature (hwmon / thermal-zone via CpuTempDiscovery). GPU (sysfs
// DRM + `nvidia-smi`) and swap land post-MVP.

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

    // True until the second `/proc/stat` sample lands ~1 s after
    // startup (the Timer fires every `interval` ms). CPU usage
    // requires two samples (the delta between them); the first tick
    // captures `_prev`, the second tick computes the percent. RAM
    // and disk are point-in-time reads and would technically be
    // ready on the first tick, but gating them on the same flag
    // keeps the warm-up sweep visually consistent across all three
    // rings — no reader needs to wonder whether one specific value
    // is "still loading" or "really zero". The 1 s warm-up is the
    // cost of this consistency; a future `Qt.callLater(_sample)` in
    // `Component.onCompleted` could halve it if the boot-time blank
    // ever becomes a UX complaint.
    readonly property bool loading: backend._prev === null

    function metricValue(id) {
        backend._tick;
        if (id === "cpu")
            return backend._aggregateUsage;
        if (id === "ram")
            return backend._ramUsage;
        if (id === "disk")
            return backend._diskUsage;
        // cpuTemp is a raw-°C metric (Catalog.isTempMetric): MainContent
        // reads metricValue for the centre text and runs it through
        // tempToPercent itself for the sweep — same contract the Plasma
        // adapter satisfies via valueFromSensorMap(sensorMap, "cpuTemp").
        if (id === "cpuTemp")
            return backend._coercedCpuTempC();
        // swap / GPU return 0 — added post-MVP.
        return 0;
    }

    // Raw °C for the split-mode right half (cpu ring merged with its
    // temperature). gpuTemp returns 0 until GPU support lands.
    function metricRawTemp(id) {
        backend._tick;
        if (id === "cpu")
            return backend._coercedCpuTempC();
        return 0;
    }

    // _cpuTempC carries NaN internally until a sensor is resolved (and
    // read). Coerce it to 0 at the public surface so this adapter
    // matches the Plasma one byte-for-byte: there
    // valueFromSensorMap(...) returns 0 for an unread/missing sensor, so
    // a consumer doing arithmetic on the value never sees NaN on one
    // host and 0 on the other.
    function _coercedCpuTempC() {
        return isFinite(backend._cpuTempC) ? backend._cpuTempC : 0;
    }

    function metricTempPercent(id) {
        return Catalog.tempToPercent(metricRawTemp(id));
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
    // Resolved once at startup (the hwmonN numbering + owning chip are
    // machine-specific — see CpuTempDiscovery.js). "" when no CPU
    // temperature sensor was found; _cpuTempC then stays NaN, which
    // Catalog.tempToPercent / convertTemp render as an unavailable 0.
    property string _cpuTempPath: ""
    property real _cpuTempC: NaN

    // Walk /sys/class/hwmon, then fall back to /sys/class/thermal, and
    // return the sysfs file to read each tick — or "" if none. All the
    // "which entry is the CPU" decisions are the pure CpuTempDiscovery
    // helpers; this function is just the I/O glue around them.
    function _resolveCpuTempPath() {
        var fromHwmon = _resolveFromHwmon();
        if (fromHwmon)
            return fromHwmon;
        return _resolveFromThermalZones();
    }

    function _resolveFromHwmon() {
        var base = "/sys/class/hwmon";
        var dirs = reader.listDir(base);
        var entries = [];
        for (var i = 0; i < dirs.length; i++) {
            var name = reader.read(base + "/" + dirs[i] + "/name").trim();
            if (name)
                entries.push({
                    "dir": dirs[i],
                    "name": name
                });
        }
        var cpuDir = CpuTemp.pickCpuHwmonDir(entries);
        if (!cpuDir)
            return "";
        var chip = base + "/" + cpuDir;
        var files = reader.listDir(chip);
        var sensors = [];
        for (var j = 0; j < files.length; j++) {
            if (!CpuTemp.isTempInput(files[j]))
                continue;
            var labelFile = files[j].replace("_input", "_label");
            sensors.push({
                "input": files[j],
                "label": reader.read(chip + "/" + labelFile).trim()
            });
        }
        var input = CpuTemp.pickCpuTempInput(sensors);
        return input ? chip + "/" + input : "";
    }

    function _resolveFromThermalZones() {
        var base = "/sys/class/thermal";
        var dirs = reader.listDir(base);
        var zones = [];
        for (var i = 0; i < dirs.length; i++) {
            if (!/^thermal_zone\d+$/.test(dirs[i]))
                continue;
            zones.push({
                "dir": dirs[i],
                "type": reader.read(base + "/" + dirs[i] + "/type").trim()
            });
        }
        var zone = CpuTemp.pickCpuThermalZone(zones);
        return zone ? base + "/" + zone + "/temp" : "";
    }

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
        // diskUsagePercent uses df(1)'s formula (excludes root-reserved
        // blocks from "size") so the ring matches `df -h /` output.
        // usagePercent would count the ext4 5% reservation as used.
        var disk = reader.statvfs(backend._diskMount);
        backend._diskUsage = MemInfoParser.diskUsagePercent(disk.total, disk.free, disk.available);
        // ── hwmon / thermal (CPU temperature) ───────────────────────
        // Re-resolve while still unresolved: the hwmon driver
        // (coretemp / k10temp / …) can be modprobed AFTER the widget
        // starts — common when it autostarts at login before the sensor
        // modules load. Without the retry the temp ring would stay stuck
        // at 0 for the whole session. Once resolved, the guard is a
        // single string check (no sysfs walk) per tick.
        if (!backend._cpuTempPath)
            backend._cpuTempPath = backend._resolveCpuTempPath();
        if (backend._cpuTempPath)
            backend._cpuTempC = CpuTemp.parseTempCelsius(reader.read(backend._cpuTempPath));
        // Bump _tick last so all readonly properties depending on it
        // re-evaluate together after every metric has its fresh value.
        backend._tick++;
    }

    // Resolve the CPU-temperature sysfs path before the first sample.
    // onCompleted runs synchronously during construction, ahead of the
    // Timer's queued triggeredOnStart fire, so _cpuTempPath is set by
    // the time _sample() first reads it. If nothing resolves here (no
    // driver loaded yet), _sample() keeps retrying until one appears.
    Component.onCompleted: backend._cpuTempPath = backend._resolveCpuTempPath()

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: backend._sample()
    }
}
