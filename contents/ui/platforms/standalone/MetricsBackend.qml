import QtQuick
import RingMonitor.Standalone
import "ProcStatParser.js" as ProcStatParser
import "MemInfoParser.js" as MemInfoParser
import "CpuTempDiscovery.js" as CpuTemp
import "DiskDiscovery.js" as DiskDiscovery
import "GpuDiscovery.js" as GpuDisc
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
//
// Backend = single `Timer` polling at 2 Hz (every 500 ms, matching the
// Plasma ksysguard cadence) via the
// `ProcReader` C++ helper (`/proc/stat`, `/proc/meminfo`, async
// `statvfs` per selected filesystem), then deferring the parse + percent math to the pure
// modules in `core/`. Maximum work in `core/`, minimum in this
// adapter — same rule that drove the `SensorPicking` extraction
// (see [feedback-maximize-shared-code] memory).
//
// Scope: CPU usage (aggregate + per-core), RAM, swap, disk, CPU temperature
// (hwmon / thermal-zone via CpuTempDiscovery), NVIDIA GPU usage + temperature
// (NVML via the NvmlReader C++ helper), AMD GPU usage + temperature (sysfs
// gpu_busy_percent + hwmon via GpuDiscovery), and Intel GPU temperature (hwmon
// via GpuDiscovery; Intel usage needs i915-perf elevated perms — deferred).

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

    // Catalog ids with a live data source (same surface as the Plasma
    // adapter). The map below reads as the gating; gpuTemp additionally
    // requires a finite reading so a GPU whose temp query keeps failing shows
    // no dead 0°C ring (matches Plasma's split usage/temp gating).
    //
    // Depends ONLY on the capability properties — NOT on _tick. Each carries
    // its own NOTIFY, so it re-evaluates when a capability flips, not every
    // 500 ms poll (which would hand MainContent a fresh array identity each
    // tick and rebuild the whole ring strip at 2 Hz — a fixed review bug).
    readonly property var availableMetrics: Catalog.availableMetricsFrom({
        "cpu": true,
        "cpuTemp": backend._cpuTempPath !== "",
        "ram": true,
        "swap": backend._swapAvailable,
        "gpu": backend._gpuAvailable,
        "gpuTemp": backend._gpuTempAvailable && isFinite(backend._gpuTempC),
        "disk": true
    })

    function metricValue(id) {
        backend._tick;
        if (id === "cpu")
            return backend._aggregateUsage;
        if (id === "ram")
            return backend._ramUsage;
        // Aggregate fallback: the standalone "disk" value is the default
        // (home) partition rather than statvfs("/") — on rpm-ostree hosts
        // "/" is a composefs overlay stuck near 100%. MainContent normally
        // renders disk in multi-partition mode and never reads this; it's
        // the sane single-number answer for any aggregate consumer.
        if (id === "disk")
            return backend.defaultPartitionIds.length > 0 ? backend.partitionValue(backend.defaultPartitionIds[0]) : 0;
        if (id === "gpu")
            return backend._gpuUsage;
        if (id === "swap")
            return backend._swapUsage;
        // cpuTemp / gpuTemp are raw-°C metrics (Catalog.isTempMetric):
        // MainContent reads metricValue for the centre text and runs it
        // through tempToPercent itself for the sweep — same contract the
        // Plasma adapter satisfies via valueFromSensorMap(sensorMap, id).
        if (id === "cpuTemp")
            return backend._coerceTemp(backend._cpuTempC);
        if (id === "gpuTemp")
            return backend._coerceTemp(backend._gpuTempC);
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

    // ── CPU process tooltip (issue #69) ──────────────────────────────
    // Same surface as the Plasma adapter; the /proc enumeration lives in the
    // ProcessSampler child (own ProcReader + Timer, running only while active)
    // so this adapter stays under the 500-line cap. We just forward.
    // topProcesses is a property (not a function) so a UI binding tracks it
    // and the tooltip list refreshes live as the sampler re-ranks.
    property alias processSamplingActive: processSampler.active
    readonly property var topProcesses: processSampler.topProcesses
    readonly property var loadAverages: processSampler.loadAverages

    ProcessSampler {
        id: processSampler
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

    // Per-partition usage %, read NON-BLOCKING so a stuck mount (stale
    // NFS, hung autofs, spun-down USB) never freezes the GUI thread —
    // issue #48. requestStatvfs kicks a background read on a worker
    // thread (idempotent: deduped while in flight, throttled per mount),
    // and cachedStatvfs returns the last-good result (empty → 0% until
    // the first read lands). Reading _tick drives the periodic 500 ms
    // refresh (each Timer tick re-evaluates this, which re-requests);
    // _partTick makes it re-render the instant a result arrives. The
    // request fires only for the ids MainContent actually asks about
    // (the selected partitions), so an unselected disk is never probed.
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

    // ── Internal ────────────────────────────────────────────────────

    ProcReader {
        id: reader
    }

    // Bumped when an async statvfs lands so partitionValue re-evaluates
    // immediately (the 500 ms Timer would otherwise be the only refresh
    // and the rings would lag a tick behind a freshly-arrived value).
    // Kept separate from _tick so a disk-only update doesn't re-run the
    // CPU/RAM/GPU bindings. No feedback loop: the re-request that this
    // re-evaluation triggers is throttled away in ProcReader.
    property int _partTick: 0
    Connections {
        target: reader
        function onStatvfsReady(mount) {
            backend._partTick++;
        }
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
    property real _swapUsage: 0
    // Whether the kernel reports any swap (SwapTotal > 0). zram (the default
    // swap on many distros) counts, so this is true on a typical desktop;
    // false only on a genuinely swapless host, where availableMetrics then
    // drops "swap".
    property bool _swapAvailable: false
    // Discovered filesystems (rebuilt only when /proc/mounts changes).
    // _partitions: [{id, label, mountpoint, device}]; _mountForId maps a
    // partition id to its representative mountpoint for the live statvfs.
    property var _partitions: []
    property var _mountForId: ({})
    property string _lastMountsRaw: ""
    property string _canonicalHome: ""
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
    // Whether any GPU has a usage source: NVML (NVIDIA) or sysfs gpu_busy_percent
    // (AMD). false on Intel-only (usage needs i915-perf elevated perms) and on
    // hosts with no GPU at all.
    property bool _gpuAvailable: false
    // Whether any GPU has a temperature source: NVML (NVIDIA) or sysfs hwmon
    // (AMD/Intel). Separate from _gpuAvailable so Intel-temp-only hosts show a
    // gpuTemp ring even though _gpuAvailable stays false (no usage source).
    property bool _gpuTempAvailable: false
    // AMD/Intel GPU sysfs paths resolved once by GpuDiscovery (empty until
    // resolved or after the bounded retry window closes). _gpuBusyPath is the
    // gpu_busy_percent file; _gpuTempPath is the hwmon temp1_input file.
    property string _gpuBusyPath: ""
    property string _gpuTempPath: ""
    // "amd" | "intel" | "" (NVIDIA excluded — NVML path; "" while unresolved)
    property string _gpuVendor: ""
    property int _gpuResolveAttempts: 0
    readonly property int _gpuMaxResolveAttempts: 60  // ~30s at the 2 Hz Timer

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

    // Delegate to GpuDiscovery to find the first AMD or Intel DRM card and
    // record its sysfs paths. Called at most once per session (on the first
    // non-NVIDIA tick, with a bounded retry window). ProcReader references are
    // wrapped in closures to keep GpuDiscovery pure (no direct I/O in the
    // module, same rationale as CpuTempDiscovery.js).
    function _resolveGpuPaths() {
        var info = GpuDisc.discoverGpu(function (path) {
            return reader.listDir(path);
        }, function (path) {
            return reader.read(path);
        });
        if (!info)
            return;
        backend._gpuVendor = info.vendor;
        backend._gpuBusyPath = info.busyPath || "";
        backend._gpuTempPath = info.tempPath || "";
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
        for (var i = 0; i < parts.length; i++)
            mountForId[parts[i].id] = parts[i].mountpoint;
        backend._mountForId = mountForId;
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
        // ── GPU: NVML (NVIDIA) + sysfs (AMD/Intel) ──────────────────
        // NVML: synchronous per-tick read (microseconds via dlopen'd libnvidia-ml).
        // AMD/Intel sysfs reads run ONLY when nvml.available is false this tick —
        // preventing a hybrid NVIDIA+AMD host from having a transient NVML failure
        // latch AMD paths and permanently shadow NVML readings with AMD values.
        // Retry gate keeps retrying while EITHER path is still empty
        // (!_gpuBusyPath || !_gpuTempPath) so a late-loaded hwmon (Intel i915 /
        // udev settle, or amdgpu's hwmon registering a few seconds after the DRM
        // node) is discovered within the 30 s window even after the first path
        // already resolved. && would close the gate the moment one path landed,
        // stranding the other for the whole session (issue #83).
        // Availability derives from this tick's read success (liveness model):
        // an AMD eGPU hot-unplug makes reads fail → ring disappears ≤1 tick,
        // matching NVML's per-tick available flag behaviour for NVIDIA.
        //
        // sample() OMITS a field whose NVML query failed this tick — commit only
        // present keys so a transient failure keeps the last-good value.
        var nvml = gpuReader.sample();
        if (nvml.available) {
            if (nvml.usage !== undefined)
                backend._gpuUsage = nvml.usage;
            if (nvml.tempC !== undefined)
                backend._gpuTempC = nvml.tempC;
        }
        var sysfsUsageValid = false;
        var sysfsTempValid = false;
        if (!nvml.available) {
            // Only AMD has a usage path; Intel/nouveau are temp-only, so don't
            // require _gpuBusyPath for them (it would re-walk sysfs every tick
            // for the whole window). Unknown vendor → require both until ID'd.
            var needBusyPath = backend._gpuVendor === "" || backend._gpuVendor === "amd";
            var gpuPathsIncomplete = (needBusyPath && !backend._gpuBusyPath) || !backend._gpuTempPath;
            if (gpuPathsIncomplete && backend._gpuResolveAttempts < backend._gpuMaxResolveAttempts) {
                backend._gpuResolveAttempts++;
                backend._resolveGpuPaths();
            }
            if (backend._gpuBusyPath) {
                var gpuUsage = parseInt(reader.read(backend._gpuBusyPath).trim(), 10);
                if (isFinite(gpuUsage)) {
                    backend._gpuUsage = gpuUsage;
                    sysfsUsageValid = true;
                }
            }
            if (backend._gpuTempPath) {
                var sysfsTemp = GpuDisc.parseTempCelsius(reader.read(backend._gpuTempPath));
                if (isFinite(sysfsTemp)) {
                    backend._gpuTempC = sysfsTemp;
                    sysfsTempValid = true;
                }
            }
        }
        backend._gpuAvailable = nvml.available || sysfsUsageValid;
        backend._gpuTempAvailable = nvml.available || sysfsTempValid;
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
