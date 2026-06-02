import QtQuick
import org.kde.ksysguard.sensors as Sensors
import "../../core/DiskIoScale.js" as DiskIo

// Plasma source for the disk-I/O throughput ring (issue #77) — the counterpart
// of platforms/standalone/DiskIoSampler.qml, satisfying the same surface
// (active / io) from ksysguard's disk/all/{read,write} byte/s sensors instead
// of /proc/diskstats. ksysguard reports the RATE directly (no sample delta
// needed, unlike the standalone /proc/diskstats counters), so each tick just
// reads .value and scales it onto the arc via the shared DiskIoScale rolling
// peak. Sensors are `enabled: active` so ksysguard isn't subscribed while the
// ring is off-screen (the issue's "sample only while on screen" requirement,
// same gate ProcessSampler uses). Split out of MetricsBackend.qml to keep that
// adapter under the 500-line cap.
//
// Public surface (mirrors the standalone sampler byte-for-byte):
//   active  - gate; sampling runs only while true.
//   io      - { readBps, writeBps, combinedBps, readPercent, writePercent,
//              combinedPercent }. The *Bps are the real rates (MB/s label);
//              the *Percent drive the arc, each against its own rolling peak.

Item {
    id: sampler

    property bool active: false

    // Reactive on _tick (bumped each Timer tick). A property, not a function,
    // so a binding tracks it (core/CLAUDE.md "expose as a property").
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

    property int _tick: 0
    property real _readBps: 0
    property real _writeBps: 0
    property real _combinedBps: 0
    // Per-component rolling peaks (the arc ceilings) — see DiskIoScale.updatePeak.
    property real _peakRead: 0
    property real _peakWrite: 0
    property real _peakCombined: 0

    // ksysguard byte/s rate sensors. enabled: active so the daemon isn't
    // subscribed while the ring is off-screen. On a host without these leaves
    // .value stays NaN (coerced to 0 below) — the ring just reads idle.
    Sensors.Sensor {
        id: readSensor
        sensorId: "disk/all/read"
        enabled: sampler.active
    }
    Sensors.Sensor {
        id: writeSensor
        sensorId: "disk/all/write"
        enabled: sampler.active
    }

    function _sample() {
        // Coerce an unread sensor (NaN/undefined before the first push) to 0 so
        // io.readBps matches the standalone surface (a finite number, never NaN).
        sampler._readBps = isFinite(readSensor.value) ? readSensor.value : 0;
        sampler._writeBps = isFinite(writeSensor.value) ? writeSensor.value : 0;
        sampler._combinedBps = DiskIo.combinedRate(sampler._readBps, sampler._writeBps);
        sampler._peakRead = DiskIo.updatePeak(sampler._peakRead, sampler._readBps);
        sampler._peakWrite = DiskIo.updatePeak(sampler._peakWrite, sampler._writeBps);
        sampler._peakCombined = DiskIo.updatePeak(sampler._peakCombined, sampler._combinedBps);
        sampler._tick++;
    }

    function _reset() {
        // Zero the rates so a re-shown ring doesn't flash the last value; peaks
        // are KEPT so it resumes its learned scale (matches the standalone
        // sampler). No baseline to drop here — ksysguard gives the rate
        // directly, so there's no stale-delta hazard.
        sampler._readBps = 0;
        sampler._writeBps = 0;
        sampler._combinedBps = 0;
        sampler._tick++;
    }

    onActiveChanged: if (!active)
        sampler._reset()

    // 500 ms = the ksysguard daemon push cadence; snapshots .value + updates the
    // peaks. running: active is the "no background subscription" gate;
    // triggeredOnStart fills the ring immediately on show.
    Timer {
        interval: 500
        running: sampler.active
        repeat: true
        triggeredOnStart: true
        onTriggered: sampler._sample()
    }
}
