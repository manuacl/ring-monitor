// Pure parser for `/proc/stat`. Standalone-build companion to the
// KSysGuard sensor model used by the Plasma adapter.
//
// `/proc/stat` exposes CPU activity as monotonic tick counters per
// core. To get a usage percentage you need two samples a moment apart
// and the delta of (total - idle) over the delta of total.
//
// Sample first line (kernel 6.x):
//
//   cpu  3357 0 4313 1362393 234 0 0 0 0 0
//
// Fields in order: user, nice, system, idle, iowait, irq, softirq,
// steal, guest, guest_nice. Older kernels omit later fields. The
// canonical formula:
//
//   total       = sum of all numeric fields
//   idle_time   = idle + iowait
//   usage%      = (1 - (idle_delta / total_delta)) * 100
//
// Dual-loaded by QML and Node (the standard `module.exports` shim at
// the bottom mirrors every other module under `core/`).
//
// Public surface:
//   parseProcStat(content) - {all, cores}, both arrays of tick fields;
//                            cores is index-ordered.
//   percentFromSample(prev, cur) - usage % over the interval; safe
//                                  against zero deltas and NaN.

function parseProcStat(content) {
    var out = {
        "all": null,
        "cores": []
    };
    if (typeof content !== "string" || content.length === 0)
        return out;
    var lines = content.split("\n");
    var coreMap = {};
    // Outer gate: only `cpu` (aggregate) and `cpuN` (per-core) lines
    // are kept. `/proc/stat` also contains `cpufreq`, `cpu_avg_freq`,
    // and other `cpu`-prefixed metadata on some platforms (and the
    // kernel could add more). Without the `\b` boundary check, those
    // lines used to enter the inner parser, parseInt their fields,
    // and only get discarded later because no branch claimed them —
    // wasted work per tick. The regex is the same one used to extract
    // the per-core index, factored out so the inner block doesn't
    // need to re-test.
    var cpuLineRe = /^cpu(\d*)\b/;
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        var lineMatch = line.match(cpuLineRe);
        if (!lineMatch)
            continue;
        var parts = line.split(/\s+/);
        var head = parts[0];
        var fields = [];
        for (var j = 1; j < parts.length; j++) {
            var n = parseInt(parts[j], 10);
            fields.push(isNaN(n) ? 0 : n);
        }
        if (head === "cpu") {
            out.all = fields;
        } else if (lineMatch[1].length > 0) {
            coreMap[parseInt(lineMatch[1], 10)] = fields;
        }
    }
    var indices = Object.keys(coreMap).map(Number).sort(function (a, b) {
        return a - b;
    });
    for (var k = 0; k < indices.length; k++)
        out.cores.push(coreMap[indices[k]]);
    return out;
}

function percentFromSample(prev, cur) {
    if (!prev || !cur || prev.length === 0 || cur.length === 0)
        return 0;
    var prevTotal = 0;
    var curTotal = 0;
    for (var i = 0; i < prev.length; i++)
        prevTotal += prev[i];
    for (var j = 0; j < cur.length; j++)
        curTotal += cur[j];
    var dTotal = curTotal - prevTotal;
    if (dTotal <= 0)
        return 0;
    // idle + iowait — both count as "not doing useful work".
    var prevIdle = (prev[3] || 0) + (prev[4] || 0);
    var curIdle = (cur[3] || 0) + (cur[4] || 0);
    var dIdle = curIdle - prevIdle;
    var usage = (1 - dIdle / dTotal) * 100;
    if (usage < 0)
        return 0;
    if (usage > 100)
        return 100;
    return usage;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        parseProcStat: parseProcStat,
        percentFromSample: percentFromSample
    };
}
