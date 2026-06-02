import QtQuick
import RingMonitor.Standalone
import "DiskStatsParser.js" as DiskStats
import "../../core/DiskIoScale.js" as DiskIo

// Standalone source for the disk-I/O throughput ring (issue #77). Samples
// /proc/diskstats and derives whole-disk read/write byte/s rates plus an
// auto-scaling-peak percentage for the arc — but ONLY while `active`, so an
// off-screen diskIo ring costs nothing (MainContent flips `active` when the
// ring is enabled + visible, same gate ProcessSampler uses for the tooltip).
// Split out of MetricsBackend.qml to keep that adapter under the 500-line cap
// and to stay a focused, separately-testable unit.
//
// Public surface (mirrored by the Plasma adapter's disk/all sensor wiring):
//   active  - gate; sampling runs only while true.
//   io      - { readBps, writeBps, combinedBps, readPercent, writePercent,
//              combinedPercent }. The *Bps are the real rates (MB/s label via
//              DiskIoScale.formatRate); the *Percent drive the arc sweep, each
//              scaled against its own rolling peak so read / write / combined
//              don't share one ceiling.

Item {
    id: sampler

    property bool active: false

    // Re-evaluated on _tick (bumped each sample). A property, not a function,
    // so a binding tracks it and the ring refreshes live (core/CLAUDE.md
    // "Reactive argless data: expose as a property, not a function").
    readonly property var io: {
        sampler._tick;
        return {
            "readBps": sampler._readBps,
            "writeBps": sampler._writeBps,
            "combinedBps": sampler._combinedBps,
            "readPercent": DiskIo.rateToPercent(sampler._readBps, sampler._peakRead),
            "writePercent": DiskIo.rateToPercent(sampler._writeBps, sampler._peakWrite),
            "combinedPercent": DiskIo.rateToPercent(sampler._combinedBps, sampler._peakCombined)
        };
    }

    // 500 ms sample window — matches the Timer below and the Plasma daemon
    // cadence (standalone/CLAUDE.md "Poll cadence"). The diskstats counters are
    // monotonic, so each rate is (sector delta × 512 B) / this window.
    readonly property real _intervalSec: 0.5

    property int _tick: 0
    property var _prev: null  // previous whole-disk {readSectors, writeSectors}
    property real _readBps: 0
    property real _writeBps: 0
    property real _combinedBps: 0
    // Per-component rolling peaks (the arc normalisation ceilings). Each decays
    // toward the floor while idle and rises instantly to a faster live rate —
    // see DiskIoScale.updatePeak.
    property real _peakRead: 0
    property real _peakWrite: 0
    property real _peakCombined: 0

    ProcReader {
        id: reader
    }

    function _sample() {
        var map = DiskStats.parseDiskStats(reader.read("/proc/diskstats"));
        // A transient empty/failed read (no device rows) must NOT seed a
        // zero baseline: the next successful tick would then read the whole
        // since-boot counter as one interval's throughput — a massive positive
        // delta (not clamped, unlike a negative one) that pins the rolling peak
        // to garbage and leaves every later sweep a sliver until it decays.
        // Skip the tick instead, keeping the last good baseline.
        if (Object.keys(map).length === 0)
            return;
        var agg = DiskStats.aggregateWholeDisks(map);
        // First tick after activation only seeds the baseline; the second
        // computes the first real delta (a one-sample rate would be bogus).
        if (sampler._prev) {
            var rates = DiskStats.ratesFromSamples(sampler._prev, agg, sampler._intervalSec);
            sampler._readBps = rates.readBps;
            sampler._writeBps = rates.writeBps;
            sampler._combinedBps = DiskIo.combinedRate(rates.readBps, rates.writeBps);
            sampler._peakRead = DiskIo.updatePeak(sampler._peakRead, sampler._readBps);
            sampler._peakWrite = DiskIo.updatePeak(sampler._peakWrite, sampler._writeBps);
            sampler._peakCombined = DiskIo.updatePeak(sampler._peakCombined, sampler._combinedBps);
        }
        sampler._prev = agg;
        sampler._tick++;
    }

    function _reset() {
        // Drop the baseline so the next activation re-seeds (the gap could be
        // minutes; a stale delta would flash a huge spurious rate). Peaks are
        // deliberately KEPT: a ring toggled off then on keeps its learned scale
        // instead of re-warming from the floor.
        sampler._prev = null;
        sampler._readBps = 0;
        sampler._writeBps = 0;
        sampler._combinedBps = 0;
        sampler._tick++;
    }

    onActiveChanged: {
        if (!active)
            _reset();
    }

    Timer {
        // Single source of truth for the cadence: _intervalSec is the rate
        // denominator, this is its millisecond form — derived so the two can't
        // drift (a mismatch would scale every reported rate).
        interval: Math.round(sampler._intervalSec * 1000)
        running: sampler.active
        repeat: true
        triggeredOnStart: true
        onTriggered: sampler._sample()
    }
}
