// Pure parser for `/proc/meminfo` plus the small percent helper that
// MemInfo and statvfs (disk) both feed. Standalone-build companion to
// the KSysGuard `memory/*` and `disk/all/usedPercent` sensors used by
// the Plasma adapter.
//
// Sample (kernel 6.x — first lines are all this parser cares about):
//
//   MemTotal:       16275216 kB
//   MemFree:         2121540 kB
//   MemAvailable:    9029768 kB
//   ...
//
// Why `MemAvailable` and not `MemTotal - MemFree`: `MemFree` ignores
// buffers/cache, which the kernel can reclaim on demand — using it
// reports 90%+ "used" on every machine with a healthy page cache.
// `MemAvailable` (kernel >= 3.14) is the kernel's own estimate of
// what an allocator can actually grab without swapping, which is what
// users mean by "free memory". Same convention as `free -h` and
// every Plasma/GNOME RAM widget.
//
// Dual-loaded by QML and Node (the standard `module.exports` shim at
// the bottom mirrors every other module under `core/`).
//
// Public surface:
//   parseMemInfo(content)         - { total, available } in kB, or
//                                   nulls on missing/malformed input.
//   usagePercent(total, available) - (1 - available/total) * 100,
//                                    clamped to [0, 100]; 0 when total
//                                    is missing/zero. Used by the RAM
//                                    path where `available` already
//                                    accounts for reclaimable cache
//                                    (`MemAvailable` in /proc/meminfo).
//   diskUsagePercent(total, free, available)
//                                  - df(1)'s "Use%" formula:
//                                    (total - free) / (total - free +
//                                    available). Differs from
//                                    usagePercent on filesystems with
//                                    a root reservation (ext4: 5%) —
//                                    treating the reserved blocks as
//                                    "size invisible to the user"
//                                    matches df's output and avoids
//                                    reporting ~5% used on an empty
//                                    freshly-formatted ext4 root.
//                                    Clamped to [0, 100]; 0 when total
//                                    is missing/zero.

function parseMemInfo(content) {
    var out = {
        "total": null,
        "available": null
    };
    if (typeof content !== "string" || content.length === 0)
        return out;
    var lines = content.split("\n");
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        var m = line.match(/^(MemTotal|MemAvailable):\s+(\d+)\s+kB/);
        if (!m)
            continue;
        var value = parseInt(m[2], 10);
        if (isNaN(value))
            continue;
        if (m[1] === "MemTotal")
            out.total = value;
        else
            out.available = value;
    }
    return out;
}

function usagePercent(total, available) {
    if (!total || total <= 0)
        return 0;
    if (typeof available !== "number" || isNaN(available))
        return 0;
    var used = total - available;
    var pct = (used / total) * 100;
    if (pct < 0)
        return 0;
    if (pct > 100)
        return 100;
    return pct;
}

function diskUsagePercent(total, free, available) {
    if (!total || total <= 0)
        return 0;
    if (typeof free !== "number" || isNaN(free))
        return 0;
    if (typeof available !== "number" || isNaN(available))
        return 0;
    var used = total - free;
    var denom = used + available;
    if (denom <= 0)
        return 0;
    var pct = (used / denom) * 100;
    if (pct < 0)
        return 0;
    if (pct > 100)
        return 100;
    return pct;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        parseMemInfo: parseMemInfo,
        usagePercent: usagePercent,
        diskUsagePercent: diskUsagePercent
    };
}
