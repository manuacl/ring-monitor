// Spec for GpuTooltipModel (issue #71 — GPU-ring hover tooltip).
//
// Run:  node --test tests/gpu-tooltip-model.test.mjs
//
// Implementation: contents/ui/core/GpuTooltipModel.js. Pure presentational
// logic shared by both platform backends, so it lives in core/.

import { createRequire } from "node:module";
import { test } from "node:test";
import assert from "node:assert/strict";

const require = createRequire(import.meta.url);
const M = require("../contents/ui/core/GpuTooltipModel.js");

const MiB = 1024 * 1024;
const GiB = 1024 * MiB;

// ── DEFAULT_LIMIT ────────────────────────────────────────────────────

test("DEFAULT_LIMIT is 20", () => {
    assert.equal(M.DEFAULT_LIMIT, 20);
});

// ── formatVram ───────────────────────────────────────────────────────

test("formatVram: bytes stay whole, no decimal", () => {
    assert.equal(M.formatVram(0), "0 B");
    assert.equal(M.formatVram(512), "512 B");
    assert.equal(M.formatVram(1023), "1023 B");
});

test("formatVram: steps to IEC units at 1024", () => {
    assert.equal(M.formatVram(1024), "1.0 KiB");
    assert.equal(M.formatVram(MiB), "1.0 MiB");
    assert.equal(M.formatVram(GiB), "1.0 GiB");
    assert.equal(M.formatVram(8 * GiB), "8.0 GiB");
    assert.equal(M.formatVram(24 * GiB), "24 GiB");
    assert.equal(M.formatVram(512 * MiB), "512 MiB");
});

test("formatVram: one decimal below 10, integer at/above", () => {
    assert.equal(M.formatVram(6.2 * GiB), "6.2 GiB");
    assert.equal(M.formatVram(9.3 * GiB), "9.3 GiB");
    assert.equal(M.formatVram(10 * GiB), "10 GiB");
    assert.equal(M.formatVram(16 * GiB), "16 GiB");
});

test("formatVram: promotes at the rounding boundary, never '1024 GiB'", () => {
    assert.equal(M.formatVram(1023.7 * GiB), "1.0 TiB");
    assert.equal(M.formatVram(1023.4 * GiB), "1023 GiB");
});

test("formatVram: NaN / negative / undefined coerce to 0 B", () => {
    assert.equal(M.formatVram(NaN), "0 B");
    assert.equal(M.formatVram(-100), "0 B");
    assert.equal(M.formatVram(undefined), "0 B");
});

// ── formatPower ──────────────────────────────────────────────────────

test("formatPower: one decimal below 100 W", () => {
    assert.equal(M.formatPower(42.5), "42.5 W");
    assert.equal(M.formatPower(0), "0.0 W");
    assert.equal(M.formatPower(99.9), "99.9 W");
    assert.equal(M.formatPower(5), "5.0 W");
});

test("formatPower: integer at/above 100 W", () => {
    assert.equal(M.formatPower(100), "100 W");
    assert.equal(M.formatPower(115), "115 W");
    assert.equal(M.formatPower(350), "350 W");
    assert.equal(M.formatPower(115.7), "116 W");
});

test("formatPower: absent (null / NaN / undefined / Infinity) → empty string", () => {
    // null is an ABSENT sentinel, NOT a valid 0 W reading — a backend that
    // emits null for an unread sensor must drop the row, not show "0.0 W".
    // (0 itself, a real reading, stays "0.0 W" — see the test above.)
    assert.equal(M.formatPower(null), "");
    assert.equal(M.formatPower(NaN), "");
    assert.equal(M.formatPower(undefined), "");
    assert.equal(M.formatPower(Infinity), "");
    assert.equal(M.formatPower(-Infinity), "");
});

// ── formatClock ──────────────────────────────────────────────────────

test("formatClock: integer MHz", () => {
    assert.equal(M.formatClock(1815), "1815 MHz");
    assert.equal(M.formatClock(300), "300 MHz");
    assert.equal(M.formatClock(2100.6), "2101 MHz");
    assert.equal(M.formatClock(0), "0 MHz");
});

