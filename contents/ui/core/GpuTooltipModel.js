// Pure presentational logic for the GPU-ring hover tooltip (issue #71).
// Both platform backends expose the same per-device detail object, and the
// view (GpuTooltip.qml) stays thin: it iterates buildStatRows()'s output and
// renders strings. All formatting + composition is here so it's tested once.
//
// Shared by both platforms → lives in core/. (Color isn't threaded through
// here because a QML `color` isn't a plain JS value.)
//
// gpuDetail contract (one object per GPU device):
//   { model, usagePercent, vramUsedBytes, vramTotalBytes,
//     tempC, powerW, clockMhz }
//   - model: display name string (e.g. "NVIDIA RTX 4090"). May be absent.
//   - usagePercent: 0-100 GPU shader/engine busy %. NVIDIA: present.
//     AMD: present via ROCm/hwmon. Intel: sparse.
//   - vramUsedBytes / vramTotalBytes: capacity in bytes. Both may be absent
//     independently — composeVram renders only when total is known.
//   - tempC: junction/hotspot temperature in °C. NVIDIA + AMD: present.
//     Intel: often absent (no dedicated junction sensor).
//   - powerW: current draw in watts. NVIDIA: present. AMD: present when
//     hwmon power1_input exposed. Intel: typically absent.
//   - clockMhz: current shader-clock in MHz. NVIDIA: present. AMD: varies.
//     Intel: often absent.
//   Every field may be undefined/NaN/absent — buildStatRows() skips rows
//   whose formatted value is empty, so NVIDIA gets all rows while Intel
//   may only show Model + Usage + Temperature.
//
// Public surface:
//   DEFAULT_LIMIT                              - 20 (top-N process cap)
//   formatVram(bytes)                          - "8.0 GiB" (IEC binary)
//   formatPower(watts)                         - "42.5 W" / "115 W" / ""
//   formatClock(mhz)                           - "1815 MHz" / ""
//   formatPercent(value)                       - "73%" (rounded integer)
//   composeVram(usedBytes, totalBytes)         - "6.2 GiB / 24 GiB · 26%"
//   buildStatRows(detail)                      - [{ label, value }] ordered
//   rankProcesses(records, limit)              - sorted [{ pid, name, vramBytes }]
//   formatProcessVram(bytes)                   - alias of formatVram

var DEFAULT_LIMIT = 20;

// IEC binary units, matching df -h convention for capacity (not I/O rate).
var SIZE_UNITS = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"];

// Coerce to a finite number; non-finite inputs (NaN, Infinity, undefined)
// become 0 so downstream formatters don't propagate garbage.
function _finite(n) {
    n = Number(n);
    return isFinite(n) ? n : 0;
}

// True when a sensor field carries a real reading. An ABSENT field is
// undefined / null / NaN / Infinity — all skipped by buildStatRows so the
// tooltip degrades per host. `null` matters: Number(null) === 0 is finite, so
// a backend emitting null for an unread sensor would otherwise render "0 W" /
// "0%" / "0 °C" (a real-looking zero) instead of dropping the row.
function _present(v) {
    if (v === undefined || v === null)
        return false;
    return isFinite(Number(v));
}

// A C++ QVariantList (e.g. NvmlReader.runningProcesses()) arrives in QML as an
// array-LIKE object, not a true JS Array — Array.isArray() is FALSE for it, so
// guard on a numeric .length + index access instead. Same trap as core/CLAUDE.md
// § "QML list properties are NOT JS Arrays": Node tests pass real Arrays, so an
// Array.isArray guard stays green in unit tests yet drops every live process
// list (the standalone GPU tooltip showed raw=22 records → ranked=0). Index
// access (records[i]) works on the array-like, which is all dedupe/rank need.
function _isArrayLike(x) {
    return x !== undefined && x !== null && typeof x.length === "number";
}

// "8.0 GiB" / "24 GiB" / "512 MiB" — one decimal below 10, integer above.
// Mirrors DiskTooltipModel.formatSize exactly (same rounding-boundary logic).
function formatVram(bytes) {
    var b = _finite(bytes);
    if (b < 0)
        b = 0;
    var i = 0;
    while (b >= 1024 && i < SIZE_UNITS.length - 1) {
        b /= 1024;
        i++;
    }
    // Prevent "1024 GiB" — promote at the rounding boundary.
    if (i < SIZE_UNITS.length - 1 && b >= 1023.5) {
        b /= 1024;
        i++;
    }
    var n;
    if (i === 0)
        n = String(Math.round(b));
    else
        n = b < 10 ? b.toFixed(1) : String(Math.round(b));
    return n + " " + SIZE_UNITS[i];
}

// "42.5 W" below 100, "115 W" at/above — one decimal only where the extra
// precision is legible. Empty string when the sensor is absent/non-finite.
function formatPower(watts) {
    if (!_present(watts))
        return "";
    var w = Number(watts);
    if (w < 100)
        return w.toFixed(1) + " W";
    return String(Math.round(w)) + " W";
}

