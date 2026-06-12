// Pure ranking + formatting for the CPU-ring process tooltip (issue #69).
//
// Consumes already-normalised process records from EITHER platform adapter
// (Plasma `ProcessDataModel`, standalone `/proc/<pid>/stat`) and produces the
// sorted, capped, display-ready list the tooltip renders. The "total 0-100%"
// CPU normalisation happens at the source — the standalone `/proc` delta is
// intrinsically total-normalised (busy jiffies over the system-wide jiffy
// delta), and the Plasma adapter divides ksysguard's reading by the core count
// — so this module stays platform-agnostic and only ranks + formats.
//
// Record shape: { pid: int, name: string, cpuPercent: number, rssKb?: number }
// rssKb is OPTIONAL and unused in the v1 CPU tooltip: it's a forward hook for
// the companion RAM-ring tooltip, which will reuse this same enumeration and
// rank on rssKb instead. Keeping the field in the shape now means that issue
// adds a `rankByMemory` here rather than re-plumbing both backends.

var DEFAULT_LIMIT = 20;

// Coerce an arbitrary value to a finite, non-negative number (defends the
// ranking + formatting against undefined / NaN / negative readings that a
// transient sensor or a racing /proc read can hand us).
function _toNonNegative(value) {
    var n = Number(value);
    if (!isFinite(n) || n < 0)
        return 0;
    return n;
}

// Validate and normalise an array of raw process records. Drops non-objects
// and records missing pid. Coerces pid to Number (Plasma ProcessDataModel
// Value role isn't guaranteed numeric — a string pid would turn the
// a.pid - b.pid tiebreak into NaN, making the sort non-deterministic).
// Carries rssKb ONLY when the producer set it, preserving the "not sampled"
// vs "genuine 0 KB" distinction rankByMemory relies on.
function _cleanRecords(records) {
    var cleaned = [];
    for (var i = 0; i < records.length; i++) {
        var r = records[i];
        if (!r || r.pid === undefined || r.pid === null)
            continue;
        var rec = {
            pid: Number(r.pid),
            name: (r.name === undefined || r.name === null) ? "" : String(r.name),
            cpuPercent: _toNonNegative(r.cpuPercent)
        };
        if (r.rssKb !== undefined && r.rssKb !== null)
            rec.rssKb = _toNonNegative(r.rssKb);
        cleaned.push(rec);
    }
    return cleaned;
}

// Sort `records` by cpuPercent descending and cap to `limit`. Returns a NEW
// array (never mutates the input). Ties break by pid ascending so the order is
// deterministic across ticks — without it two equal-CPU rows could swap places
// every refresh and make the tooltip flicker. Invalid records (non-objects,
// missing pid) are dropped.
function rankByCpu(records, limit) {
    var cap = (limit === undefined) ? DEFAULT_LIMIT : limit;
    if (!Array.isArray(records) || cap <= 0)
        return [];
    var cleaned = _cleanRecords(records);
    cleaned.sort(function (a, b) {
        if (b.cpuPercent !== a.cpuPercent)
            return b.cpuPercent - a.cpuPercent;
        return a.pid - b.pid;
    });
    return cleaned.slice(0, cap);
}

// Sort `records` by rssKb descending and cap to `limit`. Returns a NEW array
// (never mutates the input). Records with absent rssKb rank as 0 (kept, not
// dropped — the backend may not sample memory for every tick). Ties break by
// pid ascending for the same flicker-prevention reason as rankByCpu.
function rankByMemory(records, limit) {
    var cap = (limit === undefined) ? DEFAULT_LIMIT : limit;
    if (!Array.isArray(records) || cap <= 0)
        return [];
    var cleaned = _cleanRecords(records);
    cleaned.sort(function (a, b) {
        var aKb = (a.rssKb !== undefined) ? a.rssKb : 0;
        var bKb = (b.rssKb !== undefined) ? b.rssKb : 0;
        if (bKb !== aKb)
            return bKb - aKb;
        return a.pid - b.pid;
    });
    return cleaned.slice(0, cap);
}

// "12.3%" — one decimal, the precision `top` shows for %CPU. Defends against
// undefined / NaN / negative (→ "0.0%").
function formatCpuPercent(value) {
    return _toNonNegative(value).toFixed(1) + "%";
}

// The three kernel load averages (1 / 5 / 15 min) formatted for the tooltip
// footer, e.g. [0.42, 0.55, 0.61] → "0.42  0.55  0.61". The "Load average:"
// label is added (and translated) by the QML caller. Two decimals matches
// `uptime` / `top`. A short or missing array pads with "0.00" so the footer
// never renders "undefined".
function formatLoadAverages(loads) {
    var arr = Array.isArray(loads) ? loads : [];
    var out = [];
    for (var i = 0; i < 3; i++)
        out.push(_toNonNegative(arr[i]).toFixed(2));
    return out.join("  ");
}

// Humanise a KiB count for the RAM-tooltip value column. Boundaries: <1024 KiB
// stays KiB (integer), <1024 MiB shows MiB (one decimal), else GiB (one
// decimal). One decimal for MiB/GiB matches what `top` shows for %MEM at the
// precision the tooltip needs; integers for sub-MiB avoids ".0 KiB" noise.
function formatMemory(rssKb) {
    var kb = _toNonNegative(rssKb);
    if (kb < 1024)
        return Math.round(kb) + " KiB";
    var mb = kb / 1024;
    if (mb < 1024)
        return mb.toFixed(1) + " MiB";
    return (mb / 1024).toFixed(1) + " GiB";
}

// "(rssKb / totalKb) * 100" formatted to one decimal + "%" — matches `top`'s
// %MEM precision. Guards: totalKb not finite or <= 0 → "0.0%"; clamped at 100%
// so a transient rss spike above total (e.g. during a fork-bomb) doesn't show
// ">100%".
function formatMemPercent(rssKb, totalKb) {
    var total = Number(totalKb);
    if (!isFinite(total) || total <= 0)
        return "0.0%";
    var pct = (_toNonNegative(rssKb) / total) * 100;
    if (pct > 100)
        pct = 100;
    return pct.toFixed(1) + "%";
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        DEFAULT_LIMIT: DEFAULT_LIMIT,
        rankByCpu: rankByCpu,
        rankByMemory: rankByMemory,
        formatCpuPercent: formatCpuPercent,
        formatLoadAverages: formatLoadAverages,
        formatMemory: formatMemory,
        formatMemPercent: formatMemPercent,
    };
}
