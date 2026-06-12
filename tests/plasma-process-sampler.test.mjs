import { test } from "node:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import assert from "node:assert";

// Text-level guard for platforms/plasma/ProcessSampler.qml — the Plasma source
// for the CPU and RAM ring process tooltips (issues #69/#70). Same rationale as
// metrics-backend.test.mjs: it imports org.kde.ksysguard.{sensors,process},
// absent from the CI container, so a qmltestrunner smoke test would fail to
// load. The ranking math is covered runtime-free in process-ranking.test.mjs;
// this guards the ProcessDataModel wiring, per-core→total normalisation, and
// memory attribute + footer sensor wiring.

const __dirname = dirname(fileURLToPath(import.meta.url));
const SRC = readFileSync(join(__dirname, "..", "contents", "ui", "platforms", "plasma", "ProcessSampler.qml"), "utf8");

test("Plasma ProcessSampler exposes the tooltip surface MetricsBackend forwards", () => {
    assert.match(SRC, /property\s+bool\s+active/, "must declare the `active` gate");
    assert.match(SRC, /property\s+var\s+topProcesses/, "must expose topProcesses");
    assert.match(SRC, /property\s+var\s+topMemProcesses/, "must expose topMemProcesses (RAM tooltip ranking)");
    assert.match(SRC, /property\s+var\s+loadAverages/, "must expose loadAverages");
    assert.match(SRC, /property\s+real\s+memUsedKb/, "must expose memUsedKb (RAM footer)");
    assert.match(SRC, /property\s+real\s+memTotalKb/, "must expose memTotalKb (RAM footer)");
    assert.match(SRC, /property\s+int\s+coreCount/, "must take coreCount (injected) for the per-core→total normalisation");
});

test("Plasma ProcessSampler reads ProcessDataModel and ranks via the shared module", () => {
    assert.match(SRC, /import\s+org\.kde\.ksysguard\.process/, "must import org.kde.ksysguard.process");
    assert.match(SRC, /ProcessDataModel\s*{/, "must instantiate a ProcessDataModel");
    assert.match(SRC, /enabledAttributes:\s*\[\s*"name"\s*,\s*"pid"\s*,\s*"usage"\s*,\s*"memory"\s*\]/, 'must enable the name/pid/usage/memory attributes (column 3 = memory)');
    assert.match(SRC, /flatList:\s*true/, "must use a flat process list");
    assert.match(SRC, /ProcessDataModel\.Value/, "must read the raw Value role (not the formatted DisplayRole) for the math");
    assert.match(SRC, /ProcessRanking\.rankByCpu\s*\(/, "must rank + cap via the shared core/ProcessRanking");
    assert.match(SRC, /ProcessRanking\.rankByMemory\s*\(/, "must compute memory ranking via rankByMemory for the RAM tooltip");
    // rssKb must be populated from the memory column (column 3), with || 0 defence
    assert.match(SRC, /rssKb/, "must set rssKb on each record from the memory column");
    // The memory column's Value is ALREADY KiB (live-probed) — only the
    // memory/physical/* sensors report bytes. A spurious /1024 here would
    // shrink every displayed RSS 1024-fold. Anchor on the value expression
    // so the explanatory comment in the source can't false-match.
    assert.doesNotMatch(SRC, /"rssKb":\s*\([^)]*\)\s*\/\s*1024/, "memory column is already KiB — must not divide by 1024");
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
    // The load sensors must also be active-gated — otherwise they subscribe to
    // ksysguard for the whole app lifetime even when the tooltip is never
    // hovered (background polling the rest of the surface avoids). Six
    // `enabled: sampler.active` total: the ProcessDataModel + 3 load-avg +
    // 2 RAM footer sensors.
    assert.equal((SRC.match(/enabled:\s*sampler\.active/g) || []).length, 6,
        "the ProcessDataModel, all three load-average sensors, and both RAM sensors must carry enabled: sampler.active");
});

test("Plasma ProcessSampler wires the RAM footer sensors for the RAM tooltip (issue #70)", () => {
    // ksysguard memory/physical/* reports bytes; the sampler divides by 1024
    // to surface kB — matches the standalone /proc/meminfo counterpart.
    assert.match(SRC, /sensorId:\s*"memory\/physical\/used"/, "must read memory/physical/used");
    assert.match(SRC, /sensorId:\s*"memory\/physical\/total"/, "must read memory/physical/total");
    // Active gate: same no-background-subscription rationale as the load sensors.
    assert.match(SRC, /memUsedSensor[\s\S]{0,100}enabled:\s*sampler\.active/, "memUsedSensor must be gated on sampler.active");
    assert.match(SRC, /memTotalSensor[\s\S]{0,100}enabled:\s*sampler\.active/, "memTotalSensor must be gated on sampler.active");
    // Byte → kB division at the property read site.
    assert.match(SRC, /memUsedSensor\.value[\s\S]{0,40}\/\s*1024/, "memUsedKb must divide the sensor value by 1024 (bytes → kB)");
    assert.match(SRC, /memTotalSensor\.value[\s\S]{0,40}\/\s*1024/, "memTotalKb must divide the sensor value by 1024 (bytes → kB)");
});
