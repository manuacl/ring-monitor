// Pure helpers for the per-partition disk ring colors (shared by both
// platforms; issue #67).
//
// Each selected filesystem can carry its OWN ring color, stored as a JSON
// map of partition id (UUID) → color string ("#rrggbb"). A partition with
// no entry inherits the shared ring color — so "disabling" a custom color
// is just removing the partition's entry from the map (back to the general
// widget color). One fixed color per disk (no light/dark pair): the chosen
// color is used as-is in both schemes; partitions without an override still
// track the live light/dark scheme through the shared fallback.
//
// The map is written from the config picker (MetricsBody via PartitionRow)
// and read at render time (MainContent → Ring.equalColors). Same parse/
// serialize shape as DiskMetrics' label cache: tolerant of empty/malformed
// JSON, sorted-key serialization so an unchanged map re-serializes to the
// SAME string (no spurious config write).
//
// Dual-loaded by QML (`import "DiskColors.js" as DiskColors`) and Node.
// No `.pragma library`.
//
// Public surface:
//   parseColors(json)              - JSON → {id: "#rrggbb"} map, {} on empty/bad
//   serializeColors(obj)           - map → sorted-key JSON string
//   colorFor(json, id)             - the stored color for id, or "" if unset
//   withColor(json, id, color)     - new JSON with id set to color (immutable)
//   withoutColor(json, id)         - new JSON with id removed (immutable)
//   resolveRingColors(ids, json, fallback)
//                                  - array aligned to ids: the stored color
//                                    when set, else `fallback` (the shared
//                                    ring color). Drives Ring.equalColors.

function parseColors(json) {
    if (!json)
        return {};
    try {
        var obj = JSON.parse(json);
        return (obj && typeof obj === "object" && !Array.isArray(obj)) ? obj : {};
    } catch (e) {
        return {};
    }
}

// Sorted keys so an unchanged map always produces the SAME string —
// assigning it back to the bridged property is then a no-op and doesn't
// trigger a spurious config write.
function serializeColors(obj) {
    obj = obj || {};
    var keys = Object.keys(obj).sort();
    var ordered = {};
    for (var i = 0; i < keys.length; i++)
        ordered[keys[i]] = obj[keys[i]];
    return JSON.stringify(ordered);
}

// The stored color for `id`, or "" when none is set (caller falls back to
// the shared ring color). Guards against a non-string value from a
// hand-edited config.
function colorFor(json, id) {
    var map = parseColors(json);
    var c = map[id];
    return (typeof c === "string" && c.length > 0) ? c : "";
}

function withColor(json, id, color) {
    var map = parseColors(json);
    map[id] = String(color);
    return serializeColors(map);
}

function withoutColor(json, id) {
    var map = parseColors(json);
    if (Object.prototype.hasOwnProperty.call(map, id))
        delete map[id];
    return serializeColors(map);
}

// One color per id, aligned to the `ids` array (the rendered disk ring set,
// outermost first): the stored override when present, else `fallback`. The
// fallback is the shared ring color resolved by the caller, so a partition
// without an override matches every other ring (and tracks light/dark).
function resolveRingColors(ids, json, fallback) {
    ids = ids || [];
    var map = parseColors(json);
    var out = [];
    for (var i = 0; i < ids.length; i++) {
        var c = map[ids[i]];
        out.push((typeof c === "string" && c.length > 0) ? c : fallback);
    }
    return out;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        parseColors: parseColors,
        serializeColors: serializeColors,
        colorFor: colorFor,
        withColor: withColor,
        withoutColor: withoutColor,
        resolveRingColors: resolveRingColors,
    };
}
