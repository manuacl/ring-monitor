// Pure parsers for the standalone CPU-ring process tooltip (issue #69):
// `/proc/<pid>/stat` (per-process CPU jiffies), `/proc/loadavg`, and the
// per-process CPU% delta math. Standalone-only — the Plasma adapter gets the
// same data from `org.kde.ksysguard.process` `ProcessDataModel`, so this lives
// beside the standalone adapter, not in `core/` (placement rule:
// `platforms/standalone/CLAUDE.md`). Ranking + display formatting is the shared
// `core/ProcessRanking.js`; this module only turns /proc bytes into records.
//
// Self-contained on purpose: the dual-load convention (Node `--test` + QML)
// forbids a `.js` importing a sibling `.js`, so `sumJiffies` is duplicated here
// rather than reaching into `ProcStatParser.js`.

// `/proc/<pid>/stat` → { pid, name, jiffies, rssPages } or null if unparseable.
//
//   pid (comm) state ppid ... utime stime cutime cstime ... rss ...
//
// Two traps the naive `split(" ")` falls into, both handled here:
//   - `comm` (field 2) is wrapped in parens and can itself contain spaces
//     AND parens (e.g. "(Web Content)", "((sd-pam))"). Split on the LAST
//     ")" so an embedded ")" never shifts the field offsets.
//   - utime (field 14) + stime (field 15) are the process's own user/kernel
//     jiffies; cutime/cstime (children) are deliberately excluded, matching
//     `top`'s default (a process isn't "using" CPU its dead children spent).
// After the comm, the remaining tokens start at `state` (field 3), so
// field N lives at index N-3: utime → [11], stime → [12], rss → [21]
// (field 24, resident set size in pages — the QML sampler multiplies by
// pageSize() to convert to KiB; the parser stays unit-free).
// A missing or non-finite rss degrades to 0 rather than returning null:
// utime/stime validity already gates the record, and a truncated rss
// must not hide the process from the CPU ranking.
function parsePidStat(raw) {
    if (typeof raw !== "string")
        return null;
    var open = raw.indexOf("(");
    var close = raw.lastIndexOf(")");
    if (open < 0 || close < 0 || close < open)
        return null;
    var pid = parseInt(raw.substring(0, open), 10);
    if (!isFinite(pid))
        return null;
    var name = raw.substring(open + 1, close);
    var rest = raw.substring(close + 1).trim().split(/\s+/);
    var utime = parseInt(rest[11], 10);
    var stime = parseInt(rest[12], 10);
    if (!isFinite(utime) || !isFinite(stime))
        return null;
    var rssRaw = parseInt(rest[21], 10);
    var rssPages = (isFinite(rssRaw) && rssRaw >= 0) ? rssRaw : 0;
    return { pid: pid, name: name, jiffies: utime + stime, rssPages: rssPages };
}

// `/proc/loadavg` → [load1, load5, load15]. The line is
// "0.42 0.55 0.61 1/938 12345"; only the first three tokens matter.
// Missing / malformed tokens degrade to 0 so the footer never shows NaN.
function parseLoadAvg(raw) {
    if (typeof raw !== "string")
        return [0, 0, 0];
    var p = raw.trim().split(/\s+/);
    var out = [];
    for (var i = 0; i < 3; i++) {
        var n = parseFloat(p[i]);
        out.push(isFinite(n) ? n : 0);
    }
    return out;
}

// Sum of an aggregate-cpu jiffy-field array (the `all` array from
// ProcStatParser.parseProcStat) — the system-wide total jiffies. The
// denominator for the "total 0-100%" per-process normalisation: a process's
// jiffy delta over the WHOLE machine's jiffy delta, so a single core pegged on
// an 8-core box reads ~12.5%, and the rows sum toward the aggregate ring.
function sumJiffies(fields) {
    if (!Array.isArray(fields))
        return 0;
    var total = 0;
    for (var i = 0; i < fields.length; i++) {
        var n = Number(fields[i]);
        if (isFinite(n))
            total += n;
    }
    return total;
}

// Per-process CPU% over the interval between two pid→record snapshots.
// `prevMap` / `curMap` are { pid: { pid, name, jiffies } } maps;
// `totalJiffiesDelta` is sumJiffies(cur.all) - sumJiffies(prev.all) for the
// SAME interval. Returns un-ranked records [{ pid, name, cpuPercent }] for
// every pid present in BOTH snapshots (a brand-new pid has no prior sample to
// delta against — it appears next tick). Sorting + the top-N cap are the
// caller's job (core/ProcessRanking.rankByCpu).
function computePercents(prevMap, curMap, totalJiffiesDelta) {
    var out = [];
    if (!prevMap || !curMap || !(totalJiffiesDelta > 0))
        return out;
    for (var pid in curMap) {
        if (!Object.prototype.hasOwnProperty.call(curMap, pid))
            continue;
        var prev = prevMap[pid];
        if (!prev)
            continue;
        var cur = curMap[pid];
        var dj = cur.jiffies - prev.jiffies;
        if (dj < 0)
            dj = 0;  // pid reused or counter reset between samples
        var pct = dj / totalJiffiesDelta * 100;
        if (pct > 100)
            pct = 100;
        out.push({ pid: cur.pid, name: cur.name, cpuPercent: pct });
    }
    return out;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        parsePidStat: parsePidStat,
        parseLoadAvg: parseLoadAvg,
        sumJiffies: sumJiffies,
        computePercents: computePercents
    };
}
