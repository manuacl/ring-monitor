// Pure scaling + formatting helpers for the disk-I/O ring (issue #77).
//
// Disk throughput has no fixed ceiling (unlike a usage %), so the ring
// can't map it linearly the way usage rings do. This module implements
// the **auto-scaling rolling peak** chosen for #77: each sample updates
// a decaying per-ring peak, and the arc fills to `rate / peak`. The
// numeric label always shows the real MB/s (see formatRate) — the arc
// scale and the displayed value are decoupled, the same `Ring.value`
// vs `rawValue` separation the temperature ring uses (tempToPercent).
//
// Shared by BOTH platform backends (lives in core/): the Plasma adapter
// gets byte/s rates from ksysguard's `disk/all/{read,write}` sensors and
// the standalone adapter derives them from /proc/diskstats deltas
// (DiskStatsParser.js) — but the peak tracking, combine, and formatting
// are identical, so they're written and tested once here.
//
// Dual-loaded by QML (`import "DiskIoScale.js" as DiskIo`) and Node (via
// the module.exports shim at the bottom). No `.pragma library` for Node
// compatibility — same as every other module under core/.
//
// Public surface:
//   combinedRate(readBps, writeBps)        - read+write sum, NaN-safe
//   updatePeak(prevPeak, rateBps)          - new decaying peak for this tick
//   rateToPercent(rateBps, peakBps)        - 0-100 arc fill against the peak
//   formatRate(bps)                        - "{n} {unit}/s" display string

// A megabyte for throughput is 10^6 bytes (the SI convention `iostat`,
// `dstat`, and most disk-vendor specs use), not 2^20. The ring label
// reads in the same units a user would see in those tools.
var BYTES_PER_MB = 1000000;

// Peak decay per sample. The peak is the normalisation ceiling for the
// arc; without decay a single burst (a one-off large copy) would pin the
// ceiling high for the rest of the session and leave every later sweep
// near-empty. Decaying it ~2%/tick lets the ceiling drift back down over
// ~tens of seconds of idle so the gauge stays responsive to the device's
// *current* activity band — the documented trade-off of auto-scaling
// ("the gauge meaning drifts", issue #77).
var PEAK_DECAY = 0.98;

// Floor for the peak, in bytes/s. Two jobs:
//   1. Avoids a divide-by-zero when the disk has been idle (peak → 0).
//   2. Stops sensor/sampling noise on an idle disk (a few KB/s of
//      background writes) from filling the arc: with a 10 MB/s floor a
//      trickle reads as a sliver, not a saturated ring.
// 10 MB/s is well below any modern drive's sustained rate, so a real
// transfer always pushes the peak above it within a tick.
var PEAK_FLOOR_BPS = 10 * BYTES_PER_MB;

function _finite(n) {
    return (typeof n === "number" && isFinite(n)) ? n : 0;
}

// Combined throughput = read + write. Negative/NaN components coerce to
// 0 so a missing half (one sensor unread) never poisons the sum.
function combinedRate(readBps, writeBps) {
    var r = _finite(readBps);
    var w = _finite(writeBps);
    if (r < 0) r = 0;
    if (w < 0) w = 0;
    return r + w;
}

// New peak for this tick: the larger of the current rate, the decayed
// previous peak, and the floor. Monotonic against the live rate (a
// faster sample always raises it immediately), decaying only while the
// rate sits below the previous peak.
function updatePeak(prevPeak, rateBps) {
    var prev = _finite(prevPeak);
    var rate = _finite(rateBps);
    if (rate < 0) rate = 0;
    var decayed = prev * PEAK_DECAY;
    var peak = rate;
    if (decayed > peak) peak = decayed;
    if (PEAK_FLOOR_BPS > peak) peak = PEAK_FLOOR_BPS;
    return peak;
}

// Map a byte/s rate onto 0-100 for the arc sweep, against the supplied
// peak. Clamps; non-finite or non-positive peak → 0.
function rateToPercent(rateBps, peakBps) {
    var rate = _finite(rateBps);
    var peak = _finite(peakBps);
    if (rate < 0) rate = 0;
    if (peak <= 0) return 0;
    var pct = rate * 100 / peak;
    if (pct < 0) return 0;
    if (pct > 100) return 100;
    return pct;
}

// The numeric part of the MB/s readout, WITHOUT the unit: one decimal
// below 100 MB/s (so a 3.4 MB/s trickle is legible) and no decimal above
// (380, not 380.2 — the extra digit is noise at that magnitude). The ring
// renders the unit separately (smaller font) so the number gets the room,
// which is why the value and unit are split.
function formatRateValue(bps) {
    var mb = _finite(bps) / BYTES_PER_MB;
    if (mb < 0) mb = 0;
    return mb < 100 ? mb.toFixed(1) : String(Math.round(mb));
}

// Full "{n} MB/s" string. Always MB/s — a single unit keeps the width
// stable across the ring's value animation instead of flipping KB/MB/GB.
function formatRate(bps) {
    return formatRateValue(bps) + " MB/s";
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        BYTES_PER_MB: BYTES_PER_MB,
        PEAK_DECAY: PEAK_DECAY,
        PEAK_FLOOR_BPS: PEAK_FLOOR_BPS,
        combinedRate: combinedRate,
        updatePeak: updatePeak,
        rateToPercent: rateToPercent,
        formatRateValue: formatRateValue,
        formatRate: formatRate
    };
}
