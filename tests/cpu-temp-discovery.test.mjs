import { test } from "node:test";
import assert from "node:assert/strict";
import {
    CPU_HWMON_NAMES,
    CPU_THERMAL_ZONE_TYPES,
    parseTempCelsius,
    isTempInput,
    tempIndexFromInput,
    pickCpuHwmonDir,
    pickCpuTempInput,
    pickCpuThermalZone,
} from "../contents/ui/platforms/standalone/CpuTempDiscovery.js";

// Pure discovery logic for the standalone CPU-temperature sensor. The
// QML adapter does the sysfs I/O (ProcReader.listDir + read); these
// functions decide which entry is the CPU. Vendor-agnostic by design
// — see CpuTempDiscovery.js header.

test("parseTempCelsius converts millidegrees to °C", () => {
    assert.equal(parseTempCelsius("45000"), 45);
    assert.equal(parseTempCelsius("45000\n"), 45);   // trailing newline from sysfs
    assert.equal(parseTempCelsius(" 38500 "), 38.5);
    assert.equal(parseTempCelsius("-5000"), -5);     // negative is physically possible
});

test("parseTempCelsius returns NaN for empty / garbage input", () => {
    // ProcReader.read returns "" on a refused/missing path; the backend
    // must treat that as "unavailable", not 0°C.
    assert.ok(Number.isNaN(parseTempCelsius("")));
    assert.ok(Number.isNaN(parseTempCelsius(undefined)));
    assert.ok(Number.isNaN(parseTempCelsius(null)));
    assert.ok(Number.isNaN(parseTempCelsius("not-a-number")));
});

test("isTempInput / tempIndexFromInput match the hwmon naming", () => {
    assert.ok(isTempInput("temp1_input"));
    assert.ok(isTempInput("temp12_input"));
    assert.ok(!isTempInput("temp1_label"));
    assert.ok(!isTempInput("temp1_crit"));
    assert.ok(!isTempInput("name"));
    assert.equal(tempIndexFromInput("temp1_input"), 1);
    assert.equal(tempIndexFromInput("temp12_input"), 12);
    assert.ok(Number.isNaN(tempIndexFromInput("name")));
});

test("pickCpuHwmonDir prefers a CPU chip over unrelated chips", () => {
    // The real layout this code was written against (dev box): coretemp
    // is the CPU, the rest are nvme / chipset / wmi / battery sensors.
    const entries = [
        { dir: "hwmon0", name: "acpitz" },
        { dir: "hwmon1", name: "nvme" },
        { dir: "hwmon2", name: "pch_cannonlake" },
        { dir: "hwmon3", name: "gigabyte_wmi" },
        { dir: "hwmon4", name: "coretemp" },
        { dir: "hwmon5", name: "hidpp_battery_0" },
    ];
    assert.equal(pickCpuHwmonDir(entries), "hwmon4");
});

test("pickCpuHwmonDir ignores acpitz (thermal-zone fallback owns it)", () => {
    // A real CPU driver must win over acpitz.
    assert.equal(pickCpuHwmonDir([
        { dir: "hwmon0", name: "acpitz" },
        { dir: "hwmon1", name: "k10temp" },
    ]), "hwmon1");
    assert.equal(pickCpuHwmonDir([
        { dir: "hwmon0", name: "acpitz" },
        { dir: "hwmon1", name: "zenpower" },
    ]), "hwmon1");
    // acpitz is NOT a hwmon CPU chip: an acpitz-only hwmon set yields ""
    // so the backend falls through to the thermal-zone path (where
    // acpitz is accepted, but only after the real CPU zones). Without
    // this, acpitz-in-hwmon would short-circuit a better x86_pkg_temp
    // thermal zone on a machine exposing both.
    assert.equal(pickCpuHwmonDir([{ dir: "hwmon0", name: "acpitz" }]), "");
});

test("pickCpuHwmonDir returns '' when no CPU chip is present", () => {
    assert.equal(pickCpuHwmonDir([
        { dir: "hwmon0", name: "nvme" },
        { dir: "hwmon1", name: "gigabyte_wmi" },
    ]), "");
    assert.equal(pickCpuHwmonDir([]), "");
    assert.equal(pickCpuHwmonDir(undefined), "");
});

test("pickCpuTempInput prefers the package label (Intel coretemp)", () => {
    // Real coretemp layout: temp1 = "Package id 0", temp2.. = per-core.
    const sensors = [
        { input: "temp1_input", label: "Package id 0" },
        { input: "temp2_input", label: "Core 0" },
        { input: "temp3_input", label: "Core 1" },
    ];
    assert.equal(pickCpuTempInput(sensors), "temp1_input");
});

test("pickCpuTempInput prefers Tctl/Tdie (AMD k10temp)", () => {
    assert.equal(pickCpuTempInput([
        { input: "temp1_input", label: "Tctl" },
        { input: "temp2_input", label: "Tdie" },
        { input: "temp3_input", label: "Tccd1" },
    ]), "temp1_input");
    // Tdie beats per-CCD when Tctl is absent.
    assert.equal(pickCpuTempInput([
        { input: "temp2_input", label: "Tccd1" },
        { input: "temp1_input", label: "Tdie" },
    ]), "temp1_input");
});

test("pickCpuTempInput falls back to lowest index when unlabelled", () => {
    // acpitz-style chips expose temp1_input with no temp1_label file.
    assert.equal(pickCpuTempInput([
        { input: "temp2_input", label: "" },
        { input: "temp1_input", label: "" },
    ]), "temp1_input");
    assert.equal(pickCpuTempInput([]), "");
});

test("pickCpuThermalZone matches CPU zone types, prefers x86_pkg_temp", () => {
    // Real layout: zones 0/1 acpitz, zone3 x86_pkg_temp (the CPU).
    assert.equal(pickCpuThermalZone([
        { dir: "thermal_zone0", type: "acpitz" },
        { dir: "thermal_zone1", type: "acpitz" },
        { dir: "thermal_zone2", type: "pch_cannonlake" },
        { dir: "thermal_zone3", type: "x86_pkg_temp" },
    ]), "thermal_zone3");
    // Raspberry Pi style.
    assert.equal(pickCpuThermalZone([
        { dir: "thermal_zone0", type: "cpu-thermal" },
    ]), "thermal_zone0");
    assert.equal(pickCpuThermalZone([
        { dir: "thermal_zone0", type: "pch_cannonlake" },
    ]), "");
});

test("priority lists are non-empty, and acpitz is thermal-zone-only", () => {
    assert.ok(CPU_HWMON_NAMES.length >= 6);
    // acpitz must NOT be a hwmon CPU chip — it would otherwise
    // short-circuit the thermal-zone fallback (see pickCpuHwmonDir test).
    assert.equal(CPU_HWMON_NAMES.indexOf("acpitz"), -1, "acpitz must not be in CPU_HWMON_NAMES");
    // In the thermal-zone list acpitz is the LAST resort, after real
    // CPU zones like x86_pkg_temp.
    assert.ok(CPU_THERMAL_ZONE_TYPES.indexOf("acpitz") >= 0, "acpitz must remain the thermal-zone fallback");
    assert.ok(CPU_THERMAL_ZONE_TYPES.indexOf("x86_pkg_temp") < CPU_THERMAL_ZONE_TYPES.indexOf("acpitz"));
});
