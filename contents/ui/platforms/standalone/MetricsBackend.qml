import QtQuick
import RingMonitor.Standalone
import "ProcStatParser.js" as ProcStatParser
import "MemInfoParser.js" as MemInfoParser
import "CpuTempDiscovery.js" as CpuTemp
import "HwmonTempDiscovery.js" as HwmonTemp
import "DiskDiscovery.js" as DiskDiscovery
import "../../core/MetricsCatalog.js" as Catalog
import "../../core/DiskMetrics.js" as DiskMetrics

// Standalone counterpart of `platforms/plasma/MetricsBackend.qml`.
// Exposes the same public surface so the portable `core/MainContent`
// view stack renders unchanged on either host:
//
//   readonly property var coreValues
//   readonly property bool loading
//   function metricValue(id)
//   function metricRawTemp(id)
//   function metricTempPercent(id)
//   readonly property var availablePartitions   (disk multi-ring)
//   readonly property var defaultPartitionIds
//   function partitionValue(id)
//   function partitionDetail(id)                 (disk-ring tooltip, #68)
//   property string sensorTempId                 (custom temp, #164)
//   readonly property var tempSensors
//   readonly property bool sensorTempResolved
//   readonly property real sensorTempValue
//
// Backend = single `Timer` polling at 2 Hz (500 ms, matching the Plasma
// ksysguard cadence) via the `ProcReader` C++ helper (`/proc/stat`,
// `/proc/meminfo`, async `statvfs` per selected filesystem), deferring the
// parse + percent math to the pure modules in `core/` (maximum work in `core/`,
// minimum here — the [feedback-maximize-shared-code] rule).
//
// Scope: CPU usage (aggregate + per-core), RAM, swap, disk, CPU temp (hwmon/
// thermal-zone), GPU usage+temp (NVIDIA via NVML, AMD via sysfs, Intel
// temp-only), and the custom hwmon temperature (sensorTemp, #164).
// Discovery details live in the *Discovery.js modules.

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

    // True until the second `/proc/stat` sample lands ~0.5 s after startup. CPU
    // usage needs two samples (the delta); RAM/disk are point-in-time but gate
    // on the same flag so the warm-up sweep stays visually consistent across all
    // rings.
    readonly property bool loading: backend._prev === null

    // Catalog ids with a live data source (same surface as the Plasma adapter).
    // gpuTemp also requires a finite reading so a failing temp query shows no
    // dead 0°C ring. Depends ONLY on the capability properties — NOT on _tick
    // (each has NOTIFY), so it doesn't hand MainContent a fresh array every poll
    // and rebuild the whole strip at 2 Hz (a fixed review bug).
    readonly property var availableMetrics: Catalog.availableMetricsFrom({
        "cpu": true,
        "cpuTemp": backend._cpuTempPath !== "",
        "ram": true,
        "swap": backend._swapAvailable,
        "gpu": gpuSampler.available,
        "gpuTemp": gpuSampler.tempAvailable && isFinite(gpuSampler.tempC),
        "disk": true,
        // /proc/diskstats always exists (no-op until the diskIo UI PR adds the catalog id).
        "diskIo": true,
        // sensorTemp = the user-configured custom hardware sensor (#164):
        // available once the configured id is set AND resolved to a live
        // sysfs path with a finite reading (the sensorTempResolved gate).
        "sensorTemp": backend.sensorTempId.length > 0 && backend.sensorTempResolved
    })

    // ── Custom hardware temperature (sensorTemp, #164) ──────────────
    // The configured sensor id, stable across boots (HwmonTempDiscovery
    // grammar — never a hwmonN path). Set by Main.qml from the
    // ConfigStore; the settings dialog binds the same property.
    property string sensorTempId: ""
    // Every discovered temperature input ([{ id, label }], sorted chip
    // then index) for the settings picker — rebuilt only when the
    // enumeration re-runs, so the binding doesn't churn per tick.
    readonly property var tempSensors: sensorProbe.tempSensors
    // True when the configured id resolved to a current sysfs path AND
    // the last reading was finite (a removed/unreadable sensor drops the
    // ring instead of freezing at its last value, like gpuTemp).
    readonly property bool sensorTempResolved: backend.sensorTempId.length > 0 && backend._sensorTempPath !== "" && isFinite(backend._sensorTempC)
    // Raw °C of the configured sensor, NaN while unresolved.
    readonly property real sensorTempValue: backend._sensorTempC

    function metricValue(id) {
        backend._tick;
        if (id === "cpu")
            return backend._aggregateUsage;
        if (id === "ram")
            return backend._ramUsage;
        // Aggregate fallback = the default (home) partition, not statvfs("/")
        // (a composefs overlay stuck near 100% on rpm-ostree). MainContent
        // renders disk multi-partition and never reads this; it's the sane
        // single number for an aggregate consumer.
        if (id === "disk")
            return backend.defaultPartitionIds.length > 0 ? backend.partitionValue(backend.defaultPartitionIds[0]) : 0;
        if (id === "gpu")
            return gpuSampler.usage;
        if (id === "swap")
            return backend._swapUsage;
        // cpuTemp / gpuTemp are raw-°C metrics (Catalog.isTempMetric):
        // MainContent reads metricValue for the centre text and runs it
        // through tempToPercent itself for the sweep — same contract the
        // Plasma adapter satisfies via valueFromSensorMap(sensorMap, id).
        if (id === "cpuTemp")
            return backend._coerceTemp(backend._cpuTempC);
        if (id === "gpuTemp")
            return backend._coerceTemp(gpuSampler.tempC);
        if (id === "sensorTemp")
            return backend._coerceTemp(backend._sensorTempC);
        return 0;
    }

    // Raw °C for the split-mode right half (a usage ring merged with its
    // temperature) — cpu and gpu both supported.
    function metricRawTemp(id) {
        backend._tick;
        if (id === "cpu")
            return backend._coerceTemp(backend._cpuTempC);
        if (id === "gpu")
            return backend._coerceTemp(gpuSampler.tempC);
        return 0;
    }

    // A temp property is NaN until its sensor resolves; coerce to 0 at the
    // public surface so this adapter matches the Plasma one (valueFromSensorMap
    // returns 0 for an unread sensor) — a consumer never sees NaN on one host
    // and 0 on the other. Generalised over any raw-°C metric.
    function _coerceTemp(celsius) {
        return isFinite(celsius) ? celsius : 0;
    }

    function metricTempPercent(id) {
        return Catalog.tempToPercent(metricRawTemp(id));
    }

    // ── CPU + RAM process tooltips (issues #69 / #70) ───────────────
    // /proc enumeration lives in the ProcessSampler child; we just forward.
    // Properties (not functions) so bindings in the tooltips stay live.
    property alias processSamplingActive: processSampler.active
    readonly property var topProcesses: processSampler.topProcesses
    readonly property var loadAverages: processSampler.loadAverages
    readonly property var topMemProcesses: processSampler.topMemProcesses
    readonly property real memUsedKb: processSampler.memUsedKb
    readonly property real memTotalKb: processSampler.memTotalKb

    ProcessSampler {
        id: processSampler
    }

    // ── Disk I/O throughput ring (issue #77) ─────────────────────────
    // `io` (reactive) = per-component byte/s + arc %; the gate keeps the
    // /proc/diskstats poll off while the ring is off-screen. See DiskIoSampler.
    property alias diskIoSamplingActive: diskIoSampler.active
    readonly property var diskIo: diskIoSampler.io

    DiskIoSampler {
        id: diskIoSampler
    }

    // ── Disk partitions (multi-ring) ─────────────────────────────────
    //
    // availablePartitions / defaultPartitionIds are rebuilt only when
    // /proc/mounts actually changes (USB plug, mount/unmount), so the
    // identity stays stable across ticks. Mirrors the Plasma adapter's
    // SensorTreeModel-driven discovery surface.
    readonly property var availablePartitions: backend._partitions.map(function (p) {
        return {
            "id": p.id,
            "label": p.label
        };
    })
    // Currently-mounted removable filesystems (auto-show source on standalone), matching the Plasma surface.
    readonly property var removablePartitions: (backend._partitions || []).filter(function (p) {
        return DiskMetrics.isRemovableMount(p.mountpoint);
    }).map(function (p) {
        return {
            "id": p.id,
            "label": p.label
        };
    })
    // Every currently-mounted UUID (the live mount set; /proc/mounts is always fresh on standalone).
    readonly property var mountedPartitionIds: (backend._partitions || []).map(function (p) {
        return p.id;
    })
    property var defaultPartitionIds: []

    // Per-partition usage %, read NON-BLOCKING off the GUI thread (issue #48):
    // requestStatvfs kicks a worker read, cachedStatvfs returns last-good.
    // Full rationale: standalone/CLAUDE.md § "statvfs runs off the GUI thread".
    function partitionValue(id) {
        backend._tick;
        backend._partTick;
        var mount = backend._mountForId[id];
        if (!mount)
            return 0;
        reader.requestStatvfs(mount);
        var disk = reader.cachedStatvfs(mount);
        return MemInfoParser.diskUsagePercent(disk.total, disk.free, disk.available);
    }

    // Full per-partition detail for the disk-ring tooltip (#68), same shape as
    // the Plasma adapter. Bytes share the off-GUI-thread statvfs cache; the
    // user-facing "free" = available (df Avail, what you can write). DiskMetrics
    // owns the assembly + the removable rule.
    function partitionDetail(id) {
        backend._tick;
        backend._partTick;
        var stats = {};
        var mount = backend._mountForId[id];
        if (mount) {
            reader.requestStatvfs(mount);
            var disk = reader.cachedStatvfs(mount);
            // freeBytes = available (df "Avail"); cachedStatvfs sets all 3 or {}.
            stats = {
                "usedPercent": MemInfoParser.diskUsagePercent(disk.total, disk.free, disk.available),
                "totalBytes": disk.total || 0,
                "freeBytes": disk.available || 0
            };
        }
        return DiskMetrics.buildPartitionDetail(id, backend._partForId[id], stats);
    }

    // ── Internal ────────────────────────────────────────────────────

    ProcReader {
        id: reader
    }

    // Bumped when an async statvfs lands so the disk bindings re-evaluate
    // immediately. Separate from _tick so a disk update doesn't re-run the
    // CPU/RAM/GPU bindings; no loop (the re-request is throttled in ProcReader).
    property int _partTick: 0
    Connections {
        target: reader
        function onStatvfsReady(mount) {
            backend._partTick++;
        }
    }

    // GPU sampling is owned entirely by the GpuSampler child — NVML (NVIDIA)
    // + AMD/Intel sysfs always-on usage/temp + gated detail for the tooltip.
    // gpuDetailSamplingActive is set by MainContent when the GPU tooltip is
    // shown (default false — the detail polling is off until armed).
    property bool gpuDetailSamplingActive: false

    GpuSampler {
        id: gpuSampler
        reader: reader
        detailActive: backend.gpuDetailSamplingActive
    }

    // gpuDetail / gpuProcesses forward the sampler's reactive properties so
    // view bindings stay live — a property read tracks the source, a function
    // call evaluates once and freezes (core/CLAUDE.md § "Reactive argless data").
    readonly property var gpuDetail: gpuSampler.gpuDetail
    readonly property var gpuProcesses: gpuSampler.gpuProcesses

    property var _prev: null  // {all, cores} from the previous /proc/stat sample
    property real _aggregateUsage: 0
    property var _coreUsage: []
    property real _ramUsage: 0
    property real _swapUsage: 0
    // Whether the kernel reports any swap (SwapTotal > 0; zram counts). false on
    // a swapless host, where availableMetrics then drops "swap".
    property bool _swapAvailable: false
    // Discovered filesystems (rebuilt only when /proc/mounts changes).
    // _partitions: [{id, label, mountpoint, fstype, device}]; _mountForId maps a
    // partition id → its representative mountpoint for the live statvfs;
    // _partForId maps id → the whole entry for partitionDetail's O(1) lookup.
    property var _partitions: []
    property var _mountForId: ({})
    property var _partForId: ({})
    property string _lastMountsRaw: ""
    property string _canonicalHome: ""
    // Resolved lazily over a short warm-up window (hwmonN numbering is
    // machine-specific — see CpuTempDiscovery.js). "" while unresolved →
    // _cpuTempC stays NaN, coerced to 0 at the surface by _coerceTemp.
    property string _cpuTempPath: ""
    property real _cpuTempC: NaN
    // Bounded retry: a hwmon driver can be modprobed a few seconds AFTER login,
    // so re-walk sysfs for the first N ticks then give up (no per-tick walk on a
    // sensorless host). See standalone/CLAUDE.md § "Sysfs discovery retry gate".
    property int _cpuTempResolveAttempts: 0
    readonly property int _cpuTempMaxResolveAttempts: 60  // ~30s at the 2 Hz Timer

    // ── sensorTemp internals (#164) ─────────────────────────────────
    // The probe owns the sysfs enumeration (shared with the settings
    // dialog); active stays false here — the backend reads only the ONE
    // configured sensor per tick, not the whole catalog.
    HwmonTempSensors {
        id: sensorProbe
        active: false
    }
    // Current-boot sysfs path the configured id resolved to ("" while
    // unresolved → _sensorTempC stays NaN, coerced to 0 at the surface).
    property string _sensorTempPath: ""
    property real _sensorTempC: NaN
    // Same bounded warm-up window as the CPU temp: the full hwmon
    // enumeration retries while the catalog is empty (a driver modprobed
    // after login), then stops — no per-tick sysfs walk afterwards.
    property int _sensorEnumAttempts: 0
    readonly property int _sensorMaxEnumAttempts: 60  // ~30s at the 2 Hz Timer

    onSensorTempIdChanged: {
        // Re-resolve against the cached catalog (no sysfs walk). When the
        // catalog is still empty the _sample retry re-enumerates within
        // the window and the next tick resolves. NaN flush so a stale
        // reading of the PREVIOUS sensor never shows under the new id.
        backend._sensorTempPath = HwmonTemp.resolveSensorPath(sensorProbe.catalog, backend.sensorTempId);
        backend._sensorTempC = NaN;
    }

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

    // Rebuild the partition list from /proc/mounts. Cheap string compare
    // gate so the (slightly heavier) block-device walk + rebuild only runs
    // when mounts actually change — a USB plug/unmount, not every tick.
    function _refreshPartitions() {
        var raw = reader.read("/proc/mounts");
        if (raw === backend._lastMountsRaw)
            return;
        backend._lastMountsRaw = raw;
        if (!backend._canonicalHome)
            backend._canonicalHome = reader.canonicalHome();
        var mounts = DiskDiscovery.parseMounts(raw);
        var parts = DiskDiscovery.buildPartitions(mounts, reader.blockDeviceInfo());
        var mountForId = {};
        var partForId = {};
        for (var i = 0; i < parts.length; i++) {
            mountForId[parts[i].id] = parts[i].mountpoint;
            partForId[parts[i].id] = parts[i];
        }
        backend._mountForId = mountForId;
        backend._partForId = partForId;
        backend._partitions = parts;
        // Default = the $HOME-bearing filesystem (or the first partition when
        // home detection fails). Same helper as the SettingsDialog picker so
        // the rendered default and the seeded default never diverge.
        backend.defaultPartitionIds = DiskDiscovery.defaultOrFirst(mounts, parts, backend._canonicalHome);
    }

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
        // Swap usage shares the RAM formula: used = total - free. zram
        // (the default swap on many distros) is reported as swap by the
        // kernel, so this is non-zero on a typical desktop; 0 only on a genuinely
        // swapless host (usagePercent returns 0 when swapTotal is 0).
        backend._swapUsage = MemInfoParser.usagePercent(mem.swapTotal, mem.swapFree);
        backend._swapAvailable = mem.swapTotal > 0;
        // ── disk partitions ─────────────────────────────────────────
        // Refresh the discovered filesystem list when mounts change; the
        // per-partition usage % itself is read live in partitionValue(id)
        // (statvfs with df(1)'s formula) only for the selected rings.
        backend._refreshPartitions();
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
        // ── hwmon custom temperature (sensorTemp) ───────────────────
        // Full enumeration retries within the same bounded window as the
        // CPU temp while the catalog is empty; afterwards the per-tick
        // cost is one file read of the resolved path.
        if (sensorProbe.catalog.length === 0 && backend._sensorEnumAttempts < backend._sensorMaxEnumAttempts) {
            backend._sensorEnumAttempts++;
            sensorProbe.enumerate();
        }
        if (backend.sensorTempId.length > 0) {
            if (backend._sensorTempPath === "")
                backend._sensorTempPath = HwmonTemp.resolveSensorPath(sensorProbe.catalog, backend.sensorTempId);
            if (backend._sensorTempPath !== "")
                backend._sensorTempC = HwmonTemp.parseTempCelsius(reader.read(backend._sensorTempPath));
        }
        // ── GPU: delegated to GpuSampler child ──────────────────────
        // All GPU logic (NVML + AMD/Intel sysfs, retry gate, liveness flags,
        // detail branch) now lives in GpuSampler.qml. MetricsBackend reads
        // the results through gpuSampler.usage / .tempC / .available /
        // .tempAvailable — all updated synchronously inside sample().
        gpuSampler.sample();
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
