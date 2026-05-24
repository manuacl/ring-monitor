import { test } from "node:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import assert from "node:assert";

// Text-level guard for the MetricsBackend adapter. Same rationale as
// tests/config-store.test.mjs — see also memory note
// feedback_ci_no_plasma_runtime: MetricsBackend.qml imports
// `org.kde.ksysguard.sensors`, which is NOT in the CI Fedora 41
// container (CI installs only Qt6 + Kirigami). A qmltestrunner-based
// smoke test would fail to load.
//
// This Node test inspects the QML source as plain text and asserts
// that the adapter exposes the public surface main.qml depends on,
// plus the internal sensor instances mapping to the catalog's metric
// ids. Catches typos and accidental deletions that would otherwise
// only surface as silently-zero rings in production.

const __dirname = dirname(fileURLToPath(import.meta.url));
const SOURCE = readFileSync(join(__dirname, "..", "contents", "ui", "platform", "MetricsBackend.qml"), "utf8");

// Public surface main.qml consumes.
const PUBLIC_PROPS = ["coreValues"];
const PUBLIC_FUNCS = ["metricValue"];

// Named sensor instances — one per catalog metric id (see
// contents/ui/core/MetricsCatalog.js: KNOWN_METRICS).
const NAMED_SENSORS = [
    { id: "cpuTotal", catalogId: "cpu" },
    { id: "ramSensor", catalogId: "ram" },
    { id: "swapSensor", catalogId: "swap" },
    { id: "gpuSensor", catalogId: "gpu" },
    { id: "diskSensor", catalogId: "disk" }
];

// Per-core CPU sensors — 6 cores on the dev rig (see CLAUDE.md).
const CORE_IDS = ["cpu0", "cpu1", "cpu2", "cpu3", "cpu4", "cpu5"];

test("MetricsBackend exposes the public properties main.qml depends on", () => {
    for (const name of PUBLIC_PROPS) {
        const pattern = new RegExp(`property\\s+\\w+\\s+${name}\\s*:`);
        assert.match(SOURCE, pattern, `MetricsBackend.qml must declare property "${name}"`);
    }
});

test("MetricsBackend exposes the public functions main.qml depends on", () => {
    for (const name of PUBLIC_FUNCS) {
        const pattern = new RegExp(`function\\s+${name}\\s*\\(`);
        assert.match(SOURCE, pattern, `MetricsBackend.qml must declare function ${name}(...)`);
    }
});

test("MetricsBackend declares a sensor instance for every catalog metric id", () => {
    for (const { id, catalogId } of NAMED_SENSORS) {
        const idPattern = new RegExp(`id:\\s*${id}\\b`);
        assert.match(SOURCE, idPattern, `MetricsBackend.qml must declare a Sensor with id: ${id}`);

        // The sensor must be bound to the catalog lookup for its metric id.
        const bindingPattern = new RegExp(`sensorId:\\s*Catalog\\.sensorIdFor\\("${catalogId}"\\)`);
        assert.match(SOURCE, bindingPattern, `Sensor ${id} must bind sensorId: Catalog.sensorIdFor("${catalogId}")`);
    }
});

test("MetricsBackend declares one per-core CPU sensor for each core", () => {
    for (const core of CORE_IDS) {
        const idPattern = new RegExp(`id:\\s*${core}\\b`);
        assert.match(SOURCE, idPattern, `MetricsBackend.qml must declare a Sensor with id: ${core}`);

        // Hardcoded sensor id, not via Catalog (per-core ids aren't part of the catalog).
        const sensorIdPattern = new RegExp(`sensorId:\\s*"cpu/${core}/usage"`);
        assert.match(SOURCE, sensorIdPattern, `Sensor ${core} must bind sensorId: "cpu/${core}/usage"`);
    }
});

test("coreValues binding pulls from all six per-core sensors with the || 0 fallback", () => {
    // The defensive `|| 0` matters — KSysGuard returns NaN for not-yet-ready
    // sensors, and the Ring component expects numbers.
    for (const core of CORE_IDS) {
        const pattern = new RegExp(`${core}\\.value\\s*\\|\\|\\s*0`);
        assert.match(SOURCE, pattern, `coreValues must include "${core}.value || 0"`);
    }
});

test("metricValue delegates to Catalog.valueFromSensorMap", () => {
    // The pure logic lives in MetricsCatalog.js (tested in
    // tests/metrics-catalog.test.mjs). The backend is just the wiring.
    assert.match(SOURCE, /Catalog\.valueFromSensorMap\s*\(\s*sensorMap\s*,\s*id\s*\)/, "metricValue(id) must call Catalog.valueFromSensorMap(sensorMap, id)");
});
