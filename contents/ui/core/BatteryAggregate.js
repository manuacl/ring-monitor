// Shared battery aggregation — combines multiple batteries into one ring value.
//
// Both the Plasma and standalone backends expose one or more battery records;
// this module folds them into a single { percent, charging, available } result
// so the ring binding is identical on both platforms.
//
// Shared by BOTH platform backends (lives in core/): the Plasma adapter reads
// org.kde.solid / UPower D-Bus sensors, the standalone adapter parses
// /sys/class/power_supply/BAT*/ via BatteryStatus.js — but the combination
// logic is the same, so it is written and tested once here.
//
// Dual-loaded by QML (`import "BatteryAggregate.js" as BatteryAggregate`) and
// Node (module.exports shim at the bottom). No `.pragma library`.
//
// Public surface:
//   aggregate(records)  — { percent, charging, available }

// Weighted mean of record.percent values, using record.weight as the weight.
// Falls back to a simple arithmetic mean when total weight is 0 or any weight
// is non-finite — degraded weighting is still a useful result.
function _weightedPercent(valid) {
    var totalWeight = 0;
    for (var i = 0; i < valid.length; i++) {
        var w = valid[i].weight;
        if (typeof w === "number" && isFinite(w) && w > 0) {
            totalWeight += w;
        }
    }

    var sum = 0;
    var count = valid.length;

    if (totalWeight > 0) {
        // Weighted mean path.
        for (var j = 0; j < valid.length; j++) {
            var wj = valid[j].weight;
            var effectiveW = (typeof wj === "number" && isFinite(wj) && wj > 0) ? wj : 0;
            sum += valid[j].percent * (effectiveW / totalWeight);
        }
        return sum;
    }

    // Fallback: simple arithmetic mean (total weight was 0 or weights missing).
    for (var k = 0; k < valid.length; k++) {
        sum += valid[k].percent;
    }
    return sum / count;
}

// Combine an array of { percent, weight, charging } records into one ring value.
// Returns { percent: number, charging: boolean, available: boolean }.
//
// available  — true only when records is a non-empty array of valid entries.
// percent    — weight-weighted mean, clamped to [0, 100]. Records with
//              non-finite percent are ignored; if all are invalid, available=false.
// charging   — true if ANY record reports charging (laptop plugged in).
function aggregate(records) {
    if (!records || typeof records.length !== "number" || records.length === 0) {
        return { percent: 0, charging: false, available: false };
    }

    var valid = [];
    var anyCharging = false;

    for (var i = 0; i < records.length; i++) {
        var r = records[i];
        if (!r) continue;
        if (typeof r.percent !== "number" || !isFinite(r.percent)) continue;
        valid.push(r);
        if (r.charging === true) anyCharging = true;
    }

    if (valid.length === 0) {
        return { percent: 0, charging: false, available: false };
    }

    var raw = _weightedPercent(valid);
    var clamped = raw < 0 ? 0 : (raw > 100 ? 100 : raw);

    return { percent: clamped, charging: anyCharging, available: true };
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        aggregate: aggregate,
    };
}
