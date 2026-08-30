import QtQuick
import "BatteryStatus.js" as Battery
import "../../core/BatteryAggregate.js" as BatAgg

// Standalone battery source — counterpart of platforms/plasma/BatterySampler,
// satisfying the same `battery` surface from /sys/class/power_supply/BAT*/ via
// the injected ProcReader instead of ksysguard. Folds every battery into one
// ring value through the shared core/BatteryAggregate.
//
// Discovery is cached. The battery DIR set and each battery's capacity weight
// (energy_full / charge_full — design capacity, drifts on a wear timescale of
// months) are resolved once and reused, so a 2 Hz sample() reads only the live
// capacity + status files, not the whole power_supply tree. A battery-less
// desktop re-lists for a bounded warm-up window then stops, mirroring the
// CpuTemp / GpuSampler retry-then-settle discipline — no perpetual sysfs walk.
//
// `available` is a SCALAR written only when availability flips, so the backend's
// availableMetrics binding doesn't get a fresh `battery` object every poll and
// rebuild the whole ring strip at 2 Hz (the fixed-review-bug the sibling sensor
// inputs already avoid by reading NOTIFY-carrying scalars).
//
// Public surface (mirrors the Plasma adapter):
//   battery (readonly var)  — { percent: 0..100, charging, available }
//   available (readonly bool) — battery.available, change-gated for bindings
//   sample()                — per-tick work; the backend's 500 ms Timer calls it.

Item {
    id: sampler

    // Injected by MetricsBackend (not owned here) — same pattern as GpuSampler.
    property var reader

    readonly property var battery: sampler._battery
    property var _battery: ({
            percent: 0,
            charging: false,
            available: false
        })

    readonly property bool available: sampler._available
    property bool _available: false

    // Cached discovery: battery base dirs + per-dir capacity weight.
    property var _dirs: []
    property var _weights: ({})
    property int _discoverAttempts: 0
    readonly property int _maxDiscoverAttempts: 60  // ~30 s at 2 Hz

    function _discover() {
        var base = "/sys/class/power_supply";
        var entries = reader.listDir(base);
        var dirs = [];
        var weights = {};
        for (var i = 0; i < entries.length; i++) {
            if (!Battery.isBatteryDir(entries[i]))
                continue;
            var dir = base + "/" + entries[i];
            // energy_full preferred; charge_full is the fallback for batteries
            // that only expose charge (µAh) rather than energy (µWh).
            var weightRaw = reader.read(dir + "/energy_full");
            if (!weightRaw || !weightRaw.trim())
                weightRaw = reader.read(dir + "/charge_full");
            dirs.push(dir);
            weights[dir] = Battery.parseWeight(weightRaw);
        }
        sampler._dirs = dirs;
        sampler._weights = weights;
    }

    function sample() {
        // Re-list only while nothing has been found yet, bounded — a laptop
        // resolves on the first tick; a desktop stops after the warm-up window.
        if (sampler._dirs.length === 0 && sampler._discoverAttempts < sampler._maxDiscoverAttempts) {
            sampler._discoverAttempts++;
            _discover();
        }
        var records = [];
        for (var i = 0; i < sampler._dirs.length; i++) {
            var dir = sampler._dirs[i];
            var pct = Battery.parseCapacity(reader.read(dir + "/capacity"));
            if (!isFinite(pct))
                continue;
            records.push({
                "percent": pct,
                "weight": sampler._weights[dir],
                "charging": Battery.isCharging(reader.read(dir + "/status"))
            });
        }
        var agg = BatAgg.aggregate(records);
        sampler._battery = agg;
        if (agg.available !== sampler._available)
            sampler._available = agg.available;
    }
}
