// Vendor-agnostic CPU-temperature sensor discovery for the standalone
// build. On Plasma, KDE's ksystemstats already does this walk for us
// behind the `cpu/all/averageTemperature` sensor; this module is the
// in-house equivalent so the standalone backend can find the CPU
// temperature on any machine without a KDE dependency.
//
// The sysfs path of the CPU temperature is NOT fixed: the `hwmonN`
// numbering is allocation-order (so `coretemp` can be hwmon4 on one
// boot and hwmon2 on another), and which chip owns the CPU sensor
// depends on the vendor (Intel `coretemp`, AMD `k10temp` / `zenpower`,
// ARM `cpu_thermal`, …). So the backend enumerates the sysfs trees and
// asks these PURE functions which entry is the CPU — same split as
// ProcStatParser / MemInfoParser: the QML adapter does the I/O, the
// decisions live here and are Node-tested.
//
// Two sources, tried in order by the backend:
//   1. /sys/class/hwmon/hwmonN  — match `name` against CPU_HWMON_NAMES,
//      then pick the package/die temp input via its `tempN_label`.
//      This is what Conky / lm-sensors / KSysGuard use on x86.
//   2. /sys/class/thermal/thermal_zoneN — fallback for machines whose
//      CPU temp is only in the thermal framework (many ARM SBCs, some
//      VMs): match `type` against CPU_THERMAL_ZONE_TYPES.
//
// Dual-loaded by QML (`import "CpuTempDiscovery.js" as CpuTemp`) and
// Node (module.exports shim at the bottom). No `.pragma library`.

// hwmon chip `name` values that expose CPU core/package temperature,
// in detection-priority order (index = priority, lower wins). Union of
// the lists real monitors carry, so detection is vendor-agnostic:
var CPU_HWMON_NAMES = [
    "coretemp",      // Intel
    "k10temp",       // AMD K10 .. Zen (mainline driver)
    "zenpower",      // AMD Zen (out-of-tree alternative to k10temp)
    "k8temp",        // older AMD (K8)
    "fam15h_power",  // AMD family 15h
    "cpu_thermal",   // ARM SoC (devicetree thermal exposed as hwmon)
    "soc_thermal",   // ARM SoC
    // NOTE: acpitz is deliberately NOT in the hwmon list. It's a generic
    // ACPI thermal zone (often whole-board, least accurate) that almost
    // always ALSO surfaces under /sys/class/thermal as type "acpitz".
    // Listing it here would let it short-circuit the hwmon path and stop
    // the thermal-zone fallback from ever reaching a better CPU zone
    // (e.g. "x86_pkg_temp") on a machine that exposes both. So acpitz
    // lives only in CPU_THERMAL_ZONE_TYPES below — the last resort, after
    // the real CPU zones.
];

// thermal_zone `type` values for the CPU, priority order. Only consulted
// when no hwmon CPU chip matched (the hwmon path is preferred — it
// carries per-sensor labels the thermal framework lacks).
var CPU_THERMAL_ZONE_TYPES = [
    "x86_pkg_temp",  // Intel package temperature
    "cpu-thermal",   // ARM (Raspberry Pi and many devicetree SoCs)
    "cpu_thermal",
    "soc-thermal",
    "soc_thermal",
    "acpitz",        // fallback
];

// Convert a sysfs millidegrees-Celsius reading (hwmon `tempN_input` and
// thermal_zone `temp` are both millidegrees) to °C. Non-numeric / empty
// input → NaN, which the callers (Catalog.tempToPercent / convertTemp)
// already treat as "unavailable" → 0.
function parseTempCelsius(raw) {
    if (raw === undefined || raw === null) return NaN;
    var n = parseInt(String(raw).trim(), 10);
    if (!isFinite(n)) return NaN;
    return n / 1000;
}

// `tempN_input` matcher + index extractor — used to filter a hwmon
// directory listing down to its temperature inputs and to break ties
// by lowest sensor number.
function isTempInput(name) {
    return /^temp\d+_input$/.test(String(name));
}

function tempIndexFromInput(name) {
    var m = /^temp(\d+)_input$/.exec(String(name));
    return m ? parseInt(m[1], 10) : NaN;
}

// Rank a hwmon temperature label: prefer the whole-package/die readout
// (the number a user means by "CPU temperature") over per-core / per-CCD
// sensors. Lower rank wins; unlabelled / unknown labels fall to the end.
function _labelRank(label) {
    var l = String(label || "").toLowerCase();
    if (l.indexOf("package id") !== -1) return 0;  // Intel coretemp
    if (l.indexOf("tctl") !== -1) return 0;         // AMD control temp
    if (l.indexOf("tdie") !== -1) return 1;         // AMD die temp
    if (l.indexOf("tccd") !== -1) return 2;         // AMD per-CCD
    return 100;
}

// Pick the best CPU hwmon directory from enumerated { dir, name } pairs.
// Returns the `dir` of the highest-priority matching chip, or "" if no
// entry is a known CPU chip.
function pickCpuHwmonDir(entries) {
    if (!entries) return "";
    var best = null;
    for (var i = 0; i < entries.length; i++) {
        var name = String(entries[i].name || "").toLowerCase();
        var rank = CPU_HWMON_NAMES.indexOf(name);
        if (rank < 0) continue;
        if (best === null || rank < best.rank)
            best = { dir: entries[i].dir, rank: rank };
    }
    return best ? best.dir : "";
}
// Pick the best temperature input within one hwmon chip, from
// enumerated { input, label } pairs ("temp1_input" + its "temp1_label",
// label "" when the chip exposes no label file). Prefers package/die by
// label, breaks ties by lowest sensor index. Returns the input filename
// (e.g. "temp1_input") or "" when there is no temperature input.
function pickCpuTempInput(sensors) {
    if (!sensors) return "";
    var best = null;
    for (var i = 0; i < sensors.length; i++) {
        var s = sensors[i];
        if (!isTempInput(s.input)) continue;
        var rank = _labelRank(s.label);
        var idx = tempIndexFromInput(s.input);
        if (best === null || rank < best.rank || (rank === best.rank && idx < best.idx))
            best = { input: s.input, rank: rank, idx: idx };
    }
    return best ? best.input : "";
}

// Fallback path: pick the best CPU thermal_zone from enumerated
// { dir, type } pairs. Returns the `dir` (e.g. "thermal_zone3") or "".
function pickCpuThermalZone(zones) {
    if (!zones) return "";
    var best = null;
    for (var i = 0; i < zones.length; i++) {
        var type = String(zones[i].type || "").toLowerCase();
        var rank = CPU_THERMAL_ZONE_TYPES.indexOf(type);
        if (rank < 0) continue;
        if (best === null || rank < best.rank)
            best = { dir: zones[i].dir, rank: rank };
    }
    return best ? best.dir : "";
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        CPU_HWMON_NAMES: CPU_HWMON_NAMES,
        CPU_THERMAL_ZONE_TYPES: CPU_THERMAL_ZONE_TYPES,
        parseTempCelsius: parseTempCelsius,
        isTempInput: isTempInput,
        tempIndexFromInput: tempIndexFromInput,
        pickCpuHwmonDir: pickCpuHwmonDir,
        pickCpuTempInput: pickCpuTempInput,
        pickCpuThermalZone: pickCpuThermalZone,
    };
}
