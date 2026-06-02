// TDD spec for DiskStatsParser (issue #77 — standalone /proc/diskstats).
//
// Run:  node --test tests/disk-stats-parser.test.mjs
//
// Implementation: contents/ui/platforms/standalone/DiskStatsParser.js.
// Standalone-only (only that backend reads /proc), so it lives beside
// the adapter, not in core/.

import { createRequire } from "node:module";
import { test } from "node:test";
import assert from "node:assert/strict";

const require = createRequire(import.meta.url);
const Parser = require("../contents/ui/platforms/standalone/DiskStatsParser.js");

// A trimmed real-shape /proc/diskstats: nvme0n1 whole disk + two
// partitions, sda whole disk + one partition, plus virtual devices.
const SAMPLE = [
    " 259       0 nvme0n1 1000 0 8000 100 2000 0 16000 200 0 0 0",
    " 259       1 nvme0n1p1 10 0 80 1 20 0 160 2 0 0 0",
    " 259       2 nvme0n1p2 30 0 240 3 40 0 320 4 0 0 0",
    "   8       0 sda 500 0 4000 50 100 0 800 10 0 0 0",
    "   8       1 sda1 5 0 40 1 10 0 80 1 0 0 0",
    "   7       0 loop0 0 0 0 0 0 0 0 0 0 0 0",
    " 253       0 dm-0 9 0 72 1 9 0 72 1 0 0 0",
    " 252       0 zram0 0 0 0 0 0 0 0 0 0 0 0",
    ""
].join("\n");

// ── parseDiskStats ──────────────────────────────────────────────────

test("parseDiskStats returns empty on null / empty input", () => {
    assert.deepEqual(Parser.parseDiskStats(null), {});
    assert.deepEqual(Parser.parseDiskStats(""), {});
});

test("parseDiskStats reads the two sector counters per device", () => {
    const map = Parser.parseDiskStats(SAMPLE);
    assert.deepEqual(map["nvme0n1"], { readSectors: 8000, writeSectors: 16000 });
    assert.deepEqual(map["sda1"], { readSectors: 40, writeSectors: 80 });
});

test("parseDiskStats skips lines without the sector fields", () => {
    const map = Parser.parseDiskStats(" 259 0 nvme0n1 1000 0\n");
    assert.equal(map["nvme0n1"], undefined);
});

// ── aggregateWholeDisks ─────────────────────────────────────────────

test("aggregateWholeDisks sums whole disks only (drops partitions)", () => {
    const map = Parser.parseDiskStats(SAMPLE);
    const agg = Parser.aggregateWholeDisks(map);
    // nvme0n1 (8000/16000) + sda (4000/800) — NOT the p1/p2/sda1 partitions.
    assert.deepEqual(agg, { readSectors: 12000, writeSectors: 16800 });
});

test("aggregateWholeDisks drops virtual devices (loop/dm-/zram)", () => {
    // dm-0 carries 72/72; loop0/zram0 are zero. If any virtual device
    // leaked in, the read total would exceed 12000.
    const map = Parser.parseDiskStats(SAMPLE);
    const agg = Parser.aggregateWholeDisks(map);
    assert.equal(agg.readSectors, 12000);
});

test("aggregateWholeDisks keeps nvme/mmcblk whole disks (trailing digit not a partition)", () => {
    const map = Parser.parseDiskStats([
        " 259 0 nvme0n1 100 0 100 0 0 0 200 0 0 0 0",
        " 179 0 mmcblk0 50 0 50 0 0 0 60 0 0 0 0",
        " 179 1 mmcblk0p1 5 0 5 0 0 0 6 0 0 0 0",
        ""
    ].join("\n"));
    const agg = Parser.aggregateWholeDisks(map);
    // nvme0n1 (100/200) + mmcblk0 (50/60); mmcblk0p1 excluded.
    assert.deepEqual(agg, { readSectors: 150, writeSectors: 260 });
});

test("aggregateWholeDisks excludes eMMC hardware areas (boot0/boot1/rpmb)", () => {
    // mmcblk0boot0/boot1/rpmb sit beside the data device and survive the
    // trailing-digit rule (mmcblk0boot0 → mmcblk0boot, absent), so without
    // the area rule they would double-count into the aggregate.
    const map = Parser.parseDiskStats([
        " 179 0 mmcblk0 1000 0 1000 0 0 0 2000 0 0 0 0",
        " 179 8 mmcblk0boot0 5 0 5 0 0 0 6 0 0 0 0",
        " 179 16 mmcblk0boot1 5 0 5 0 0 0 6 0 0 0 0",
        " 179 24 mmcblk0rpmb 1 0 1 0 0 0 2 0 0 0 0",
        " 179 1 mmcblk0p1 9 0 9 0 0 0 9 0 0 0 0",
        ""
    ].join("\n"));
    const agg = Parser.aggregateWholeDisks(map);
    assert.deepEqual(agg, { readSectors: 1000, writeSectors: 2000 });
});

test("aggregateWholeDisks drops the numbered virtual families (md/sr/fd/ram)", () => {
    const map = Parser.parseDiskStats([
        " 8 0 sda 100 0 100 0 0 0 200 0 0 0 0",
        " 9 0 md0 50 0 50 0 0 0 60 0 0 0 0",
        " 11 0 sr0 1 0 1 0 0 0 0 0 0 0 0",
        " 2 0 fd0 1 0 1 0 0 0 0 0 0 0 0",
        " 1 0 ram0 1 0 1 0 0 0 0 0 0 0 0",
        ""
    ].join("\n"));
    const agg = Parser.aggregateWholeDisks(map);
    assert.deepEqual(agg, { readSectors: 100, writeSectors: 200 });
});

test("aggregateWholeDisks is empty-safe", () => {
    assert.deepEqual(Parser.aggregateWholeDisks(null), { readSectors: 0, writeSectors: 0 });
    assert.deepEqual(Parser.aggregateWholeDisks({}), { readSectors: 0, writeSectors: 0 });
});

// ── ratesFromSamples ────────────────────────────────────────────────

test("ratesFromSamples computes bytes/s from the sector delta × 512", () => {
    const prev = { readSectors: 1000, writeSectors: 2000 };
    const cur = { readSectors: 3000, writeSectors: 2000 };
    // 2000 sectors × 512 B over 2 s = 512000 B/s read; write unchanged.
    const r = Parser.ratesFromSamples(prev, cur, 2);
    assert.equal(r.readBps, 2000 * 512 / 2);
    assert.equal(r.writeBps, 0);
});

test("ratesFromSamples clamps a negative delta (counter reset) to 0", () => {
    const prev = { readSectors: 5000, writeSectors: 5000 };
    const cur = { readSectors: 10, writeSectors: 5000 };
    const r = Parser.ratesFromSamples(prev, cur, 1);
    assert.equal(r.readBps, 0);
    assert.equal(r.writeBps, 0);
});

test("ratesFromSamples returns 0 for a non-positive interval or missing sample", () => {
    const s = { readSectors: 1, writeSectors: 1 };
    assert.deepEqual(Parser.ratesFromSamples(s, s, 0), { readBps: 0, writeBps: 0 });
    assert.deepEqual(Parser.ratesFromSamples(null, s, 1), { readBps: 0, writeBps: 0 });
});
