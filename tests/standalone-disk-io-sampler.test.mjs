import { test } from "node:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import assert from "node:assert";

// Text-level guard for DiskIoSampler.qml — the standalone source for the
// disk-I/O throughput ring (issue #77). Same rationale as
// standalone-process-sampler.test.mjs: the file imports `RingMonitor.Standalone`
// (the ProcReader C++ helper), absent from the CI container, so a
// qmltestrunner smoke test would fail to load. The rate / peak / aggregation
// math is covered runtime-free in disk-io-scale.test.mjs +
// disk-stats-parser.test.mjs; this guards the QML wiring those can't see.

const __dirname = dirname(fileURLToPath(import.meta.url));
const SRC = readFileSync(join(__dirname, "..", "contents", "ui", "platforms", "standalone", "DiskIoSampler.qml"), "utf8");

test("DiskIoSampler exposes the io surface MetricsBackend forwards", () => {
    assert.match(SRC, /property\s+bool\s+active/, "must declare the `active` gate");
    assert.match(SRC, /property\s+var\s+io/, "must expose the `io` property");
    // The six fields a consumer reads: real rates for the label, percentages
    // for the arc. A dropped field would silently render undefined.
    for (const field of ["readBps", "writeBps", "combinedBps", "readPercent", "writePercent", "combinedPercent"]) {
        assert.match(SRC, new RegExp(`["']${field}["']`), `io must carry ${field}`);
    }
});

test("DiskIoSampler derives rates from /proc/diskstats via the shared modules", () => {
    assert.match(SRC, /import\s+RingMonitor\.Standalone/, "must import RingMonitor.Standalone (ProcReader)");
    assert.match(SRC, /ProcReader\s*{/, "must instantiate its own ProcReader");
    assert.match(SRC, /reader\.read\(["']\/proc\/diskstats["']\)/, "must read /proc/diskstats");
    assert.match(SRC, /DiskStats\.parseDiskStats\s*\(/, "must parse via DiskStatsParser");
    assert.match(SRC, /DiskStats\.aggregateWholeDisks\s*\(/, "must aggregate whole disks (drop partitions)");
    assert.match(SRC, /DiskStats\.ratesFromSamples\s*\(/, "must derive byte/s from the sample delta");
    assert.match(SRC, /DiskIo\.updatePeak\s*\(/, "must track the auto-scaling peak");
    assert.match(SRC, /DiskIo\.rateToPercent\s*\(/, "must scale the rate to the arc percent");
});

test("DiskIoSampler only samples while active (off-screen ring costs nothing)", () => {
    // The whole point of the gate: the issue #77 requirement is to sample only
    // while the ring is on screen. The Timer's running must follow `active`.
    assert.match(SRC, /Timer\s*{[\s\S]*?running:\s*sampler\.active/, "the Timer's running must be bound to active");
    // Dropping the prev sample on deactivate prevents a stale first delta when
    // the ring re-appears (the gap could be minutes → a huge spurious rate).
    assert.match(SRC, /onActiveChanged:\s*{[\s\S]*?_reset\(\)/, "must reset the baseline when active flips off");
});

test("DiskIoSampler skips a transient empty /proc/diskstats read (no spurious spike)", () => {
    // A failed/empty read parses to {} → a {0,0} aggregate. Seeding that as the
    // baseline makes the NEXT good tick read the whole since-boot counter as one
    // interval (a huge unclamped positive delta) and pins the rolling peak to
    // garbage. The guard must bail before touching _prev on an empty map.
    assert.match(SRC, /Object\.keys\(\s*map\s*\)\.length\s*===\s*0/, "must detect an empty parse (no device rows)");
    const sampleBody = SRC.match(/function\s+_sample\s*\(\)\s*{[\s\S]*?\n    }/);
    assert.ok(sampleBody, "must find _sample()");
    assert.match(sampleBody[0], /length\s*===\s*0\s*\)\s*\n\s*return/, "the empty-map guard must `return` before updating _prev");
});

test("DiskIoSampler derives the Timer interval from the rate denominator (no drift)", () => {
    // _intervalSec is the seconds the rate divides by; the Timer ms must be
    // derived from it, not a second hardcoded literal that could silently drift
    // and scale every reported rate.
    assert.match(SRC, /interval:\s*Math\.round\(\s*sampler\._intervalSec\s*\*\s*1000\s*\)/, "Timer.interval must derive from _intervalSec");
});

test("DiskIoSampler is Plasma-free (standalone isolation)", () => {
    assert.doesNotMatch(SRC, /import\s+org\.kde\.(?!kirigami)/, "must not import a non-Kirigami org.kde.* module");
});
