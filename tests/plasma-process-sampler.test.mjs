import { test } from "node:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import assert from "node:assert";

// Text-level guard for platforms/plasma/ProcessSampler.qml — the Plasma source
// for the CPU-ring process tooltip (issue #69). Same rationale as
// metrics-backend.test.mjs: it imports org.kde.ksysguard.{sensors,process},
// absent from the CI container, so a qmltestrunner smoke test would fail to
// load. The ranking math is covered runtime-free in process-ranking.test.mjs;
// this guards the ProcessDataModel wiring + the per-core→total normalisation.

const __dirname = dirname(fileURLToPath(import.meta.url));
const SRC = readFileSync(join(__dirname, "..", "contents", "ui", "platforms", "plasma", "ProcessSampler.qml"), "utf8");

test("Plasma ProcessSampler exposes the tooltip surface MetricsBackend forwards", () => {
    assert.match(SRC, /property\s+bool\s+active/, "must declare the `active` gate");
    assert.match(SRC, /property\s+var\s+topProcesses/, "must expose topProcesses");
    assert.match(SRC, /property\s+var\s+loadAverages/, "must expose loadAverages");
    assert.match(SRC, /property\s+int\s+coreCount/, "must take coreCount (injected) for the per-core→total normalisation");
});

test("Plasma ProcessSampler reads ProcessDataModel and ranks via the shared module", () => {
    assert.match(SRC, /import\s+org\.kde\.ksysguard\.process/, "must import org.kde.ksysguard.process");
    assert.match(SRC, /ProcessDataModel\s*{/, "must instantiate a ProcessDataModel");
    assert.match(SRC, /enabledAttributes:\s*\[\s*"name"\s*,\s*"pid"\s*,\s*"usage"\s*\]/, 'must enable the name/pid/usage attributes ("usage" is the CPU id)');
    assert.match(SRC, /flatList:\s*true/, "must use a flat process list");
    assert.match(SRC, /ProcessDataModel\.Value/, "must read the raw Value role (not the formatted DisplayRole) for the math");
    assert.match(SRC, /ProcessRanking\.rankByCpu\s*\(/, "must rank + cap via the shared core/ProcessRanking");
});

test("Plasma ProcessSampler normalises per-core usage to total 0-100%", () => {
    // ksysguard "usage" is per-core (a thread reads ~100%, total can reach
    // coreCount*100). Dividing by coreCount yields the "total" semantics where
    // rows sum toward the aggregate ring — the chosen normalisation for #69.
    assert.match(SRC, /Math\.max\(\s*1\s*,\s*sampler\.coreCount\s*\)/, "must guard the divide with Math.max(1, coreCount)");
    assert.match(SRC, /\/\s*ncores/, "must divide the usage reading by the core count");
});

test("Plasma ProcessSampler only samples while active (no background polling, #69)", () => {
    // ProcessDataModel.enabled bound to active is the real gate (the model
    // stops fetching the process table when the tooltip closes); the Timer that
    // snapshots it is likewise running:active.
    assert.match(SRC, /enabled:\s*sampler\.active/, "ProcessDataModel.enabled must be bound to active (the no-background-polling gate)");
    assert.match(SRC, /Timer\s*{[\s\S]*?running:\s*sampler\.active/, "the snapshot Timer's running must be bound to active");
});

test("Plasma ProcessSampler wires the load-average sensors for the footer", () => {
    assert.match(SRC, /sensorId:\s*"cpu\/loadaverages\/loadaverage1"/, "must read cpu/loadaverages/loadaverage1");
    assert.match(SRC, /sensorId:\s*"cpu\/loadaverages\/loadaverage5"/, "must read cpu/loadaverages/loadaverage5");
    assert.match(SRC, /sensorId:\s*"cpu\/loadaverages\/loadaverage15"/, "must read cpu/loadaverages/loadaverage15");
});