test("formatClock: absent / null / NaN / undefined → empty string", () => {
    assert.equal(M.formatClock(null), "");
    assert.equal(M.formatClock(NaN), "");
    assert.equal(M.formatClock(undefined), "");
    assert.equal(M.formatClock(Infinity), "");
});

// ── formatPercent ────────────────────────────────────────────────────

test("formatPercent: rounded integer with % sign", () => {
    assert.equal(M.formatPercent(73), "73%");
    assert.equal(M.formatPercent(0), "0%");
    assert.equal(M.formatPercent(100), "100%");
    assert.equal(M.formatPercent(73.6), "74%");
    assert.equal(M.formatPercent(73.4), "73%");
});

test("formatPercent: NaN / undefined coerce to 0%", () => {
    assert.equal(M.formatPercent(NaN), "0%");
    assert.equal(M.formatPercent(undefined), "0%");
});

test("formatPercent: negative floors to 0%", () => {
    assert.equal(M.formatPercent(-5), "0%");
});

// ── composeVram ──────────────────────────────────────────────────────

test("composeVram: used / total · percent when total known", () => {
    // 6 GiB used / 24 GiB total → 25%
    assert.equal(M.composeVram(6 * GiB, 24 * GiB), "6.0 GiB / 24 GiB · 25%");
});

test("composeVram: rounds percent", () => {
    // 1 GiB / 3 GiB → 33.3% rounds to 33%
    assert.equal(M.composeVram(GiB, 3 * GiB), "1.0 GiB / 3.0 GiB · 33%");
});

test("composeVram: empty when total is zero or absent", () => {
    assert.equal(M.composeVram(6 * GiB, 0), "");
    assert.equal(M.composeVram(6 * GiB, NaN), "");
    assert.equal(M.composeVram(6 * GiB, undefined), "");
});

test("composeVram: empty when total is negative", () => {
    assert.equal(M.composeVram(6 * GiB, -1), "");
});

test("composeVram: used absent/NaN treats used as 0", () => {
    assert.equal(M.composeVram(undefined, 8 * GiB), "0 B / 8.0 GiB · 0%");
    assert.equal(M.composeVram(NaN, 8 * GiB), "0 B / 8.0 GiB · 0%");
});

test("composeVram: used negative clamps to 0", () => {
    assert.equal(M.composeVram(-1 * GiB, 8 * GiB), "0 B / 8.0 GiB · 0%");
});

test("composeVram: percent clamps to 100 when used exceeds total", () => {
    // Transient sample (used > total) must not render "108%".
    assert.equal(M.composeVram(26 * GiB, 24 * GiB), "26 GiB / 24 GiB · 100%");
});

// ── buildStatRows ────────────────────────────────────────────────────

test("buildStatRows: full NVIDIA detail → all 6 rows in order", () => {
    const rows = M.buildStatRows({
        model: "NVIDIA RTX 4090",
        usagePercent: 73,
        vramUsedBytes: 6 * GiB,
        vramTotalBytes: 24 * GiB,
        tempC: 71.7,
        powerW: 115,
        clockMhz: 1815
    });
    assert.equal(rows.length, 6);
    assert.deepEqual(rows[0], { label: "Model",       value: "NVIDIA RTX 4090" });
    assert.deepEqual(rows[1], { label: "Usage",        value: "73%" });
    assert.deepEqual(rows[2], { label: "VRAM",         value: "6.0 GiB / 24 GiB · 25%" });
    assert.deepEqual(rows[3], { label: "Temperature",  value: "72 °C" });
    assert.deepEqual(rows[4], { label: "Power",        value: "115 W" });
    assert.deepEqual(rows[5], { label: "Clock",        value: "1815 MHz" });
});

test("buildStatRows: Intel sparse detail → only rows whose sensor is present", () => {
    // Intel GPU: model name present, usage present, temperature present;
    // no VRAM total, no power sensor, no clock reported.
    const rows = M.buildStatRows({
        model: "Intel Arc A770",
        usagePercent: 12,
        tempC: 55
    });
    assert.equal(rows.length, 3);
    assert.equal(rows[0].label, "Model");
    assert.equal(rows[1].label, "Usage");
    assert.equal(rows[2].label, "Temperature");
});

