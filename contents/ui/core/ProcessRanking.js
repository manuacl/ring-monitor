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

// Sort `records` by cpuPercent descending and cap to `limit`. Returns a NEW
// array (never mutates the input). Ties break by pid ascending so the order is
// deterministic across ticks — without it two equal-CPU rows could swap places
// every refresh and make the tooltip flicker. Invalid records (non-objects,
// missing pid) are dropped.
function rankByCpu(records, limit) {
    var cap = (limit === undefined) ? DEFAULT_LIMIT : limit;
    if (!Array.isArray(records) || cap <= 0)
        return [];
    var cleaned = [];
    for (var i = 0; i < records.length; i++) {
        var r = records[i];
        if (!r || r.pid === undefined || r.pid === null)
            continue;
        // Coerce pid to a Number so the tiebreak (a.pid - b.pid) stays numeric
        // even if a backend hands it as a string (the Plasma ProcessDataModel
        // Value role isn't guaranteed numeric); a NaN compare there would make
        // the sort non-deterministic — the flicker the tiebreak exists to stop.
        var rec = {
            pid: Number(r.pid),
            name: (r.name === undefined || r.name === null) ? "" : String(r.name),
            cpuPercent: _toNonNegative(r.cpuPercent)
        };
        // rssKb is the optional RAM-tooltip forward hook — carry it ONLY when
        // the producer actually set it, so a future rankByMemory can tell
        // "not sampled" (absent) from a genuine 0 KB. v1 never sets it.
        if (r.rssKb !== undefined && r.rssKb !== null)
            rec.rssKb = _toNonNegative(r.rssKb);
        cleaned.push(rec);
    }
    cleaned.sort(function (a, b) {
        if (b.cpuPercent !== a.cpuPercent)
            return b.cpuPercent - a.cpuPercent;
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

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        DEFAULT_LIMIT: DEFAULT_LIMIT,
        rankByCpu: rankByCpu,
        formatCpuPercent: formatCpuPercent,
        formatLoadAverages: formatLoadAverages,
    };
}
