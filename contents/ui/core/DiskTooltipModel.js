// Pure presentational logic for the disk-ring hover tooltip (issue #68).
// Both platform backends expose the same per-partition detail object, and the
// view (DiskTooltip.qml) stays thin: it repeats over buildRows()'s output and
// renders strings. All formatting + composition is here so it's tested once.
//
// Shared by both platforms → lives in core/. (The view picks the per-ring
// color from the aligned _diskColors array; color isn't threaded through here
// because a QML `color` isn't a plain JS value.)
//
// partitionDetail(id) contract (what PR2's backends return, one object):
//   { id, label, mountpoint, fstype, usedPercent, totalBytes, freeBytes,
//     removable }
//   - usedPercent: the SAME number the ring is drawn from (ksysguard
//     usedPercent on Plasma, df-formula on standalone) — NOT recomputed from
//     bytes, so the tooltip can't disagree with the gauge (issue #68 note).
//   - totalBytes / freeBytes: capacity in bytes; used = total - free. 0/absent
//     when the source hasn't resolved yet → the byte figures are dropped and
//     only the % shows (graceful degrade).
//
// Public surface:
//   formatSize(bytes)                          - "56 GiB" (IEC binary, df -h style)
//   composeUsage(usedPercent, used, total)     - "12% — 56 GiB / 466 GiB"
//   composeFree(freeBytes, totalBytes)         - "120 GiB free"
//   subLabel(mountpoint, fstype)               - "/ · btrfs"
//   iconFor(removable)                         - freedesktop icon name
//   buildRows(details)                         - [{ id, label, subLabel,
//                                                 usageText, freeText,
//                                                 iconName, removable }]

// IEC binary units (KiB = 1024 B). Capacity follows the Dolphin / `df -h`
// convention (binary), deliberately NOT the SI 10^3 steps DiskIoScale uses for
// I/O *rate* — size and throughput are different unit families.
var SIZE_UNITS = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"];

function _finite(n) {
    n = Number(n);
    return isFinite(n) ? n : 0;
}

// "56 GiB" / "466 GiB" / "9.3 GiB" / "1.5 TiB" / "512 B" / "0 B".
// One decimal only below 10 (so a 1.5 GiB sliver stays legible) and integer
// above (466, not 466.0 — noise at that magnitude), matching `df -h`.
function formatSize(bytes) {
    var b = _finite(bytes);
    if (b < 0)
        b = 0;
    var i = 0;
    while (b >= 1024 && i < SIZE_UNITS.length - 1) {
        b /= 1024;
        i++;
    }
    // Promote at the rounding boundary so 1023.7 GiB renders "1.0 TiB", never
    // "1024 GiB" (the while only steps on a true >= 1024).
    if (i < SIZE_UNITS.length - 1 && b >= 1023.5) {
        b /= 1024;
        i++;
    }
    var n;
    if (i === 0)
        n = String(Math.round(b));      // whole bytes
    else
        n = b < 10 ? b.toFixed(1) : String(Math.round(b));
    return n + " " + SIZE_UNITS[i];
}

function _percentText(usedPercent) {
    var p = _finite(usedPercent);
    if (p < 0)
        p = 0;
    return Math.round(p) + "%";
}

// "12% — 56 GiB / 466 GiB", or just "12%" when total is unknown (bytes source
// not yet resolved) — the % always shows, the figures only when they exist.
function composeUsage(usedPercent, usedBytes, totalBytes) {
    var pct = _percentText(usedPercent);
    if (_finite(totalBytes) <= 0)
        return pct;
    return pct + " — " + formatSize(usedBytes) + " / " + formatSize(totalBytes);
}

// "120 GiB free". Empty when the byte source hasn't resolved (total unknown),
// so the view can hide the line rather than show a misleading "0 B free".
function composeFree(freeBytes, totalBytes) {
    if (_finite(totalBytes) <= 0)
        return "";
    return formatSize(freeBytes) + " free";
}

// "/ · btrfs", or just one when the other is missing, or "" when both are.
function subLabel(mountpoint, fstype) {
    var mp = mountpoint || "";
    var fs = fstype || "";
    if (mp && fs)
        return mp + " · " + fs;
    return mp || fs;
}

// Freedesktop icon names (resolved by ThemedIcon → Kirigami.Icon). Distinguishes
// an auto-shown removable from a manually-pinned fixed disk.
function iconFor(removable) {
    return removable ? "drive-removable-media" : "drive-harddisk";
}

function buildRows(details) {
    if (!Array.isArray(details))
        return [];
    return details.map(function (d) {
        d = d || {};
        var total = _finite(d.totalBytes);
        var free = _finite(d.freeBytes);
        var used = total - free;
        if (used < 0)
            used = 0;
        return {
            "id": d.id || "",
            "label": d.label || (d.id || ""),
            "subLabel": subLabel(d.mountpoint, d.fstype),
            "usageText": composeUsage(d.usedPercent, used, total),
            "freeText": composeFree(free, total),
            "iconName": iconFor(!!d.removable),
            "removable": !!d.removable
        };
    });
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        formatSize: formatSize,
        composeUsage: composeUsage,
        composeFree: composeFree,
        subLabel: subLabel,
        iconFor: iconFor,
        buildRows: buildRows
    };
}
