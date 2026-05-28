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
// Backend = single `Timer` polling at 2 Hz (every 500 ms, matching the
// Plasma ksysguard cadence) via the
// `ProcReader` C++ helper (`/proc/stat`, `/proc/meminfo`, `statvfs`
// on `/`), then deferring the parse + percent math to the pure
// modules in `core/`. Maximum work in `core/`, minimum in this
// adapter — same rule that drove the `SensorPicking` extraction
// (see [feedback-maximize-shared-code] memory).
//
// Scope: CPU usage (aggregate + per-core), RAM, disk, CPU temperature
// (hwmon / thermal-zone via CpuTempDiscovery), and NVIDIA GPU usage +
// temperature (NVML via the NvmlReader C++ helper). AMD/Intel GPU
// (sysfs) and swap land in a follow-up.

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

    // True until the second `/proc/stat` sample lands ~0.5 s after
    // startup (the Timer fires every `interval` ms). CPU usage
    // requires two samples (the delta between them); the first tick
    // captures `_prev`, the second tick computes the percent. RAM
    // and disk are point-in-time reads and would technically be
    // ready on the first tick, but gating them on the same flag
    // keeps the warm-up sweep visually consistent across all three
    // rings — no reader needs to wonder whether one specific value
    // is "still loading" or "really zero". The ~0.5 s warm-up is the
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
        if (id === "gpu")
            return backend._gpuUsage;
        // cpuTemp / gpuTemp are raw-°C metrics (Catalog.isTempMetric):
        // MainContent reads metricValue for the centre text and runs it
        // through tempToPercent itself for the sweep — same contract the
        // Plasma adapter satisfies via valueFromSensorMap(sensorMap, id).
        if (id === "cpuTemp")
            return backend._coerceTemp(backend._cpuTempC);
        if (id === "gpuTemp")
            return backend._coerceTemp(backend._gpuTempC);
        // swap returns 0 — added post-MVP.
        return 0;
    }

    // Raw °C for the split-mode right half (a usage ring merged with its
    // temperature) — cpu and gpu both supported.
    function metricRawTemp(id) {
        backend._tick;
        if (id === "cpu")
            return backend._coerceTemp(backend._cpuTempC);
        if (id === "gpu")
            return backend._coerceTemp(backend._gpuTempC);
        return 0;
    }

    // A temp property carries NaN internally until its sensor is resolved
    // (and read). Coerce it to 0 at the public surface so this adapter
    // matches the Plasma one byte-for-byte: there valueFromSensorMap(...)
    // returns 0 for an unread/missing sensor, so a consumer doing
    // arithmetic on the value never sees NaN on one host and 0 on the
    // other. Generalised over cpuTemp/gpuTemp (any future raw-°C metric).
    function _coerceTemp(celsius) {
        return isFinite(celsius) ? celsius : 0;
    }

    function metricTempPercent(id) {
        return Catalog.tempToPercent(metricRawTemp(id));
    }

    // ── Internal ────────────────────────────────────────────────────

    ProcReader {
        id: reader
    }

    // NVIDIA GPU via NVML (dlopen'd libnvidia-ml). available:false on
    // non-NVIDIA hosts — AMD/Intel sysfs land in a follow-up.
    NvmlReader {
        id: gpuReader
    }

    property var _prev: null  // {all, cores} from the previous /proc/stat sample
    property real _aggregateUsage: 0
    property var _coreUsage: []
    property real _ramUsage: 0
    property real _diskUsage: 0
    // Resolved lazily over a short warm-up window (the hwmonN numbering
    // + owning chip are machine-specific — see CpuTempDiscovery.js).
    // "" while unresolved; _cpuTempC then stays NaN, coerced to 0 at the
    // public surface by _coerceTemp.
    property string _cpuTempPath: ""
    property real _cpuTempC: NaN
    // Bounded retry: a hwmon driver (coretemp/k10temp/…) can be modprobed
    // a few seconds AFTER the widget autostarts at login, so we re-walk
    // sysfs for the first _cpuTempMaxResolveAttempts ticks. After that we
    // give up — a machine with genuinely no CPU temp sensor (VM, unknown
    // hardware) must NOT re-walk /sys every tick for the whole session.
    property int _cpuTempResolveAttempts: 0
    readonly property int _cpuTempMaxResolveAttempts: 60  // ~30s at the 2 Hz Timer
    // GPU (NVIDIA/NVML). _gpuUsage is a 0-100 percent; _gpuTempC is raw °C
    // (NaN until/unless NVML reports it, coerced to 0 at the surface).
    property real _gpuUsage: 0
    property real _gpuTempC: NaN

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
        // Resolve the sysfs path on the first tick, retrying for a
        // bounded warm-up window if it doesn't resolve immediately (a
        // late-modprobed driver). Once resolved, or once the window
        // closes, this is a single string check (no sysfs walk) per
        // tick — the common "no sensor" case stops scanning instead of
        // re-walking /sys forever. (triggeredOnStart fires the first
        // _sample at startup, so no separate Component.onCompleted.)
        if (!backend._cpuTempPath && backend._cpuTempResolveAttempts < backend._cpuTempMaxResolveAttempts) {
            backend._cpuTempResolveAttempts++;
            backend._cpuTempPath = backend._resolveCpuTempPath();
        }
        if (backend._cpuTempPath)
            backend._cpuTempC = CpuTemp.parseTempCelsius(reader.read(backend._cpuTempPath));
        // ── NVML (NVIDIA GPU usage + temperature) ───────────────────
        // NVML calls are microseconds, so this is a synchronous per-tick
        // read on the GUI thread (the reason we chose the library over a
        // nvidia-smi subprocess — no spawn, no frame drop). On a
        // non-NVIDIA host sample() reports available:false and we leave
        // _gpuUsage at 0 / _gpuTempC at NaN (→ 0 at the surface).
        // sample() OMITS a field whose NVML query failed this tick, so we
        // commit only the keys that are present — a transient failure then
        // keeps the last-good value (or the NaN temp sentinel) instead of
        // snapping the ring to 0.
        var gpu = gpuReader.sample();
        if (gpu.available) {
            if (gpu.usage !== undefined)
                backend._gpuUsage = gpu.usage;
            if (gpu.tempC !== undefined)
                backend._gpuTempC = gpu.tempC;
        }
        // Bump _tick last so all readonly properties depending on it
        // re-evaluate together after every metric has its fresh value.
        backend._tick++;
    }

    Timer {
        // 500 ms (2 Hz) to match the Plasma adapter: the ksysguard
        // daemon pushes sensor updates at ~500 ms, so a 1 Hz Timer here
        // made the standalone rings step in coarser jumps than the
        // Plasma widget (measured, not assumed). 500 ms also sits just
        // above Ring.qml's 400 ms value animation, so each sweep
        // finishes before the next sample — no overlapping easings.
        interval: 500
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: backend._sample()
    }
}
