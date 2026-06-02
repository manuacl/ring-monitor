// Text-level guard for DiskPartitionSensors.qml — the Plasma per-partition
// disk Sensor adapter (split out of MetricsBackend for #68).
//
// Run:  node --test tests/disk-partition-sensors.test.mjs
//
// Like metrics-backend.test.mjs this inspects the QML as text: the file imports
// org.kde.ksysguard.sensors, absent from the CI container, so qmltestrunner
// can't load it. The regexes assert the public surface + the 3-leaf wiring.

import { test } from "node:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import assert from "node:assert/strict";

const __dirname = dirname(fileURLToPath(import.meta.url));
const SOURCE = readFileSync(
    join(__dirname, "..", "contents", "ui", "platforms", "plasma", "DiskPartitionSensors.qml"),
    "utf8");

test("declares the partitions + mounted inputs", () => {
    assert.match(SOURCE, /property\s+var\s+partitions\s*:/, "must take the discovered partition list");
    assert.match(SOURCE, /property\s+var\s+mounted\s*:/, "must take the findmnt mount set (mountpoint/fstype/removable)");
});

test("instantiates a per-partition Sensor delegate keyed by id", () => {
    assert.match(SOURCE, /model:\s*diskSensors\.partitions/, "Instantiator must be driven by the discovered list");
    assert.match(SOURCE, /partId:\s*modelData\.id/, "each delegate must expose its partition id");
});

test("each delegate carries THREE ksysguard leaves: usedPercent + total + free", () => {
    // usedPercent drives the ring; total/free bytes feed the #68 tooltip figures.
    assert.match(SOURCE, /sensorId:\s*modelData\.sensorId/, "usedPercent sensor must bind the discovered sensorId");
    assert.match(SOURCE, /sensorId:\s*"disk\/"\s*\+\s*modelData\.id\s*\+\s*"\/total"/, "must subscribe the per-partition total-bytes leaf");
    assert.match(SOURCE, /sensorId:\s*"disk\/"\s*\+\s*modelData\.id\s*\+\s*"\/free"/, "must subscribe the per-partition free-bytes leaf");
});

test("exposes partitionValue + partitionDetail", () => {
    assert.match(SOURCE, /function\s+partitionValue\s*\(id\)/, "must expose partitionValue(id)");
    assert.match(SOURCE, /function\s+partitionDetail\s*\(id\)/, "must expose partitionDetail(id)");
});

test("partitionDetail assembles via the shared DiskMetrics helper", () => {
    // The defaulting + the single removable rule live once in core/DiskMetrics.
    assert.match(SOURCE, /import\s+["']\.\.\/\.\.\/core\/DiskMetrics\.js["']\s+as\s+DiskMetrics/, "must import the shared DiskMetrics module");
    assert.match(SOURCE, /DiskMetrics\.buildPartitionDetail\s*\(/, "partitionDetail must delegate assembly to DiskMetrics.buildPartitionDetail");
});

test("holds last-good usedPercent across Sensor rebuilds (USB plug/unplug)", () => {
    assert.match(SOURCE, /_lastValue/, "must cache the last-good value so a rebuild doesn't blink rings to 0%");
});