test("buildStatRows: skips Model row when model is absent", () => {
    const rows = M.buildStatRows({ usagePercent: 50, tempC: 60 });
    assert.equal(rows.length, 2);
    assert.equal(rows[0].label, "Usage");
});

test("buildStatRows: skips Usage row when usagePercent is absent/NaN", () => {
    const rows = M.buildStatRows({ model: "GPU", usagePercent: NaN });
    assert.equal(rows.length, 1);
    assert.equal(rows[0].label, "Model");
});

test("buildStatRows: 0% usage is a valid reading — kept, not skipped", () => {
    const rows = M.buildStatRows({ usagePercent: 0 });
    assert.equal(rows.length, 1);
    assert.equal(rows[0].label, "Usage");
    assert.equal(rows[0].value, "0%");
});

test("buildStatRows: 0 °C temperature is kept (valid reading)", () => {
    const rows = M.buildStatRows({ tempC: 0 });
    assert.equal(rows.length, 1);
    assert.equal(rows[0].label, "Temperature");
    assert.equal(rows[0].value, "0 °C");
});

test("buildStatRows: VRAM skipped when total unknown, kept when total present", () => {
    const withTotal = M.buildStatRows({ vramUsedBytes: 2 * GiB, vramTotalBytes: 8 * GiB });
    assert.equal(withTotal.length, 1);
    assert.equal(withTotal[0].label, "VRAM");

    const noTotal = M.buildStatRows({ vramUsedBytes: 2 * GiB });
    assert.equal(noTotal.length, 0);
});

test("buildStatRows: Temperature value rounds to integer °C", () => {
    const rows = M.buildStatRows({ tempC: 71.7 });
    assert.equal(rows[0].value, "72 °C");
});

test("buildStatRows: Power row uses formatPower thresholds", () => {
    const low = M.buildStatRows({ powerW: 42.5 });
    assert.equal(low[0].value, "42.5 W");

    const high = M.buildStatRows({ powerW: 350 });
    assert.equal(high[0].value, "350 W");
});

test("buildStatRows: empty detail object → empty rows", () => {
    assert.deepEqual(M.buildStatRows({}), []);
});

test("buildStatRows: null/undefined detail → empty rows", () => {
    assert.deepEqual(M.buildStatRows(null), []);
    assert.deepEqual(M.buildStatRows(undefined), []);
});

test("buildStatRows: null sensor fields are absent, not 0 (no fake rows)", () => {
    // A backend emitting null for an unread sensor must drop the row, not
    // render "0%" / "0 °C" / "0 W". Only `model: null` and the byte fields
    // here — usage/temp/power/clock all null → no rows.
    const rows = M.buildStatRows({
        model: null,
        usagePercent: null,
        vramUsedBytes: null,
        vramTotalBytes: null,
        tempC: null,
        powerW: null,
        clockMhz: null
    });
    assert.deepEqual(rows, []);
});

// ── rankProcesses ────────────────────────────────────────────────────

test("rankProcesses: sorts by vramBytes descending", () => {
    const out = M.rankProcesses([
        { pid: 1, name: "a", vramBytes: 100 * MiB },
        { pid: 2, name: "b", vramBytes: 8 * GiB },
        { pid: 3, name: "c", vramBytes: 500 * MiB }
    ]);
    assert.deepEqual(out.map(r => r.name), ["b", "c", "a"]);
});

test("rankProcesses: tiebreak by pid ascending (deterministic, no flicker)", () => {
    const out = M.rankProcesses([
        { pid: 9, name: "late",  vramBytes: GiB },
        { pid: 2, name: "early", vramBytes: GiB },
        { pid: 5, name: "mid",   vramBytes: GiB }
    ]);
    assert.deepEqual(out.map(r => r.pid), [2, 5, 9]);
});

