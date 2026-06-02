// Spec for DiskTooltipModel (issue #68 — disk-ring hover tooltip).
//
// Run:  node --test tests/disk-tooltip-model.test.mjs
//
// Implementation: contents/ui/core/DiskTooltipModel.js. Pure presentational
// logic shared by both platform backends, so it lives in core/.

import { createRequire } from "node:module";
import { test } from "node:test";
import assert from "node:assert/strict";

const require = createRequire(import.meta.url);
const M = require("../contents/ui/core/DiskTooltipModel.js");

const KiB = 1024;
const MiB = 1024 * KiB;
const GiB = 1024 * MiB;
const TiB = 1024 * GiB;

// ── formatSize ──────────────────────────────────────────────────────

test("formatSize: bytes stay whole, no decimal", () => {
    assert.equal(M.formatSize(0), "0 B");
    assert.equal(M.formatSize(512), "512 B");
    assert.equal(M.formatSize(1023), "1023 B");
});

test("formatSize: steps to IEC binary units at 1024", () => {
    assert.equal(M.formatSize(KiB), "1.0 KiB");
    assert.equal(M.formatSize(1536), "1.5 KiB");
    assert.equal(M.formatSize(MiB), "1.0 MiB");
    assert.equal(M.formatSize(GiB), "1.0 GiB");
    assert.equal(M.formatSize(TiB), "1.0 TiB");
});

test("formatSize: one decimal below 10, integer at/above (df -h style)", () => {
    assert.equal(M.formatSize(9.3 * GiB), "9.3 GiB");
    assert.equal(M.formatSize(56 * GiB), "56 GiB");
    assert.equal(M.formatSize(466 * GiB), "466 GiB");
});

test("formatSize: promotes at the rounding boundary, never '1024 GiB'", () => {
    assert.equal(M.formatSize(1023.7 * GiB), "1.0 TiB");
});

test("formatSize: caps at PiB (no unit past the table)", () => {
    assert.equal(M.formatSize(5000 * 1024 * TiB), "5000 PiB");
});

test("formatSize: NaN / negative / undefined coerce to 0 B", () => {
    assert.equal(M.formatSize(NaN), "0 B");
    assert.equal(M.formatSize(-100), "0 B");
    assert.equal(M.formatSize(undefined), "0 B");
});

// ── composeUsage ────────────────────────────────────────────────────

test("composeUsage: full line with rounded % and both figures", () => {
    assert.equal(M.composeUsage(12, 56 * GiB, 466 * GiB), "12% — 56 GiB / 466 GiB");
});

test("composeUsage: % rounds; reads the ring's value, not recomputed", () => {
    // usedPercent is taken as-is (the gauge's number), independent of bytes.
    assert.equal(M.composeUsage(12.6, 56 * GiB, 466 * GiB), "13% — 56 GiB / 466 GiB");
});

test("composeUsage: total unknown → just the percent", () => {
    assert.equal(M.composeUsage(40, 0, 0), "40%");
    assert.equal(M.composeUsage(40, 0, NaN), "40%");
});

test("composeUsage: negative / NaN percent floors to 0%", () => {
    assert.equal(M.composeUsage(-5, 0, 0), "0%");
    assert.equal(M.composeUsage(NaN, 0, 0), "0%");
});

// ── composeFree ─────────────────────────────────────────────────────

test("composeFree: '<size> free' when total is known", () => {
    assert.equal(M.composeFree(120 * GiB, 466 * GiB), "120 GiB free");
});

test("composeFree: empty when total unknown (no misleading '0 B free')", () => {
    assert.equal(M.composeFree(0, 0), "");
    assert.equal(M.composeFree(50 * GiB, NaN), "");
});

// ── subLabel ────────────────────────────────────────────────────────

test("subLabel: mountpoint · fstype", () => {
    assert.equal(M.subLabel("/", "btrfs"), "/ · btrfs");
    assert.equal(M.subLabel("/run/media/usb", "vfat"), "/run/media/usb · vfat");
});

