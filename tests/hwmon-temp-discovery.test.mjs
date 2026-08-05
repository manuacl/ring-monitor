import { test } from "node:test";
import assert from "node:assert/strict";
import {
    parseTempCelsius,
    isTempInput,
    tempIndexFromInput,
    buildCatalog,
    resolveSensorPath,
} from "../contents/ui/platforms/standalone/HwmonTempDiscovery.js";

// Pure catalog logic for the standalone custom-temperature metric
// (sensorTemp, issue #164). The QML adapters (MetricsBackend /
// HwmonTempSensors) do the sysfs I/O; these functions own the stable-id
// grammar, collision disambiguation, label fallback and sorting.

test("parseTempCelsius converts millidegrees to °C (same contract as CpuTempDiscovery)", () => {
    assert.equal(parseTempCelsius("45000"), 45);
    assert.equal(parseTempCelsius("45000\n"), 45);   // trailing newline from sysfs
    assert.equal(parseTempCelsius(" 38500 "), 38.5);
    assert.ok(Number.isNaN(parseTempCelsius("")));   // ProcReader.read "" on failure
    assert.ok(Number.isNaN(parseTempCelsius(undefined)));
    assert.ok(Number.isNaN(parseTempCelsius("not-a-number")));
});

test("isTempInput / tempIndexFromInput match the hwmon naming", () => {
    assert.ok(isTempInput("temp1_input"));
    assert.ok(isTempInput("temp12_input"));
    assert.ok(!isTempInput("temp1_label"));
    assert.ok(!isTempInput("fan1_input"));
    assert.equal(tempIndexFromInput("temp3_input"), 3);
});

test("buildCatalog uses the <chipName>/temp<N> grammar", () => {
    const catalog = buildCatalog([
        {
            dir: "hwmon2",
            name: "nvme",
            device: "0000:04:00.0",
            sensors: [{ input: "temp1_input", label: "Composite" }],
        },
    ]);
    assert.deepEqual(catalog, [
        { id: "nvme/temp1", label: "Composite", path: "/sys/class/hwmon/hwmon2/temp1_input" },
    ]);
});

test("buildCatalog never bakes the hwmonN number into the id", () => {
    // hwmonN is allocation-order and changes across boots — only the
    // PATH (rebuilt at runtime) may contain it, never the persisted id.
    const catalog = buildCatalog([
        { dir: "hwmon7", name: "k10temp", device: "", sensors: [{ input: "temp1_input", label: "Tctl" }] },
    ]);
    assert.equal(catalog[0].id, "k10temp/temp1");
    assert.match(catalog[0].path, /hwmon7/);
    assert.doesNotMatch(catalog[0].id, /hwmon/);
});

test("buildCatalog disambiguates colliding chip names with @<device>", () => {
    // Two NVMe drives both report name "nvme" — the basename of the
    // device symlink (the PCI address) keeps their ids stable + unique.
    const catalog = buildCatalog([
        {
            dir: "hwmon1",
            name: "nvme",
            device: "0000:04:00.0",
            sensors: [{ input: "temp1_input", label: "Composite" }],
        },
        {
            dir: "hwmon4",
            name: "nvme",
            device: "0000:05:00.0",
            sensors: [{ input: "temp1_input", label: "Composite" }],
        },
    ]);
    assert.deepEqual(catalog.map((e) => e.id), [
        "nvme@0000:04:00.0/temp1",
        "nvme@0000:05:00.0/temp1",
    ]);
});

test("buildCatalog suffixes duplicated picker labels with the id stem", () => {
    // The picker shows labels and maps text back to the FIRST matching
    // id — two drives both labelled "Composite" would make the second
    // one unselectable without the stem suffix (review finding, #167).
    const catalog = buildCatalog([
        {
            dir: "hwmon1",
            name: "nvme",
            device: "0000:04:00.0",
            sensors: [{ input: "temp1_input", label: "Composite" }],
        },
        {
            dir: "hwmon4",
            name: "nvme",
            device: "0000:05:00.0",
            sensors: [{ input: "temp1_input", label: "Composite" }],
        },
        {
            dir: "hwmon2",
            name: "k10temp",
            device: "",
            sensors: [{ input: "temp1_input", label: "Tctl" }],
        },
    ]);
    assert.deepEqual(catalog.map((e) => e.label), [
        "Tctl",                                // unique → untouched
        "Composite (nvme@0000:04:00.0)",
        "Composite (nvme@0000:05:00.0)",
    ]);
});

test("buildCatalog disambiguates duplicated fallback labels too", () => {
    // Unlabeled chips all fall back to "tempN" — collisions are the
    // common case there, not the exception.
    const catalog = buildCatalog([
        { dir: "hwmon0", name: "acpitz", device: "", sensors: [{ input: "temp1_input", label: "" }] },
        { dir: "hwmon3", name: "pch_cannonlake", device: "", sensors: [{ input: "temp1_input", label: "" }] },
    ]);
    assert.deepEqual(catalog.map((e) => e.label), [
        "temp1 (acpitz)",
        "temp1 (pch_cannonlake)",
    ]);
});

test("buildCatalog falls back to the full id when the stem can't split a label group", () => {
    // Same label twice on ONE chip: the stem is identical for both, so
    // only the full id (unique by construction) distinguishes them.
    const catalog = buildCatalog([
        { dir: "hwmon1", name: "nvme", device: "", sensors: [{ input: "temp1_input", label: "Composite" }] },
        { dir: "hwmon4", name: "nvme", device: "", sensors: [{ input: "temp1_input", label: "Composite" }] },
    ]);
    assert.deepEqual(catalog.map((e) => e.label), [
        "Composite (nvme/temp1)",
        "Composite (nvme/temp1)",
    ]);
});