test("rankProcesses: caps to the given limit", () => {
    const input = [
        { pid: 1, name: "a", vramBytes: 100 },
        { pid: 2, name: "b", vramBytes: 200 },
        { pid: 3, name: "c", vramBytes: 300 },
        { pid: 4, name: "d", vramBytes: 400 }
    ];
    assert.equal(M.rankProcesses(input, 2).length, 2);
    assert.deepEqual(M.rankProcesses(input, 2).map(r => r.name), ["d", "c"]);
});

test("rankProcesses: defaults to DEFAULT_LIMIT (20) when limit omitted", () => {
    const input = [];
    for (let i = 0; i < 50; i++)
        input.push({ pid: i, name: "p" + i, vramBytes: i * MiB });
    assert.equal(M.rankProcesses(input).length, 20);
});

test("rankProcesses: absent vramBytes ranks as 0 (kept, not dropped)", () => {
    const out = M.rankProcesses([
        { pid: 1, name: "norss" },
        { pid: 2, name: "hasvram", vramBytes: 512 * MiB }
    ]);
    assert.equal(out.length, 2);
    assert.equal(out[0].name, "hasvram");
    assert.equal(out[1].name, "norss");
    assert.equal(out[1].vramBytes, 0);
});

test("rankProcesses: NaN / negative vramBytes ranks as 0", () => {
    const out = M.rankProcesses([
        { pid: 1, name: "nan",  vramBytes: NaN },
        { pid: 2, name: "neg",  vramBytes: -100 },
        { pid: 3, name: "good", vramBytes: MiB }
    ]);
    assert.equal(out[0].name, "good");
    assert.equal(out[1].vramBytes, 0);
    assert.equal(out[2].vramBytes, 0);
});

test("rankProcesses: drops records with no pid", () => {
    const out = M.rankProcesses([
        { pid: 1, name: "a", vramBytes: 100 },
        { name: "nopid", vramBytes: 999 },
        { pid: null, vramBytes: 800 }
    ]);
    assert.deepEqual(out.map(r => r.name), ["a"]);
});

test("rankProcesses: non-array input → empty array", () => {
    assert.deepEqual(M.rankProcesses(null), []);
    assert.deepEqual(M.rankProcesses(undefined), []);
    assert.deepEqual(M.rankProcesses("not-an-array"), []);
});

// SCENARIO (#71 live): a C++ QVariantList (NvmlReader.runningProcesses) reaches
// QML as an array-LIKE object, NOT a true Array — Array.isArray() is false for
// it. An Array.isArray guard stays green here yet dropped every live process
// (standalone showed raw=22 → ranked=0). Pin the array-like path: a plain
// object with numeric .length + indexed entries must be ranked, not dropped.
test("rankProcesses: array-like (QVariantList) input is processed, not dropped", () => {
    const arrayLike = { length: 2, 0: { pid: 2, name: "b", vramBytes: GiB }, 1: { pid: 1, name: "a", vramBytes: 2 * GiB } };
    const out = M.rankProcesses(arrayLike);
    assert.equal(out.length, 2);
    assert.deepEqual(out.map(r => r.pid), [1, 2]);   // sorted by vram desc
});

test("rankProcesses: non-positive limit → empty array", () => {
    assert.deepEqual(M.rankProcesses([{ pid: 1, name: "a", vramBytes: 100 }], 0), []);
    assert.deepEqual(M.rankProcesses([{ pid: 1, name: "a", vramBytes: 100 }], -1), []);
});

test("rankProcesses: does not mutate the input array", () => {
    const input = [
        { pid: 2, name: "b", vramBytes: GiB },
        { pid: 1, name: "a", vramBytes: 2 * GiB }
    ];
    const snapshot = input.map(r => r.pid);
    M.rankProcesses(input);
    assert.deepEqual(input.map(r => r.pid), snapshot);
});

test("rankProcesses: missing name becomes empty string", () => {
    const out = M.rankProcesses([{ pid: 7, vramBytes: 100 }]);
    assert.equal(out[0].name, "");
});

// ── formatProcessVram ────────────────────────────────────────────────