test("subLabel: one side missing → the other alone", () => {
    assert.equal(M.subLabel("/home", ""), "/home");
    assert.equal(M.subLabel("", "ext4"), "ext4");
    assert.equal(M.subLabel(undefined, undefined), "");
});

// ── iconFor ─────────────────────────────────────────────────────────

test("iconFor: removable vs fixed icon names", () => {
    assert.equal(M.iconFor(true), "drive-removable-media");
    assert.equal(M.iconFor(false), "drive-harddisk");
});

// ── buildRows ───────────────────────────────────────────────────────

test("buildRows: maps a detail to the presentational row", () => {
    const rows = M.buildRows([{
        id: "uuid-1",
        label: "root",
        mountpoint: "/",
        fstype: "btrfs",
        usedPercent: 12,
        totalBytes: 466 * GiB,
        freeBytes: 410 * GiB,
        removable: false
    }]);
    assert.equal(rows.length, 1);
    assert.deepEqual(rows[0], {
        id: "uuid-1",
        label: "root",
        subLabel: "/ · btrfs",
        usageText: "12% — 56 GiB / 466 GiB",
        freeText: "410 GiB free",
        iconName: "drive-harddisk",
        removable: false
    });
});

test("buildRows: derives used = total - free, clamped at 0", () => {
    // free > total (transient inconsistency between sources) → used floors to 0.
    const rows = M.buildRows([{ totalBytes: 100 * GiB, freeBytes: 120 * GiB, usedPercent: 0 }]);
    assert.equal(rows[0].usageText, "0% — 0 B / 100 GiB");
});

test("buildRows: removable → removable icon", () => {
    const rows = M.buildRows([{ id: "u", label: "USB", removable: true, usedPercent: 30, totalBytes: 16 * GiB, freeBytes: 11 * GiB }]);
    assert.equal(rows[0].iconName, "drive-removable-media");
    assert.equal(rows[0].removable, true);
});

test("buildRows: label falls back to id when absent", () => {
    const rows = M.buildRows([{ id: "uuid-x", usedPercent: 0 }]);
    assert.equal(rows[0].label, "uuid-x");
});

test("buildRows: bytes absent → percent-only usage, no free line", () => {
    const rows = M.buildRows([{ id: "u", label: "root", mountpoint: "/", fstype: "ext4", usedPercent: 40 }]);
    assert.equal(rows[0].usageText, "40%");
    assert.equal(rows[0].freeText, "");
});

test("buildRows: non-array input → empty list", () => {
    assert.deepEqual(M.buildRows(undefined), []);
    assert.deepEqual(M.buildRows(null), []);
});

// ── boundary cases (code-review #122 recall pass) ───────────────────

test("formatSize: exact promote boundary — 1023.5 GiB promotes, 1023.4 GiB does not", () => {
    assert.equal(M.formatSize(1023.5 * GiB), "1.0 TiB"); // b >= 1023.5 → promote
    assert.equal(M.formatSize(1023.4 * GiB), "1023 GiB"); // just below → stays
});

test("formatSize: the <10 decimal threshold — 10 is integer, 9.94 keeps one decimal", () => {
    assert.equal(M.formatSize(10 * GiB), "10 GiB");   // b<10 false → integer, not "10.0"
    assert.equal(M.formatSize(9.94 * GiB), "9.9 GiB"); // below 10 → one decimal
});

test("composeFree: free > total is shown as-is (transient source skew, not clamped here)", () => {
    // buildRows clamps `used` to 0, but composeFree reports freeBytes verbatim —
    // the figure is illustrative; the % stays the authoritative number.
    assert.equal(M.composeFree(120 * GiB, 100 * GiB), "120 GiB free");
});

test("composeUsage: used > total passes through (clamping is buildRows' job, not this layer's)", () => {
    assert.equal(M.composeUsage(25, 150 * GiB, 100 * GiB), "25% — 150 GiB / 100 GiB");
});
