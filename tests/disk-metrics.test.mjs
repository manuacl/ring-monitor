// Tests for DiskMetrics.js — the shared view-side helpers for the
// multi-partition disk ring (average centre readout + selection filter).

import { createRequire } from "node:module";
import { test } from "node:test";
import assert from "node:assert/strict";

const require = createRequire(import.meta.url);
const Disk = require("../contents/ui/core/DiskMetrics.js");

// ── averagePercent ──────────────────────────────────────────────────

test("averagePercent: empty array → 0", () => {
    assert.equal(Disk.averagePercent([]), 0);
    assert.equal(Disk.averagePercent(null), 0);
    assert.equal(Disk.averagePercent(undefined), 0);
});

test("averagePercent: single value → itself", () => {
    assert.equal(Disk.averagePercent([52]), 52);
});

test("averagePercent: mean of N", () => {
    assert.equal(Disk.averagePercent([10, 20, 30]), 20);
    assert.equal(Disk.averagePercent([52, 8, 26, 67]), (52 + 8 + 26 + 67) / 4);
});

test("averagePercent: any non-finite member → 0 (no NaN sweep)", () => {
    // SCENARIO: a partition value not yet sampled comes through as NaN —
    // the centre must read a clean 0, never NaN (which would glitch the arc).
    assert.equal(Disk.averagePercent([50, NaN]), 0);
    assert.equal(Disk.averagePercent([Infinity, 10]), 0);
    assert.equal(Disk.averagePercent([50, undefined]), 0);
});

// ── selectPartitions ────────────────────────────────────────────────

test("selectPartitions: keeps only discovered ids, in discovery order", () => {
    // The CSV order is ignored — discovery order wins (so the rings stay
    // stable regardless of the order the user clicked the checkboxes).
    const available = ["uuid-a", "uuid-b", "uuid-c"];
    assert.deepEqual(Disk.selectPartitions(available, ["uuid-c", "uuid-a"]), ["uuid-a", "uuid-c"]);
});

test("selectPartitions: drops stale csv ids no longer present", () => {
    // SCENARIO: a USB disk that was selected is now unplugged — its id
    // must vanish from the displayed set rather than render a dead ring.
    assert.deepEqual(Disk.selectPartitions(["uuid-a"], ["uuid-a", "uuid-gone"]), ["uuid-a"]);
});

test("selectPartitions: empty csv → empty (caller falls back to platform default)", () => {
    assert.deepEqual(Disk.selectPartitions(["uuid-a", "uuid-b"], []), []);
    assert.deepEqual(Disk.selectPartitions(["uuid-a"], null), []);
});

test("selectPartitions: empty available → empty", () => {
    assert.deepEqual(Disk.selectPartitions([], ["uuid-a"]), []);
    assert.deepEqual(Disk.selectPartitions(null, ["uuid-a"]), []);
});

// ── sortByLabel ──────────────────────────────────────────────────────

test("sortByLabel: alphabetical, case-insensitive, does not mutate input", () => {
    const input = [
        { id: "u3", label: "sync" },
        { id: "u1", label: "BAZZITE" },
        { id: "u2", label: "photos" },
    ];
    const out = Disk.sortByLabel(input);
    assert.deepEqual(out.map((p) => p.label), ["BAZZITE", "photos", "sync"]);
    // input untouched
    assert.equal(input[0].label, "sync");
});

// ── orderPartitions ──────────────────────────────────────────────────

const AVAIL = [
    { id: "u-bazzite", label: "bazzite" },
    { id: "u-photos", label: "photos" },
    { id: "u-sync", label: "sync" },
];

test("orderPartitions: empty saved order → alphabetical by label (default)", () => {
    const out = Disk.orderPartitions("", AVAIL);
    assert.deepEqual(out.map((p) => p.label), ["bazzite", "photos", "sync"]);
});

test("orderPartitions: saved order respected, kept first", () => {
    const out = Disk.orderPartitions("u-sync,u-bazzite,u-photos", AVAIL);
    assert.deepEqual(out.map((p) => p.id), ["u-sync", "u-bazzite", "u-photos"]);
});

test("orderPartitions: newly-discovered (not in saved) appended alphabetically", () => {
    // SCENARIO: user had saved [sync, bazzite]; a new disk "photos" appears.
    // It must land after the saved ones, alphabetically among new arrivals.
    const out = Disk.orderPartitions("u-sync,u-bazzite", AVAIL);
    assert.deepEqual(out.map((p) => p.id), ["u-sync", "u-bazzite", "u-photos"]);
});

test("orderPartitions: stale saved ids (unplugged) are dropped", () => {
    const out = Disk.orderPartitions("u-gone,u-photos", AVAIL);
    assert.deepEqual(out.map((p) => p.id), ["u-photos", "u-bazzite", "u-sync"]);
});

test("orderPartitions: tolerates empty available", () => {
    assert.deepEqual(Disk.orderPartitions("u-a,u-b", []), []);
    assert.deepEqual(Disk.orderPartitions("", null), []);
});

test("sortByLabel: ties broken by id; tolerates empty/missing", () => {
    assert.deepEqual(Disk.sortByLabel([]), []);
    assert.deepEqual(Disk.sortByLabel(null), []);
    const out = Disk.sortByLabel([
        { id: "b", label: "data" },
        { id: "a", label: "data" },
    ]);
    assert.deepEqual(out.map((p) => p.id), ["a", "b"]);
});
