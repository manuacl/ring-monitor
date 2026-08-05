// TDD spec for TempSensorCatalog — the pure decisions behind the
// sensorTemp picker's Celsius-sensor discovery (issue #164).
//
// Run:  node --test tests/temp-sensor-catalog.test.mjs
//
// Implementation: contents/ui/platforms/plasma/TempSensorCatalog.js.
// Dual-loaded by QML and Node via the module.exports shim at the bottom.

import { createRequire } from "node:module";
import { test } from "node:test";
import assert from "node:assert/strict";

const require = createRequire(import.meta.url);
const TempSensorCatalog = require("../contents/ui/platforms/plasma/TempSensorCatalog.js");

// Live-probed facts (#164): a Celsius leaf's DisplayRole is the
// LOCALIZED name with the unit suffix ("Composite (°C)"); regex/group
// nodes (e.g. "cpu/cpu\d+/temperature") carry unit -1 and never reach
// Ready; Sensors.Sensor.unit reports KSysGuard::Unit as an int with
// UnitCelsius = 1000 (the enum is not exposed to QML).

test("UNIT_CELSIUS is the probed KSysGuard::Unit value", () => {
    assert.equal(TempSensorCatalog.UNIT_CELSIUS, 1000);
});

test("isTempCandidate accepts localized names with the °C suffix", () => {
    assert.equal(TempSensorCatalog.isTempCandidate("Composite (°C)"), true);
    assert.equal(TempSensorCatalog.isTempCandidate("Cœur 1 Température actuelle (°C)"), true);
});

test("isTempCandidate rejects non-temperature and non-string displays", () => {
    assert.equal(TempSensorCatalog.isTempCandidate("Composite"), false);
    assert.equal(TempSensorCatalog.isTempCandidate("Fan Speed (rpm)"), false);
    assert.equal(TempSensorCatalog.isTempCandidate("Composite (°F)"), false);
    assert.equal(TempSensorCatalog.isTempCandidate(""), false);
    assert.equal(TempSensorCatalog.isTempCandidate(undefined), false);
    assert.equal(TempSensorCatalog.isTempCandidate(null), false);
    assert.equal(TempSensorCatalog.isTempCandidate(42), false);
});

test("disambiguationSegment strips the bus/address tail from the chip segment", () => {
    assert.equal(TempSensorCatalog.disambiguationSegment("lmsensors/gigabyte_wmi-isa-0a40/temp1"), "gigabyte_wmi");
    assert.equal(TempSensorCatalog.disambiguationSegment("lmsensors/nvme-pci-0100/temp1"), "nvme");
    assert.equal(TempSensorCatalog.disambiguationSegment("lmsensors/nct6775-isa-0290/temp2"), "nct6775");
});

test("disambiguationSegment keeps plain middle segments untouched", () => {
    assert.equal(TempSensorCatalog.disambiguationSegment("cpu/cpu0/temperature"), "cpu0");
    assert.equal(TempSensorCatalog.disambiguationSegment("gpu/gpu1/temperature"), "gpu1");
});

test("disambiguationSegment falls back to the first segment for one-part ids", () => {
    assert.equal(TempSensorCatalog.disambiguationSegment("cpu"), "cpu");
});

test("buildTempSensorEntries returns [] on null / undefined / empty input", () => {
    assert.deepEqual(TempSensorCatalog.buildTempSensorEntries(null), []);
    assert.deepEqual(TempSensorCatalog.buildTempSensorEntries(undefined), []);
    assert.deepEqual(TempSensorCatalog.buildTempSensorEntries([]), []);
});

test("buildTempSensorEntries keeps only Ready Celsius probes", () => {
    const probed = [
        { id: "cpu/all/averageTemperature", name: "Average", unit: 1000, ready: true },
        // Regex/group node: unit -1, never Ready — must be excluded.
        { id: "cpu/cpu\\d+/temperature", name: "Temperature", unit: -1, ready: false },
        { id: "lmsensors/nct6775-isa-0290/fan1", name: "Fan", unit: 2000, ready: true },
        { id: "gpu/gpu0/temperature", name: "GPU", unit: 1000, ready: false },
        null,
        undefined,
    ];
    assert.deepEqual(TempSensorCatalog.buildTempSensorEntries(probed), [{ id: "cpu/all/averageTemperature", label: "Average" }]);
});

test("buildTempSensorEntries labels unique names without a suffix", () => {
    const probed = [
        { id: "lmsensors/nvme-pci-0100/temp1", name: "Composite", unit: 1000, ready: true },
        { id: "cpu/all/averageTemperature", name: "Average", unit: 1000, ready: true },
    ];
    const entries = TempSensorCatalog.buildTempSensorEntries(probed);
    assert.deepEqual(entries, [
        { id: "cpu/all/averageTemperature", label: "Average" },
        { id: "lmsensors/nvme-pci-0100/temp1", label: "Composite" },
    ]);
});

test("buildTempSensorEntries disambiguates duplicate names with the chip segment", () => {
    const probed = [
        { id: "lmsensors/gigabyte_wmi-isa-0a40/temp1", name: "Température 1", unit: 1000, ready: true },
        { id: "lmsensors/nct6775-isa-0290/temp1", name: "Température 1", unit: 1000, ready: true },
        { id: "cpu/all/averageTemperature", name: "Average", unit: 1000, ready: true },
    ];
    const entries = TempSensorCatalog.buildTempSensorEntries(probed);
    assert.deepEqual(entries, [
        { id: "cpu/all/averageTemperature", label: "Average" },
        { id: "lmsensors/gigabyte_wmi-isa-0a40/temp1", label: "Température 1 (gigabyte_wmi)" },
        { id: "lmsensors/nct6775-isa-0290/temp1", label: "Température 1 (nct6775)" },
    ]);
});

test("buildTempSensorEntries falls back to the full id when name and segment both collide", () => {
    // Same chip exposing the same sensor name twice (seen on multi-zone
    // hwmon devices): the segment can't tell them apart, the id can.
    const probed = [
        { id: "lmsensors/nct6775-isa-0290/temp1", name: "Temp", unit: 1000, ready: true },
        { id: "lmsensors/nct6775-isa-0290/temp4", name: "Temp", unit: 1000, ready: true },
    ];
    const entries = TempSensorCatalog.buildTempSensorEntries(probed);
    assert.deepEqual(entries, [
        { id: "lmsensors/nct6775-isa-0290/temp1", label: "Temp (lmsensors/nct6775-isa-0290/temp1)" },
        { id: "lmsensors/nct6775-isa-0290/temp4", label: "Temp (lmsensors/nct6775-isa-0290/temp4)" },
    ]);
});

test("buildTempSensorEntries sorts by label, then id", () => {
    const probed = [
        { id: "gpu/gpu0/temperature", name: "GPU", unit: 1000, ready: true },
        { id: "cpu/cpu1/temperature", name: "Core", unit: 1000, ready: true },
        { id: "cpu/cpu0/temperature", name: "Core", unit: 1000, ready: true },
    ];
    const entries = TempSensorCatalog.buildTempSensorEntries(probed);
    assert.deepEqual(
        entries.map(function (e) {
            return e.id;
        }),
        ["cpu/cpu0/temperature", "cpu/cpu1/temperature", "gpu/gpu0/temperature"],
    );
    // Duplicate names are disambiguated — the two "Core" entries get
    // per-device suffixes so their labels stay unique.
    assert.equal(entries[0].label, "Core (cpu0)");
    assert.equal(entries[1].label, "Core (cpu1)");
});
