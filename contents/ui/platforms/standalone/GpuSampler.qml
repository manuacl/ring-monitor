import QtQuick
import RingMonitor.Standalone
import "GpuDiscovery.js" as GpuDisc

// Standalone GPU sampling — extracted from MetricsBackend to keep that file
// under the 500-line cap. Owns the NVML reader, the AMD/Intel sysfs discovery,
// and the always-on usage+temp reads. Also provides gated detail (VRAM / power
// / clock / model) for the GPU tooltip (issue #71) when detailActive is true.
//
// Inputs:
//   reader       — the parent MetricsBackend's ProcReader (injected; not owned here)
//   detailActive — true only while the GPU tooltip is shown; gates detail polling
//
// Public surface (consumed by MetricsBackend):
//   readonly property real usage
//   readonly property real tempC
//   readonly property bool available
//   readonly property bool tempAvailable
//   function sample()      — per-tick GPU work; MetricsBackend's Timer calls it
//   function gpuDetail()   — tooltip detail snapshot (call only when detailActive)

Item {
    id: gpuSampler

    // ── Inputs ──────────────────────────────────────────────────────────
    property var reader: null
    // Gate: set true only while the GPU tooltip is shown. When false the
    // NvmlReader.sample(false) call skips the detail queries, keeping the
    // fast always-on path. Same ProcessSampler / DiskPartitionSensors gate
    // pattern used by the other tooltip backends.
    property bool detailActive: false

    // ── Public surface ───────────────────────────────────────────────────
    readonly property real usage: gpuSampler._gpuUsage
    readonly property real tempC: gpuSampler._gpuTempC
    readonly property bool available: gpuSampler._gpuAvailable
    readonly property bool tempAvailable: gpuSampler._gpuTempAvailable

    // ── NVIDIA GPU via NVML (dlopen'd libnvidia-ml) ──────────────────────
    // available:false on non-NVIDIA hosts — AMD/Intel sysfs runs only when
    // nvml.available is false this tick, preventing a hybrid NVIDIA+AMD host
    // from latching AMD paths after a transient NVML hiccup and permanently
    // shadowing NVML values with AMD values.
    NvmlReader {
        id: gpuReader
    }

    // ── Always-on GPU state ──────────────────────────────────────────────
    property real _gpuUsage: 0
    property real _gpuTempC: NaN
    // Whether any GPU has a usage source (NVML, or AMD sysfs gpu_busy_percent);
    // false on Intel-only (needs elevated perms) and GPU-less hosts.
    property bool _gpuAvailable: false
    // Whether any GPU has a temp source (NVML, or AMD/Intel hwmon). Separate so
    // an Intel-temp-only host shows a gpuTemp ring without _gpuAvailable.
    property bool _gpuTempAvailable: false
    // AMD/Intel GPU sysfs paths resolved once by GpuDiscovery (empty until
    // resolved or after the retry window closes): gpu_busy_percent + hwmon temp.
    property string _gpuBusyPath: ""
    property string _gpuTempPath: ""
    // "amd" | "intel" | "nouveau" | "" (NVIDIA excluded — NVML path; "" while unresolved)
    property string _gpuVendor: ""
    // Bounded retry: a hwmon driver can be modprobed a few seconds AFTER login,
    // so re-walk sysfs for the first N ticks then give up (no per-tick walk on a
    // sensorless host). See standalone/CLAUDE.md § "Sysfs discovery retry gate".
    property int _gpuResolveAttempts: 0
    readonly property int _gpuMaxResolveAttempts: 60  // ~30s at the 2 Hz Timer

    // ── AMD detail paths (set by _resolveGpuPaths; empty when absent) ────
    // VRAM nodes live directly under the card device dir (not in hwmon).
    // powerPath is in MICROWATTS on amdgpu — divided by 1e6 in sample().
    property string _gpuVramUsedPath: ""
    property string _gpuVramTotalPath: ""
    property string _gpuPowerPath: ""

    // ── Last-good detail values ──────────────────────────────────────────
    // Persisted across ticks so gpuDetail() returns stable values between
    // samples. Overwritten only when detailActive AND the read succeeds.
    // NaN default: undefined-until-seen (same sentinel as _gpuTempC).
    property string _gpuModel: ""
    property real _gpuVramUsedBytes: NaN
    property real _gpuVramTotalBytes: NaN
    property real _gpuPowerW: NaN
    property real _gpuClockMhz: NaN

    // ── Path discovery ───────────────────────────────────────────────────
    // Delegate to GpuDiscovery to find the first AMD or Intel DRM card and
    // record its sysfs paths. Called at most once per session (on the first
    // non-NVIDIA tick, with a bounded retry window). ProcReader references
    // are wrapped in closures to keep GpuDiscovery pure (no direct I/O in
    // the module, same rationale as CpuTempDiscovery.js).
    // Retry gate keeps retrying while EITHER path is still empty
    // (!_gpuBusyPath || !_gpuTempPath) so a late-loaded hwmon (Intel i915 /
    // udev settle, or amdgpu's hwmon registering a few seconds after the DRM
    // node) is discovered within the 30 s window even after the first path
    // already resolved. && would close the gate the moment one path landed,
    // stranding the other for the whole session (issue #83).
    function _resolveGpuPaths() {
        var info = GpuDisc.discoverGpu(function (path) {
            return gpuSampler.reader.listDir(path);
        }, function (path) {
            return gpuSampler.reader.read(path);
        });
        if (!info)
            return;
        gpuSampler._gpuVendor = info.vendor;
        gpuSampler._gpuBusyPath = info.busyPath || "";
        gpuSampler._gpuTempPath = info.tempPath || "";
        // AMD detail paths — present only when the kernel/driver exposes them
        // (amdgpu since kernel 4.2 for VRAM; power1_input since amdgpu hwmon).
        gpuSampler._gpuVramUsedPath = info.vramUsedPath || "";
        gpuSampler._gpuVramTotalPath = info.vramTotalPath || "";
        gpuSampler._gpuPowerPath = info.powerPath || "";
    }

    // ── Per-tick GPU sampling ─────────────────────────────────────────────
    // Called each Timer interval by MetricsBackend. Implements the same
    // always-on NVML + AMD/Intel sysfs logic that previously lived inline
    // in MetricsBackend._sample(), moved verbatim — semantics are identical.
    //
    // sample() OMITS a field whose NVML query failed this tick — commit only
    // present keys so a transient failure keeps the last-good value.
    // Availability derives from this tick's read success (liveness model):
    // an AMD eGPU hot-unplug makes reads fail → ring disappears ≤1 tick,
    // matching NVML's per-tick available flag behaviour for NVIDIA.
    function sample() {
        // Pass the detail gate so NVML fills the extended fields only when
        // the tooltip is open — the always-on path (sample(false)) stays
        // exactly as fast as before.
        var nvml = gpuReader.sample(gpuSampler.detailActive);
        if (nvml.available) {
            if (nvml.usage !== undefined)
                gpuSampler._gpuUsage = nvml.usage;
            if (nvml.tempC !== undefined)
                gpuSampler._gpuTempC = nvml.tempC;
            // Detail branch — NVML: copy present keys into last-good props.
            // Omit-on-failure: never overwrite a last-good with a missing key.
            if (gpuSampler.detailActive) {
                if (nvml.model !== undefined)
                    gpuSampler._gpuModel = nvml.model;
                if (nvml.vramUsedBytes !== undefined && isFinite(nvml.vramUsedBytes))
                    gpuSampler._gpuVramUsedBytes = nvml.vramUsedBytes;
                if (nvml.vramTotalBytes !== undefined && isFinite(nvml.vramTotalBytes))
                    gpuSampler._gpuVramTotalBytes = nvml.vramTotalBytes;
                if (nvml.powerW !== undefined && isFinite(nvml.powerW))
                    gpuSampler._gpuPowerW = nvml.powerW;
                if (nvml.clockMhz !== undefined && isFinite(nvml.clockMhz))
                    gpuSampler._gpuClockMhz = nvml.clockMhz;
            }
        }
        var sysfsUsageValid = false;
        var sysfsTempValid = false;
        if (!nvml.available) {
            // Only AMD has a usage path; Intel/nouveau are temp-only, so don't
            // require _gpuBusyPath for them (it would re-walk sysfs every tick
            // for the whole window). Unknown vendor → require both until ID'd.
            var needBusyPath = gpuSampler._gpuVendor === "" || gpuSampler._gpuVendor === "amd";
            var gpuPathsIncomplete = (needBusyPath && !gpuSampler._gpuBusyPath) || !gpuSampler._gpuTempPath;
            if (gpuPathsIncomplete && gpuSampler._gpuResolveAttempts < gpuSampler._gpuMaxResolveAttempts) {
                gpuSampler._gpuResolveAttempts++;
                gpuSampler._resolveGpuPaths();
            }
            if (gpuSampler._gpuBusyPath) {
                var gpuUsage = parseInt(gpuSampler.reader.read(gpuSampler._gpuBusyPath).trim(), 10);
                if (isFinite(gpuUsage)) {
                    gpuSampler._gpuUsage = gpuUsage;
                    sysfsUsageValid = true;
                }
            }
            if (gpuSampler._gpuTempPath) {
                var sysfsTemp = GpuDisc.parseTempCelsius(gpuSampler.reader.read(gpuSampler._gpuTempPath));
                if (isFinite(sysfsTemp)) {
                    gpuSampler._gpuTempC = sysfsTemp;
                    sysfsTempValid = true;
                }
            }
            // Detail branch — AMD sysfs: read the extra paths only when the
            // tooltip is active. Omit-on-failure (isFinite guard) so a
            // missing/unreadable node never overwrites a last-good value.
            if (gpuSampler.detailActive) {
                if (gpuSampler._gpuVramUsedPath) {
                    var vramUsed = parseInt(gpuSampler.reader.read(gpuSampler._gpuVramUsedPath).trim(), 10);
                    if (isFinite(vramUsed))
                        gpuSampler._gpuVramUsedBytes = vramUsed;
                }
                if (gpuSampler._gpuVramTotalPath) {
                    var vramTotal = parseInt(gpuSampler.reader.read(gpuSampler._gpuVramTotalPath).trim(), 10);
                    if (isFinite(vramTotal))
                        gpuSampler._gpuVramTotalBytes = vramTotal;
                }
                if (gpuSampler._gpuPowerPath) {
                    // power1_input is in microwatts on amdgpu — divide by 1e6 for watts.
                    var powerUw = parseInt(gpuSampler.reader.read(gpuSampler._gpuPowerPath).trim(), 10);
                    if (isFinite(powerUw))
                        gpuSampler._gpuPowerW = powerUw / 1e6;
                }
            }
        }
        gpuSampler._gpuAvailable = nvml.available || sysfsUsageValid;
        gpuSampler._gpuTempAvailable = nvml.available || sysfsTempValid;
    }

    // ── GPU tooltip detail snapshot ───────────────────────────────────────
    // Returns the last-good detail values gathered while detailActive was
    // true. Each field is present (finite / non-empty) only when a source
    // was found and a read succeeded; otherwise undefined — callers must
    // check before rendering.
    //
    // tempC is returned as the raw last-good NaN (not coerced to 0) so a
    // caller can distinguish "not read yet" from "genuinely 0°C". The ring
    // surface (_coerceTemp) handles the NaN→0 coercion separately.
    function gpuDetail() {
        return {
            "model": gpuSampler._gpuModel !== "" ? gpuSampler._gpuModel : undefined,
            "usagePercent": gpuSampler._gpuAvailable ? gpuSampler._gpuUsage : undefined,
            "vramUsedBytes": isFinite(gpuSampler._gpuVramUsedBytes) ? gpuSampler._gpuVramUsedBytes : undefined,
            "vramTotalBytes": isFinite(gpuSampler._gpuVramTotalBytes) ? gpuSampler._gpuVramTotalBytes : undefined,
            "tempC": (gpuSampler._gpuTempAvailable && isFinite(gpuSampler._gpuTempC)) ? gpuSampler._gpuTempC : undefined,
            "powerW": isFinite(gpuSampler._gpuPowerW) ? gpuSampler._gpuPowerW : undefined,
            "clockMhz": isFinite(gpuSampler._gpuClockMhz) ? gpuSampler._gpuClockMhz : undefined
        };
    }
}
