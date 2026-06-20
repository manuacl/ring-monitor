// Pure parse helpers for /sys/class/power_supply/BAT*/ sysfs files.
//
// The standalone MetricsBackend does the I/O (ProcReader.read + listDir);
// these functions decide which entries are batteries and what their
// parsed values mean. Same split as CpuTempDiscovery / ProcStatParser:
// no file I/O here, only string-to-value conversions.
//
// /sys/class/power_supply/ mixes battery nodes (BAT0, BAT1, …) with AC
// adapter nodes (AC, ADP0, ADP1, mains, …). The backend lists the dir
// and asks isBatteryDir to filter; for each battery it reads the
// `capacity`, `status`, and `energy_full`/`charge_full` files and asks
// the remaining helpers to parse them.
//
// Dual-loaded by QML (`import "BatteryStatus.js" as BatteryStatus`) and
// Node (module.exports shim at the bottom). No `.pragma library`.
//
// Public surface:
//   isBatteryDir(name)     — boolean, true for BAT0/BAT1/…
//   parseCapacity(raw)     — integer 0..100, or NaN
//   isCharging(statusRaw)  — boolean (Charging OR Full)
//   parseWeight(raw)       — positive finite number, or 1 as fallback

// Lookup table for status strings that count as "charging". Keys are
// lower-cased trimmed values; "full" is included because a full battery
// is plugged-in and at 100% — treating it as not-charging would leave
// the ring showing a non-charging state at 100%.
var CHARGING_STATUS = {
    "charging": true,
    "full":     true,
};

// True when the power_supply directory name looks like a battery.
// BAT0, BAT1, BAT_MAIN, etc. — case-insensitive prefix match.
// AC adapter names (AC, ADP0, ADP1, ADP1-1, mains, USB) return false.
function isBatteryDir(name) {
    return /^BAT/i.test(String(name));
}

// Parse the integer percent from the `capacity` sysfs file.
// Returns an integer clamped to [0, 100], or NaN for empty / garbage input.
// The file contains a single decimal integer (possibly with a trailing newline);
// some buggy ECs report out-of-range values (e.g. 105), so the clamp keeps the
// documented contract true at the parse boundary rather than relying on a single
// downstream clamp in BatteryAggregate (a multi-battery weighted mean would
// otherwise be skewed by an out-of-range member before that final clamp).
function parseCapacity(raw) {
    if (raw === undefined || raw === null) return NaN;
    var n = parseInt(String(raw).trim(), 10);
    if (!isFinite(n)) return NaN;
    if (n < 0) return 0;
    if (n > 100) return 100;
    return n;
}

// True when the `status` sysfs file indicates the battery is charging or full.
// The kernel writes one of: "Charging", "Discharging", "Not charging",
// "Full", "Unknown" (or "" on some firmware). Case-insensitive.
function isCharging(statusRaw) {
    if (statusRaw === undefined || statusRaw === null) return false;
    var key = String(statusRaw).trim().toLowerCase();
    return CHARGING_STATUS[key] === true;
}

// Parse the design or last-known-good capacity from `energy_full` or
// `charge_full` (both are single integers in µWh / µAh respectively;
// the unit doesn't matter here — only the relative magnitude is used
// as a weight). Returns the raw integer, or 1 when the file is absent,
// empty, or contains garbage — so weighting degrades to a simple mean.
function parseWeight(raw) {
    if (raw === undefined || raw === null) return 1;
    var n = parseInt(String(raw).trim(), 10);
    if (!isFinite(n) || n <= 0) return 1;
    return n;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        isBatteryDir: isBatteryDir,
        parseCapacity: parseCapacity,
        isCharging: isCharging,
        parseWeight: parseWeight,
    };
}
