import { test } from "node:test";
import assert from "node:assert/strict";
import {
    isBatteryDir,
    parseCapacity,
    isCharging,
    parseWeight,
} from "../contents/ui/platforms/standalone/BatteryStatus.js";

// Pure parse helpers for /sys/class/power_supply/ sysfs files.
// The QML adapter does the I/O; these functions classify and parse.

// --- isBatteryDir ---

test("isBatteryDir: BAT0 / BAT1 / BAT_MAIN are batteries", () => {
    assert.ok(isBatteryDir("BAT0"));
    assert.ok(isBatteryDir("BAT1"));
    assert.ok(isBatteryDir("BAT_MAIN"));
    assert.ok(isBatteryDir("BAT99"));
});

test("isBatteryDir: case-insensitive (bat0 is still a battery)", () => {
    // Some firmware ships lowercase names; the check is case-insensitive.
    assert.ok(isBatteryDir("bat0"));
    assert.ok(isBatteryDir("Bat1"));
});

test("isBatteryDir: AC adapter names return false", () => {
    assert.equal(isBatteryDir("AC"), false);
    assert.equal(isBatteryDir("ADP0"), false);
    assert.equal(isBatteryDir("ADP1"), false);
    assert.equal(isBatteryDir("ADP1-1"), false);
    assert.equal(isBatteryDir("mains"), false);
    assert.equal(isBatteryDir("usb"), false);
    assert.equal(isBatteryDir(""), false);
});

// --- parseCapacity ---

test("parseCapacity: integer with no trailing whitespace", () => {
    assert.equal(parseCapacity("85"), 85);
    assert.equal(parseCapacity("0"), 0);
    assert.equal(parseCapacity("100"), 100);
});

test("parseCapacity: strips trailing newline (sysfs style)", () => {
    assert.equal(parseCapacity("72\n"), 72);
    assert.equal(parseCapacity(" 50 "), 50);
});

test("parseCapacity: returns NaN for empty / garbage", () => {
    assert.ok(Number.isNaN(parseCapacity("")));
    assert.ok(Number.isNaN(parseCapacity("not-a-number")));
    assert.ok(Number.isNaN(parseCapacity(undefined)));
    assert.ok(Number.isNaN(parseCapacity(null)));
});

// --- isCharging ---

test("isCharging: 'Charging' returns true", () => {
    assert.equal(isCharging("Charging"), true);
});

test("isCharging: 'Full' returns true (plugged-in at 100%)", () => {
    // A full battery means power is connected; should show as charging.
    assert.equal(isCharging("Full"), true);
});

test("isCharging: 'Discharging' returns false", () => {
    assert.equal(isCharging("Discharging"), false);
});

test("isCharging: 'Not charging' returns false", () => {
    assert.equal(isCharging("Not charging"), false);
});

test("isCharging: 'Unknown' returns false", () => {
    assert.equal(isCharging("Unknown"), false);
});

test("isCharging: empty string returns false", () => {
    assert.equal(isCharging(""), false);
});

test("isCharging: case-insensitive ('CHARGING', 'full')", () => {
    assert.equal(isCharging("CHARGING"), true);
    assert.equal(isCharging("full"), true);
    assert.equal(isCharging("FULL"), true);
});

test("isCharging: strips surrounding whitespace (sysfs newline)", () => {
    assert.equal(isCharging("Charging\n"), true);
    assert.equal(isCharging(" Full "), true);
    assert.equal(isCharging("Discharging\n"), false);
});

test("isCharging: undefined / null return false", () => {
    assert.equal(isCharging(undefined), false);
    assert.equal(isCharging(null), false);
});

// --- parseWeight ---

test("parseWeight: valid integer returns that integer", () => {
    assert.equal(parseWeight("50000000"), 50000000);
    assert.equal(parseWeight("1"), 1);
});

test("parseWeight: strips trailing newline (sysfs style)", () => {
    assert.equal(parseWeight("40000\n"), 40000);
    assert.equal(parseWeight(" 30000 "), 30000);
});

test("parseWeight: missing / empty file → 1 (fall back to simple mean)", () => {
    // When energy_full / charge_full is absent the backend passes "".
    assert.equal(parseWeight(""), 1);
    assert.equal(parseWeight(undefined), 1);
    assert.equal(parseWeight(null), 1);
});

test("parseWeight: garbage string → 1", () => {
    assert.equal(parseWeight("not-a-number"), 1);
});

test("parseWeight: zero or negative → 1 (non-positive weight is meaningless)", () => {
    assert.equal(parseWeight("0"), 1);
    assert.equal(parseWeight("-5000"), 1);
});

test("parseWeight: returns a finite positive number in the normal case", () => {
    const w = parseWeight("48000000");
    assert.ok(isFinite(w) && w > 0, "weight must be finite and positive");
});
