// SCENARIO regression tests for the disk-partition picker + ring set on
// plug / unplug, composed end-to-end on the pure DiskMetrics helpers. These
// encode the manual test scenarios run on 2026-05-29 (Plasma USB plug/unplug)
// so the behaviour — especially "does the greyed stale row appear?" — is a
// deterministic assert instead of a fiddly live test.
//
// The picker on Plasma derives three things from one mount-gated discovered
// list (MetricsBackend.mountedAvailablePartitions = filterToMounted(
// availablePartitions, mountedPartitionIds)):
//   - selectable rows   = orderPartitions(orderCsv, mountedAvailable)
//   - greyed stale rows  = stalePartitions(enabledCsv, orderCsv, mountedAvailable, cache)
//   - rendered rings     = resolveDiskRingIds(manual, removable, [], defaults, max, mountedIds)
// The KEY to the bug class (#58): availablePartitions FREEZES on unmount
// (ksysguard keeps listing the gone UUID), so these tests feed a FROZEN
// `available` that still contains the unplugged disk, and assert the live
// `mountedIds` gate is what makes it drop / go stale / self-heal.

import { createRequire } from "node:module";
import { test } from "node:test";
import assert from "node:assert/strict";

const require = createRequire(import.meta.url);
const Disk = require("../contents/ui/core/DiskMetrics.js");

// Three fixed disks (always mounted) + one removable USB key.
const SAMSUNG = { id: "s-uuid", label: "SAMSUNG" };
const SYNC = { id: "y-uuid", label: "sync" };
const PHOTOS = { id: "p-uuid", label: "photos" };
const USB = { id: "u-uuid", label: "MYUSB" };

const FIXED = [SAMSUNG, SYNC, PHOTOS];
const FIXED_IDS = FIXED.map(p => p.id);

const DISK_MAX = 5; // Geom.DISK_MAX_RING_COUNT

// Reproduce the picker/ring derivation a Plasma config dialog performs.
// `available` is the (possibly frozen) ksysguard discovered set; `mountedIds`
// is the live findmnt set; `enabledCsv`/`orderCsv` are the persisted manual
// selection; `removableMounts` is MountInfo's mounted-removable list.
function pickerState({ available, mountedIds, enabledCsv = "", orderCsv = "", removableMounts = [], cache = "" }) {
    const mountedAvailable = Disk.filterToMounted(available, mountedIds);
    const selectable = Disk.orderPartitions(orderCsv, mountedAvailable).map(p => p.id);
    const stale = Disk.stalePartitions(enabledCsv, orderCsv, mountedAvailable, cache);
    // manual ids = enabled, in order (what MetricsCatalog.filterByOrder yields).
    const enabledIds = enabledCsv ? enabledCsv.split(",").filter(Boolean) : [];
    const rings = Disk.resolveDiskRingIds(enabledIds, removableMounts, [], [], DISK_MAX, mountedIds);
    return { selectable, stale, rings };
}

// ── SCENARIO 1 — picker gating on plug / unplug (#65) ────────────────

test("SCENARIO 1a: plug a USB → it is selectable in the picker, no stale row, no auto-check", () => {
    const s = pickerState({
        available: [...FIXED, USB],
        mountedIds: [...FIXED_IDS, USB.id],
        enabledCsv: "", // nothing manually checked
        removableMounts: [USB],
    });
    assert.ok(s.selectable.includes(USB.id), "USB must be a selectable picker row while mounted");
    assert.deepEqual(s.stale, [], "no stale rows while everything is mounted");
    assert.ok(s.rings.includes(USB.id), "auto-show: the USB ring renders via removableMounts even though unchecked");
});

test("SCENARIO 1b: unplug an UNCHECKED (auto-shown) USB → it disappears entirely, no stale row", () => {
    // ksysguard's tree is FROZEN and still lists the USB; the live mount set
    // no longer does. This is what the user saw: the line just vanishes.
    const s = pickerState({
        available: [...FIXED, USB], // frozen — still lists the gone USB
        mountedIds: FIXED_IDS, // findmnt: USB gone
        enabledCsv: "", // was never checked
        removableMounts: [], // unmounted → not in MountInfo.mounted
    });
    assert.ok(!s.selectable.includes(USB.id), "unmounted USB must drop from the selectable list (#65)");
    assert.deepEqual(s.stale, [], "an auto-shown (never-checked) USB leaves nothing to clean up → no greyed row");
    assert.ok(!s.rings.includes(USB.id), "ring self-heals away (#58)");
});