test("formatProcessVram: alias for formatVram, same output", () => {
    assert.equal(M.formatProcessVram(8 * GiB), M.formatVram(8 * GiB));
    assert.equal(M.formatProcessVram(512 * MiB), "512 MiB");
    assert.equal(M.formatProcessVram(0), "0 B");
    assert.equal(M.formatProcessVram(undefined), "0 B");
});

// ── dedupeByPid ──────────────────────────────────────────────────────

test("dedupeByPid: collapses two entries with the same pid, keeping max vramBytes", () => {
    const out = M.dedupeByPid([
        { pid: 42, name: "a", vramBytes: 100 * MiB },
        { pid: 42, name: "a", vramBytes: 300 * MiB }
    ]);
    assert.equal(out.length, 1);
    assert.equal(out[0].pid, 42);
    assert.equal(out[0].vramBytes, 300 * MiB);
});

test("dedupeByPid: keeps distinct pids untouched", () => {
    const input = [
        { pid: 1, name: "a", vramBytes: 100 * MiB },
        { pid: 2, name: "b", vramBytes: 200 * MiB }
    ];
    const out = M.dedupeByPid(input);
    assert.equal(out.length, 2);
    assert.equal(out[0].pid, 1);
    assert.equal(out[1].pid, 2);
});

test("dedupeByPid: non-array input → empty array", () => {
    assert.deepEqual(M.dedupeByPid(null), []);
    assert.deepEqual(M.dedupeByPid(undefined), []);
    assert.deepEqual(M.dedupeByPid("not-an-array"), []);
    assert.deepEqual(M.dedupeByPid(42), []);
});

// SCENARIO (#71 live): the QVariantList from NvmlReader.runningProcesses arrives
// as an array-LIKE object (numeric .length, indexed), not a true Array. The
// Array.isArray guard returned [] for it → no GPU processes ever shown. Guard
// must accept array-likes; index access is all dedupe needs.
test("dedupeByPid: array-like (QVariantList) input is processed, not dropped", () => {
    const arrayLike = { length: 2, 0: { pid: 42, name: "a", vramBytes: 100 * MiB }, 1: { pid: 42, name: "a", vramBytes: 300 * MiB } };
    const out = M.dedupeByPid(arrayLike);
    assert.equal(out.length, 1);
    assert.equal(out[0].vramBytes, 300 * MiB);
});

test("dedupeByPid: skips records with missing or NaN pid", () => {
    const out = M.dedupeByPid([
        { pid: 1,         name: "good", vramBytes: 100 * MiB },
        { name: "nopid",  vramBytes: 200 * MiB },
        { pid: null,      name: "nullpid", vramBytes: 300 * MiB },
        { pid: NaN,       name: "nanpid",  vramBytes: 400 * MiB }
    ]);
    assert.equal(out.length, 1);
    assert.equal(out[0].pid, 1);
});

test("dedupeByPid: does not mutate the input array", () => {
    const input = [
        { pid: 1, name: "a", vramBytes: 100 * MiB },
        { pid: 1, name: "a", vramBytes: 200 * MiB }
    ];
    const snapshot = JSON.parse(JSON.stringify(input));
    M.dedupeByPid(input);
    assert.deepEqual(input, snapshot);
});

test("dedupeByPid: coerces negative vramBytes to 0", () => {
    const out = M.dedupeByPid([
        { pid: 7, name: "a", vramBytes: -500 }
    ]);
    assert.equal(out.length, 1);
    assert.equal(out[0].vramBytes, 0);
});

test("dedupeByPid: coerces non-finite vramBytes to 0", () => {
    const out = M.dedupeByPid([
        { pid: 7, name: "a", vramBytes: Infinity },
        { pid: 8, name: "b", vramBytes: NaN }
    ]);
    assert.equal(out.length, 2);
    assert.equal(out[0].vramBytes, 0);
    assert.equal(out[1].vramBytes, 0);
});

test("dedupeByPid: tie on vramBytes keeps first-seen record (distinguishable by name)", () => {
    const out = M.dedupeByPid([
        { pid: 5, name: "first",  vramBytes: GiB },
        { pid: 5, name: "second", vramBytes: GiB }
    ]);
    assert.equal(out.length, 1);
    assert.equal(out[0].name, "first");
});