// "1815 MHz" (integer — clock rates don't warrant sub-MHz precision).
// Empty string when the sensor is absent/non-finite.
function formatClock(mhz) {
    if (!_present(mhz))
        return "";
    return String(Math.round(Number(mhz))) + " MHz";
}

// "73%" — rounded integer, no decimal. Used for GPU engine utilisation.
// Absent/NaN → "0%" (rounds, doesn't hide, because 0% is a valid reading).
function formatPercent(value) {
    var p = _finite(value);
    if (p < 0)
        p = 0;
    return Math.round(p) + "%";
}

// "6.2 GiB / 24 GiB · 26%" when total is known; "" when total is unknown
// or <= 0 (hide the line rather than show misleading "0 B / 0 B").
function composeVram(usedBytes, totalBytes) {
    var total = _finite(totalBytes);
    if (total <= 0)
        return "";
    var used = _finite(usedBytes);
    if (used < 0)
        used = 0;
    // Clamp: a transient sample with used > total must not render "108%".
    var pct = Math.round((used / total) * 100);
    if (pct > 100)
        pct = 100;
    return formatVram(used) + " / " + formatVram(total) + " · " + pct + "%";
}

// Returns the ordered stat rows for the GPU tooltip, skipping any row whose
// formatted value is empty (absent sensor). Order follows sensor availability:
// Model (always human-readable if present), Usage, VRAM, Temperature, Power, Clock.
function buildStatRows(detail) {
    var d = detail || {};
    var rows = [];

    var model = d.model ? String(d.model) : "";
    if (model)
        rows.push({ label: "Model", value: model });

    if (_present(d.usagePercent))
        rows.push({ label: "Usage", value: formatPercent(d.usagePercent) });

    var vramText = composeVram(d.vramUsedBytes, d.vramTotalBytes);
    if (vramText)
        rows.push({ label: "VRAM", value: vramText });

    if (_present(d.tempC))
        rows.push({ label: "Temperature", value: Math.round(_finite(d.tempC)) + " °C" });

    var powerText = formatPower(d.powerW);
    if (powerText)
        rows.push({ label: "Power", value: powerText });

    var clockText = formatClock(d.clockMhz);
    if (clockText)
        rows.push({ label: "Clock", value: clockText });

    return rows;
}

// Sort GPU process records by vramBytes descending, tiebreak pid ascending,
// cap to limit. Absent vramBytes ranks as 0 (kept, not dropped — the backend
// may not sample VRAM for every process tick). Non-array input → [].
function rankProcesses(records, limit) {
    var cap = (limit === undefined) ? DEFAULT_LIMIT : limit;
    if (!_isArrayLike(records) || cap <= 0)
        return [];
    var cleaned = [];
    for (var i = 0; i < records.length; i++) {
        var r = records[i];
        if (!r || r.pid === undefined || r.pid === null)
            continue;
        var vram = Number(r.vramBytes);
        cleaned.push({
            pid: Number(r.pid),
            name: (r.name === undefined || r.name === null) ? "" : String(r.name),
            vramBytes: (isFinite(vram) && vram >= 0) ? vram : 0
        });
    }
    cleaned.sort(function (a, b) {
        if (b.vramBytes !== a.vramBytes)
            return b.vramBytes - a.vramBytes;
        return a.pid - b.pid;
    });
    return cleaned.slice(0, cap);
}

// Alias — formatProcessVram is the same unit family as formatVram.
function formatProcessVram(bytes) {
    return formatVram(bytes);
}

// Collapse duplicate pids before rankProcesses: NVML may report a process once
// per compute context and once per graphics context, producing multiple records
// with the same pid. Keeps the record with the larger vramBytes; on a tie
// keeps the first-seen record. Does NOT sort (rankProcesses handles that).
// Non-array input → []. Records with missing/NaN pid are skipped.
function dedupeByPid(records) {
    if (!_isArrayLike(records))
        return [];
    var seen = {};   // pid (number) → index into out[]
    var out = [];
    for (var i = 0; i < records.length; i++) {
        var r = records[i];
        if (!r)
            continue;
        var pid = Number(r.pid);
        if (r.pid === undefined || r.pid === null || !isFinite(pid))
            continue;
        var vram = Number(r.vramBytes);
        if (!isFinite(vram) || vram < 0)
            vram = 0;
        var name = (r.name === undefined || r.name === null) ? "" : String(r.name);
        if (!(pid in seen)) {
            seen[pid] = out.length;
            out.push({ pid: pid, name: name, vramBytes: vram });
        } else {
            var prev = out[seen[pid]];
            if (vram > prev.vramBytes)
                out[seen[pid]] = { pid: pid, name: name, vramBytes: vram };
        }
    }
    return out;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        DEFAULT_LIMIT: DEFAULT_LIMIT,
        formatVram: formatVram,
        formatPower: formatPower,
        formatClock: formatClock,
        formatPercent: formatPercent,
        composeVram: composeVram,
        buildStatRows: buildStatRows,
        rankProcesses: rankProcesses,
        formatProcessVram: formatProcessVram,
        dedupeByPid: dedupeByPid
    };
}