test("SCENARIO 1c: unplug a CHECKED USB → it becomes a greyed stale row (NOT a live checkbox, NOT gone)", () => {
    // THE case the live test did not cover. The USB was manually checked, so
    // its UUID is in enabledPartitions; on unplug it must surface as the
    // greyed "no longer connected" row with its last-known label.
    const s = pickerState({
        available: [...FIXED, USB], // frozen — still lists the USB
        mountedIds: FIXED_IDS, // findmnt: USB gone
        enabledCsv: [...FIXED_IDS, USB.id].join(","), // USB was checked
        orderCsv: [...FIXED_IDS, USB.id].join(","),
        removableMounts: [],
        cache: JSON.stringify({ [USB.id]: "MYUSB" }), // last-known label cached
    });
    assert.ok(!s.selectable.includes(USB.id), "the unmounted USB must NOT be a live selectable row");
    assert.deepEqual(
        s.stale,
        [{ id: USB.id, label: "MYUSB" }],
        "a CHECKED-then-unplugged USB must surface as a greyed stale row with its cached label",
    );
});

test("SCENARIO 1c-bis: BEFORE the fix, the frozen tree kept the checked USB live (regression guard)", () => {
    // Demonstrates why the mount gate is load-bearing: feeding the RAW frozen
    // `available` (no filterToMounted) to stalePartitions reports the USB as
    // still-discovered → NOT stale → it would linger as a live checked row.
    const frozenDiscovered = [...FIXED, USB];
    const staleWithoutGate = Disk.stalePartitions(
        [...FIXED_IDS, USB.id].join(","), [...FIXED_IDS, USB.id].join(","), frozenDiscovered, "",
    );
    assert.deepEqual(staleWithoutGate, [], "without the mount gate the frozen tree hides the unplug — this is the bug #65 fixes");
});

// ── SCENARIO 2 — auto-show ring + self-heal (#60 / #58) ──────────────

test("SCENARIO 2: auto-show on plug, self-heal on unplug (no manual selection)", () => {
    const plugged = pickerState({
        available: [...FIXED, USB], mountedIds: [...FIXED_IDS, USB.id],
        enabledCsv: "", removableMounts: [USB],
    });
    assert.ok(plugged.rings.includes(USB.id), "plugged: USB ring auto-shows");

    const unplugged = pickerState({
        available: [...FIXED, USB], mountedIds: FIXED_IDS, // frozen tree, live findmnt
        enabledCsv: "", removableMounts: [],
    });
    assert.ok(!unplugged.rings.includes(USB.id), "unplugged: USB ring self-heals away");
});

// ── SCENARIO 3 — a checked removable ring self-heals too (#58) ───────

test("SCENARIO 3: a CHECKED partition's ring self-heals on unmount via the mountedIds gate", () => {
    // resolveDiskRingIds gates the MANUAL ids on mountedIds, so even a
    // hand-checked partition loses its ring when unmounted (the picker shows
    // it as stale per 1c, but the ring must not linger frozen).
    const rings = Disk.resolveDiskRingIds(
        [...FIXED_IDS, USB.id], [], [], [], DISK_MAX, FIXED_IDS, // USB checked but not in live mounts
    );
    assert.ok(!rings.includes(USB.id), "checked-but-unmounted partition is dropped from the rendered rings");
    assert.deepEqual(rings, FIXED_IDS, "the still-mounted fixed disks keep their rings");
});

// ── SCENARIO 4 — warm-up window must not blank the picker ────────────

test("SCENARIO 4: before the first findmnt poll (empty mountedIds), the picker shows everything (no false blanking)", () => {
    // Empty mountedIds = "no live data yet" → passthrough, so opening the
    // dialog doesn't momentarily empty the picker while findmnt spins up.
    const s = pickerState({
        available: [...FIXED, USB], mountedIds: [], // poll not returned yet
        enabledCsv: "", removableMounts: [],
    });
    assert.deepEqual(
        s.selectable.sort(),
        [...FIXED_IDS, USB.id].sort(),
        "during warm-up every discovered partition stays selectable (passthrough)",
    );
});
