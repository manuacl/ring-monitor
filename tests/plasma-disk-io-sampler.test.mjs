import { test } from "node:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import assert from "node:assert";

// Text-level guard for platforms/plasma/DiskIoSampler.qml — the Plasma source
// for the disk-I/O throughput ring (issue #77). Same rationale as
// metrics-backend.test.mjs: it imports org.kde.ksysguard.sensors, absent from
// the CI container, so a qmltestrunner smoke test would fail to load. The
// rate / peak math is covered runtime-free in disk-io-scale.test.mjs; this
// guards the ksysguard sensor wiring + the same-surface contract with the
// standalone sampler.

const __dirname = dirname(fileURLToPath(import.meta.url));
const SRC = readFileSync(join(__dirname, "..", "contents", "ui", "platforms", "plasma", "DiskIoSampler.qml"), "utf8");

test("Plasma DiskIoSampler exposes the io surface MetricsBackend forwards", () => {
    assert.match(SRC, /property\s+bool\s+active/, "must declare the `active` gate");
    assert.match(SRC, /property\s+var\s+io/, "must expose the `io` property");
    for (const field of ["readBps", "writeBps", "combinedBps", "readPercent", "writePercent", "combinedPercent"]) {
        assert.match(SRC, new RegExp(`["']${field}["']`), `io must carry ${field} (same surface as the standalone sampler)`);
    }
});

test("Plasma DiskIoSampler reads the disk/all byte/s sensors and scales via the shared module", () => {
    assert.match(SRC, /import\s+org\.kde\.ksysguard\.sensors/, "must import org.kde.ksysguard.sensors");
    assert.match(SRC, /sensorId:\s*"disk\/all\/read"/, "must read disk/all/read");
    assert.match(SRC, /sensorId:\s*"disk\/all\/write"/, "must read disk/all/write");
    assert.match(SRC, /DiskIo\.combinedRate\s*\(/, "must combine read+write via DiskIoScale");
    assert.match(SRC, /DiskIo\.updatePeak\s*\(/, "must track the auto-scaling peak");
    assert.match(SRC, /DiskIo\.rateToPercent\s*\(/, "must scale the rate to the arc percent");
    // ksysguard gives the rate directly — this sampler must NOT do a /proc-style
    // sample delta (that's the standalone path). A `ratesFromSamples` call here
    // would be a copy-paste bug.
    assert.doesNotMatch(SRC, /ratesFromSamples/, "Plasma reads the rate directly; no sample-delta math");
});

test("Plasma DiskIoSampler only subscribes while active (off-screen ring costs nothing)", () => {
    // Both sensors gated on active so ksysguard isn't subscribed in the
    // background, and the snapshot Timer likewise runs only while active.
    assert.equal((SRC.match(/enabled:\s*sampler\.active/g) || []).length, 2,
        "both disk/all sensors must carry enabled: sampler.active");
    assert.match(SRC, /Timer\s*{[\s\S]*?running:\s*sampler\.active/, "the snapshot Timer's running must be bound to active");
});

test("Plasma DiskIoSampler coerces an unread sensor to 0 (same-surface, no NaN leak)", () => {
    // Before the first push .value is NaN/undefined; the standalone surface
    // exposes finite numbers, so this must coerce or io.readBps would be NaN.
    assert.match(SRC, /isFinite\(\s*readSensor\.value\s*\)/, "must coerce readSensor.value through isFinite");
    assert.match(SRC, /isFinite\(\s*writeSensor\.value\s*\)/, "must coerce writeSensor.value through isFinite");
});
