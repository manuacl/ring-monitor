// Standalone-only pure JS module for sysfs-based AMD/Intel/nouveau GPU discovery.
// Mirrors the CpuTempDiscovery.js pattern: all sysfs I/O is injected via
// listDir/read args so the logic is fully Node-testable.
//
// Main entry: discoverGpu(listDir, read) → { vendor, busyPath, tempPath } | null
//   vendor:   "amd" | "intel" | "nouveau"
//   busyPath: sysfs file for GPU utilisation 0-100 (null on Intel — elevated
//             perms required for i915 perf; null on nouveau — no sysfs usage
//             counter, debugfs pstate needs root; both deferred)
//   tempPath: sysfs file for GPU temp in millidegrees (null if not found)
//
// NVIDIA (0x10de) on the PROPRIETARY driver is handled by NvmlReader / NVML —
// that path takes priority and this sysfs discovery only runs when NVML is
// unavailable (MetricsBackend gates on `!nvml.available`). On the open-source
// `nouveau` driver (or any host without the proprietary driver) NVML init
// fails, so we fall back to nouveau's hwmon for GPU TEMPERATURE only — usage
// stays unavailable (issue #106).
// Dual-loaded by QML (`import "GpuDiscovery.js" as GpuDisc`) and Node
// (module.exports shim at the bottom). No `.pragma library`.

var VENDOR_AMD    = "0x1002";  // AMD / ATI
var VENDOR_INTEL  = "0x8086";  // Intel
var VENDOR_NVIDIA = "0x10de";  // NVIDIA (nouveau fallback; proprietary → NVML)

// Main entry point. listDir and read are ProcReader method references,
// injected by the backend so this module stays pure (no direct I/O).
// Returns { vendor, busyPath, tempPath } on the first AMD or Intel DRM card
// found, or null when no eligible card exists.
// Card selection: lowest card number wins (card0 before card1) so the result
// is stable across boots even when multiple GPUs are present. AMD/Intel take
// priority over a nouveau card: they expose a usage source (or are first-class
// targets), whereas nouveau is a TEMP-ONLY fallback (issue #106) — so on a
// hybrid NVIDIA-nouveau + AMD host the AMD card (usage + temp) wins, and the
// nouveau card is used only when no AMD/Intel card exists.
function discoverGpu(listDir, read) {
    var cards = _sortedDrmCards(listDir("/sys/class/drm"));
    var nouveauBase = null;
    for (var i = 0; i < cards.length; i++) {
        var base = "/sys/class/drm/" + cards[i];
        var vendor = read(base + "/device/vendor").trim().toLowerCase();
        if (vendor === VENDOR_AMD)
            return _amdInfo(base, listDir, read);
        if (vendor === VENDOR_INTEL)
            return _intelInfo(base, listDir);
        if (vendor === VENDOR_NVIDIA && nouveauBase === null)
            nouveauBase = base;  // remember the lowest NVIDIA card; keep scanning for AMD/Intel
    }
    return nouveauBase !== null ? _nouveauInfo(nouveauBase, listDir) : null;
}

// Filter DRM entry list to `card\d+` names and sort numerically.
function _sortedDrmCards(entries) {
    return (entries || [])
        .filter(function (e) { return /^card\d+$/.test(e); })
        .sort(function (a, b) { return _cardNum(a) - _cardNum(b); });
}

function _cardNum(name) {
    return parseInt(name.replace("card", ""), 10);
}

function _amdInfo(base, listDir, read) {
    var busyFile = base + "/device/gpu_busy_percent";
    // Verify the file is present — kernel 4.19+ for amdgpu; older kernels lack
    // it. read() returns "" on missing/unreadable paths, so a non-empty result
    // (including "0\n" at idle) confirms existence.
    var busyPath = read(busyFile) !== "" ? busyFile : null;
    var tempPath = _drmHwmonTempPath(base + "/device/hwmon", listDir);
    return { vendor: "amd", busyPath: busyPath, tempPath: tempPath };
}

function _intelInfo(base, listDir) {
    // Intel GPU utilisation needs i915 perf counters (elevated perms) —
    // deferred. This discovery covers Intel temp-only for now.
    var tempPath = _drmHwmonTempPath(base + "/device/hwmon", listDir);
    return { vendor: "intel", busyPath: null, tempPath: tempPath };
}

function _nouveauInfo(base, listDir) {
    // nouveau (open-source NVIDIA driver) exposes a standard hwmon temp at the
    // DRM card's device/hwmon, same location as amdgpu/i915. Usage has no sysfs
    // counter (debugfs pstate is root-only), so this is temp-only — exactly the
    // _gpuTempAvailable-without-_gpuAvailable case MetricsBackend already
    // supports. Only reached when NVML is unavailable (issue #106).
    var tempPath = _drmHwmonTempPath(base + "/device/hwmon", listDir);
    return { vendor: "nouveau", busyPath: null, tempPath: tempPath };
}

// Walk /sys/class/drm/cardN/device/hwmon/ and return the `temp1_input` path
// inside the first hwmonN entry found, or null when the dir is empty or absent.
// The amdgpu and i915/xe drivers both expose a single hwmon device at this
// location with `temp1_input` as the junction/die temperature.
function _drmHwmonTempPath(hwmonBase, listDir) {
    var entries = listDir(hwmonBase) || [];
    for (var i = 0; i < entries.length; i++) {
        if (/^hwmon\d+$/.test(entries[i]))
            return hwmonBase + "/" + entries[i] + "/temp1_input";
    }
    return null;
}

// Convert a sysfs millidegrees-Celsius reading to °C. Non-numeric / empty
// input → NaN (callers coerce NaN to 0 at the public surface via _coerceTemp).
// Same formula as CpuTempDiscovery.parseTempCelsius.
function parseTempCelsius(raw) {
    if (raw === undefined || raw === null) return NaN;
    var n = parseInt(String(raw).trim(), 10);
    return isFinite(n) ? n / 1000 : NaN;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        VENDOR_AMD: VENDOR_AMD,
        VENDOR_INTEL: VENDOR_INTEL,
        VENDOR_NVIDIA: VENDOR_NVIDIA,
        discoverGpu: discoverGpu,
        parseTempCelsius: parseTempCelsius,
        _sortedDrmCards: _sortedDrmCards,
        _drmHwmonTempPath: _drmHwmonTempPath,
    };
}