test("buildCatalog counts sensorless chips for collision detection", () => {
    // A sensorless sibling still shares the chip name, so the sensor-
    // bearing chip gets the disambiguated form — the id must not change
    // shape if the sibling grows a sensor after a late modprobe.
    const catalog = buildCatalog([
        { dir: "hwmon0", name: "amdgpu", device: "0000:03:00.0", sensors: [] },
        {
            dir: "hwmon1",
            name: "amdgpu",
            device: "0000:0a:00.0",
            sensors: [{ input: "temp1_input", label: "edge" }],
        },
    ]);
    assert.equal(catalog.length, 1);
    assert.equal(catalog[0].id, "amdgpu@0000:0a:00.0/temp1");
});

test("buildCatalog falls back to the bare name when the device symlink is unresolvable", () => {
    // device "" (readLink failure) must not produce a malformed
    // "chip@/temp1" id — duplicates are tolerated instead
    // (resolveSensorPath returns the first match).
    const catalog = buildCatalog([
        { dir: "hwmon1", name: "nvme", device: "", sensors: [{ input: "temp1_input", label: "" }] },
        { dir: "hwmon4", name: "nvme", device: "", sensors: [{ input: "temp1_input", label: "" }] },
    ]);
    assert.deepEqual(catalog.map((e) => e.id), ["nvme/temp1", "nvme/temp1"]);
});

test("buildCatalog falls back to the input base name when unlabelled", () => {
    // Chips without tempN_label files (acpitz-style) still need a
    // human-meaningful picker label: the input base name.
    const catalog = buildCatalog([
        {
            dir: "hwmon0",
            name: "acpitz",
            device: "",
            sensors: [
                { input: "temp1_input", label: "" },
                { input: "temp2_input", label: "  " },  // whitespace-only counts as empty
            ],
        },
    ]);
    assert.equal(catalog[0].label, "temp1");
    assert.equal(catalog[1].label, "temp2");
});

test("buildCatalog sorts by chip name then numeric sensor index", () => {
    // Enumeration order is readdir-arbitrary; the picker surface must be
    // deterministic. Numeric (not lexical) index order: temp2 < temp10.
    const catalog = buildCatalog([
        {
            dir: "hwmon3",
            name: "nvme",
            device: "",
            sensors: [
                { input: "temp10_input", label: "" },
                { input: "temp2_input", label: "" },
                { input: "temp1_input", label: "" },
            ],
        },
        {
            dir: "hwmon1",
            name: "k10temp",
            device: "",
            sensors: [{ input: "temp2_input", label: "Tdie" }, { input: "temp1_input", label: "Tctl" }],
        },
    ]);
    assert.deepEqual(catalog.map((e) => e.id), [
        "k10temp/temp1",
        "k10temp/temp2",
        "nvme/temp1",
        "nvme/temp2",
        "nvme/temp10",
    ]);
});

test("buildCatalog skips malformed entries instead of throwing", () => {
    const catalog = buildCatalog([
        { dir: "hwmon0", name: "", device: "", sensors: [{ input: "temp1_input", label: "" }] },      // no chip name
        { dir: "hwmon1", name: "nvme", device: "", sensors: null },                                    // no sensor list
        {
            dir: "hwmon2",
            name: "coretemp",
            device: "",
            sensors: [
                { input: "fan1_input", label: "" },     // not a temperature input
                { input: "temp1_label", label: "" },    // label file, not an input
                { input: "temp1_input", label: "Package id 0" },
            ],
        },
    ]);
    assert.deepEqual(catalog, [
        { id: "coretemp/temp1", label: "Package id 0", path: "/sys/class/hwmon/hwmon2/temp1_input" },
    ]);
    assert.deepEqual(buildCatalog([]), []);
    assert.deepEqual(buildCatalog(undefined), []);
    assert.deepEqual(buildCatalog(null), []);
});

test("resolveSensorPath maps an id to its current-boot path", () => {
    const catalog = buildCatalog([
        { dir: "hwmon1", name: "nvme", device: "0000:04:00.0", sensors: [{ input: "temp1_input", label: "" }] },
        { dir: "hwmon2", name: "nvme", device: "0000:05:00.0", sensors: [{ input: "temp1_input", label: "" }] },
        { dir: "hwmon3", name: "k10temp", device: "", sensors: [{ input: "temp1_input", label: "Tctl" }] },
    ]);
    assert.equal(resolveSensorPath(catalog, "k10temp/temp1"), "/sys/class/hwmon/hwmon3/temp1_input");
    // The disambiguated id resolves to ITS drive, not the first nvme.
    assert.equal(resolveSensorPath(catalog, "nvme@0000:05:00.0/temp1"), "/sys/class/hwmon/hwmon2/temp1_input");
});

test("resolveSensorPath returns '' for unknown / empty / malformed input", () => {
    const catalog = buildCatalog([
        { dir: "hwmon3", name: "k10temp", device: "", sensors: [{ input: "temp1_input", label: "Tctl" }] },
    ]);
    // Sensor removed, or enumeration hasn't run yet (empty catalog while
    // the warm-up retry window is still open).
    assert.equal(resolveSensorPath(catalog, "nvme/temp1"), "");
    assert.equal(resolveSensorPath([], "k10temp/temp1"), "");
    assert.equal(resolveSensorPath(catalog, ""), "");
    assert.equal(resolveSensorPath(catalog, undefined), "");
    assert.equal(resolveSensorPath(undefined, "k10temp/temp1"), "");
});
