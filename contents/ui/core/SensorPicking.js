// Pure picking helpers for "list of candidate sensors, return the
// first one that's ready" patterns.
//
// The Plasma backend uses this to merge an aggregate (`gpu/all/usage`)
// with per-device fallbacks (`gpu/gpuN/usage`): try the aggregate
// first, fall back to any per-device sensor that resolved. The
// standalone backend will hit the same pattern when probing across
// hwmon paths or DRM cards — the algorithm is portable, only the
// definition of "ready" differs per platform.
//
// Public surface:
//   pickFirstReadyValue(candidates) — first {ready:true} candidate's
//                                     value (|| 0), or 0 if none.
//
// `candidates` is an array of objects with shape `{ready: bool,
// value: number}`. Null / undefined entries are skipped so callers
// can build the list with `if (s) candidates.push(...)` without an
// extra filter pass.
//
// Dual-loaded by QML (`import "SensorPicking.js" as SensorPicking`)
// and Node (via the module.exports shim at the bottom).

function pickFirstReadyValue(candidates) {
    if (!candidates || !candidates.length)
        return 0;
    for (var i = 0; i < candidates.length; i++) {
        var c = candidates[i];
        if (c && c.ready)
            return c.value || 0;
    }
    return 0;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        pickFirstReadyValue: pickFirstReadyValue,
    };
}
