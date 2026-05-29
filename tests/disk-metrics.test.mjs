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

// NOTE: selecting the enabled subset in display order is done with
// MetricsCatalog.filterByOrder(enabledCsvIds, orderedIds) — covered in
// tests/metrics-catalog.test.mjs. The old DiskMetrics.selectPartitions was
// a duplicate of filterByOrder (args swapped) and has been removed.

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

test("orderPartitions: stale saved ids (unplugged) are excluded from the draggable list", () => {
    // The draggable list shows only discovered partitions; stale ids are
    // surfaced separately via stalePartitions() (see below), not here.
    const out = Disk.orderPartitions("u-gone,u-photos", AVAIL);
    assert.deepEqual(out.map((p) => p.id), ["u-photos", "u-bazzite", "u-sync"]);
});

test("orderPartitions: tolerates empty available", () => {
    assert.deepEqual(Disk.orderPartitions("u-a,u-b", []), []);
    assert.deepEqual(Disk.orderPartitions("", null), []);
});

// ── stalePartitions ──────────────────────────────────────────────────

test("stalePartitions: none when every configured id is discovered", () => {
    assert.deepEqual(Disk.stalePartitions("u-bazzite,u-photos", "u-photos,u-bazzite", AVAIL, ""), []);
});

test("stalePartitions: an unplugged enabled id surfaces as stale", () => {
    // SCENARIO (#49): user selected a USB drive (u-usb), then unplugged it.
    // Its UUID lingers in enabledPartitions but is no longer discovered.
    const out = Disk.stalePartitions("u-photos,u-usb", "", AVAIL, "");
    assert.deepEqual(out.map((p) => p.id), ["u-usb"]);
});

test("stalePartitions: stale id present only in the order CSV still surfaces", () => {
    const out = Disk.stalePartitions("", "u-gone,u-photos", AVAIL, "");
    assert.deepEqual(out.map((p) => p.id), ["u-gone"]);
});

test("stalePartitions: order CSV listed first, then enabled-only, deduped", () => {
    const out = Disk.stalePartitions("u-enabled-only", "u-ordered", AVAIL, "");
    assert.deepEqual(out.map((p) => p.id), ["u-ordered", "u-enabled-only"]);
    // u-ordered appearing in both must not duplicate.
    const dedup = Disk.stalePartitions("u-ordered,u-x", "u-ordered", AVAIL, "");
    assert.deepEqual(dedup.map((p) => p.id), ["u-ordered", "u-x"]);
});

test("stalePartitions: label comes from the cache, falls back to the UUID", () => {
    const cache = JSON.stringify({ "u-usb": "backups" });
    const out = Disk.stalePartitions("u-usb,u-nocache", "", AVAIL, cache);
    assert.deepEqual(out, [
        { id: "u-usb", label: "backups" },
        { id: "u-nocache", label: "u-nocache" },
    ]);
});

test("stalePartitions: tolerates empty inputs", () => {
    assert.deepEqual(Disk.stalePartitions("", "", AVAIL, ""), []);
    assert.deepEqual(Disk.stalePartitions("u-a", "", null, null), [{ id: "u-a", label: "u-a" }]);
});

// ── filterToMounted ──────────────────────────────────────────────────

const PARTS = [
    { id: "u-a", label: "alpha" },
    { id: "u-b", label: "beta" },
    { id: "u-c", label: "gamma" },
];

test("filterToMounted: keeps only partitions whose id is mounted", () => {
    assert.deepEqual(
        Disk.filterToMounted(PARTS, ["u-a", "u-c"]),
        [{ id: "u-a", label: "alpha" }, { id: "u-c", label: "gamma" }],
    );
});

test("filterToMounted: SCENARIO #58 — a frozen-but-unmounted partition drops out", () => {
    // ksysguard still lists u-b after its disk unmounted (its SensorTreeModel
    // freezes), but findmnt no longer reports it → the picker must not offer
    // it as a live selectable row.
    assert.deepEqual(
        Disk.filterToMounted(PARTS, ["u-a", "u-c"]).map(p => p.id),
        ["u-a", "u-c"],
    );
});

test("filterToMounted: empty/absent mountedIds → passthrough (warm-up window)", () => {
    // Before the findmnt poll returns there is no live data; gating then would
    // wrongly empty the whole picker. Passthrough until the set is known.
    assert.deepEqual(Disk.filterToMounted(PARTS, []), PARTS);
    assert.deepEqual(Disk.filterToMounted(PARTS, null), PARTS);
    assert.deepEqual(Disk.filterToMounted(PARTS, undefined), PARTS);
});

test("filterToMounted: returns a new array, does not mutate input", () => {
    const out = Disk.filterToMounted(PARTS, []);
    assert.notEqual(out, PARTS);
    assert.deepEqual(out, PARTS);
});

test("filterToMounted: tolerates empty/null partitions", () => {
    assert.deepEqual(Disk.filterToMounted([], ["u-a"]), []);
    assert.deepEqual(Disk.filterToMounted(null, ["u-a"]), []);
    assert.deepEqual(Disk.filterToMounted(undefined, null), []);
});

test("filterToMounted: none of the discovered are mounted → empty", () => {
    assert.deepEqual(Disk.filterToMounted(PARTS, ["u-x", "u-y"]), []);
});

// ── label cache (parse / serialize / merge) ──────────────────────────

test("parseLabelCache: empty / malformed JSON → {}", () => {
    assert.deepEqual(Disk.parseLabelCache(""), {});
    assert.deepEqual(Disk.parseLabelCache(null), {});
    assert.deepEqual(Disk.parseLabelCache("not json"), {});
    assert.deepEqual(Disk.parseLabelCache("[1,2]"), {}); // array is not a map
    assert.deepEqual(Disk.parseLabelCache('{"u-a":"x"}'), { "u-a": "x" });
});

test("serializeLabelCache: sorted keys → stable output regardless of insertion order", () => {
    const a = Disk.serializeLabelCache({ z: "1", a: "2", m: "3" });
    const b = Disk.serializeLabelCache({ a: "2", m: "3", z: "1" });
    assert.equal(a, b);
    assert.equal(a, '{"a":"2","m":"3","z":"1"}');
});

test("mergeLabelCache: fresh discovered labels win, bounded to referenced ids", () => {
    const out = Disk.mergeLabelCache("{}", AVAIL, ["u-bazzite", "u-photos"]);
    assert.deepEqual(JSON.parse(out), { "u-bazzite": "bazzite", "u-photos": "photos" });
    // u-sync discovered but not referenced → not cached.
    assert.equal(JSON.parse(out)["u-sync"], undefined);
});

test("mergeLabelCache: preserves last-known label for a referenced-but-undiscovered id", () => {
    // SCENARIO (#49): u-usb was cached while plugged; now unplugged (not in
    // AVAIL) but still referenced → keep its friendly name for the stale row.
    const prev = JSON.stringify({ "u-usb": "backups" });
    const out = Disk.mergeLabelCache(prev, AVAIL, ["u-usb", "u-bazzite"]);
    assert.deepEqual(JSON.parse(out), { "u-usb": "backups", "u-bazzite": "bazzite" });
});

test("mergeLabelCache: drops entries for ids no longer referenced", () => {
    const prev = JSON.stringify({ "u-old": "gone", "u-bazzite": "stale-name" });
    const out = Disk.mergeLabelCache(prev, AVAIL, ["u-bazzite"]);
    // u-old dropped (unreferenced); u-bazzite refreshed from discovery.
    assert.deepEqual(JSON.parse(out), { "u-bazzite": "bazzite" });
});

test("mergeLabelCache: stable output → unchanged cache round-trips identically", () => {
    const first = Disk.mergeLabelCache("{}", AVAIL, ["u-photos", "u-bazzite"]);
    const second = Disk.mergeLabelCache(first, AVAIL, ["u-bazzite", "u-photos"]);
    assert.equal(first, second);
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

// ── isRemovableMount ────────────────────────────────────────────────

test("isRemovableMount: /run/media/<user>/… → removable", () => {
    assert.equal(Disk.isRemovableMount("/run/media/manu/BIOS"), true);
    assert.equal(Disk.isRemovableMount("/run/media/manu/My Backup"), true);
});

test("isRemovableMount: legacy /media/<user>/… → removable", () => {
    assert.equal(Disk.isRemovableMount("/media/manu/usbkey"), true);
});

test("isRemovableMount: fixed-disk mountpoints → not removable", () => {
    assert.equal(Disk.isRemovableMount("/"), false);
    assert.equal(Disk.isRemovableMount("/boot"), false);
    assert.equal(Disk.isRemovableMount("/var/home"), false);
    assert.equal(Disk.isRemovableMount("/var/mnt/photos"), false);
});

test("isRemovableMount: a path merely containing /media is not a prefix match", () => {
    assert.equal(Disk.isRemovableMount("/var/media/library"), false);
    assert.equal(Disk.isRemovableMount("/home/manu/run/media/x"), false);
});

test("isRemovableMount: empty / non-string → false", () => {
    assert.equal(Disk.isRemovableMount(""), false);
    assert.equal(Disk.isRemovableMount(null), false);
    assert.equal(Disk.isRemovableMount(undefined), false);
    assert.equal(Disk.isRemovableMount(42), false);
});

// ── resolveDiskRingIds ──────────────────────────────────────────────
// The final disk-ring set: manual selection ∪ mounted removable (− opt-out),
// default fallback when empty, capped at maxCount. removableMounts is [{id,…}].

const MAX = 6;

test("resolveDiskRingIds: manual selection only → unchanged, order preserved", () => {
    const out = Disk.resolveDiskRingIds(["a", "b"], [], [], [], MAX);
    assert.deepEqual(out, ["a", "b"]);
});

test("resolveDiskRingIds: a mounted removable auto-shows even with no manual selection", () => {
    const out = Disk.resolveDiskRingIds([], [{ id: "usb-1", label: "BIOS" }], [], [], MAX);
    assert.deepEqual(out, ["usb-1"]);
});

test("resolveDiskRingIds: manual first, then removable appended", () => {
    const out = Disk.resolveDiskRingIds(["home", "data"], [{ id: "usb-1" }], [], [], MAX);
    assert.deepEqual(out, ["home", "data", "usb-1"]);
});

test("resolveDiskRingIds: a manually-selected removable is not double-counted", () => {
    // The user explicitly checked the USB AND it is mounted-removable — it must
    // appear once (in its manual position), not twice.
    const out = Disk.resolveDiskRingIds(["usb-1", "home"], [{ id: "usb-1" }], [], [], MAX);
    assert.deepEqual(out, ["usb-1", "home"]);
});

test("resolveDiskRingIds: an opted-out removable is suppressed from the auto-show", () => {
    const out = Disk.resolveDiskRingIds([], [{ id: "usb-1" }, { id: "usb-2" }], ["usb-1"], [], MAX);
    assert.deepEqual(out, ["usb-2"]);
});

test("resolveDiskRingIds: opt-out does not hide a manually-selected partition", () => {
    // Manual selection wins — opt-out only governs the auto-show of removables.
    const out = Disk.resolveDiskRingIds(["usb-1"], [{ id: "usb-1" }], ["usb-1"], [], MAX);
    assert.deepEqual(out, ["usb-1"]);
});

test("resolveDiskRingIds: empty union falls back to defaultIds", () => {
    const out = Disk.resolveDiskRingIds([], [], [], ["home-fs"], MAX);
    assert.deepEqual(out, ["home-fs"]);
});

test("resolveDiskRingIds: default fallback is deduped (contract holds on the empty-union path)", () => {
    const out = Disk.resolveDiskRingIds([], [], [], ["d", "d", "e"], MAX);
    assert.deepEqual(out, ["d", "e"]);
});

test("resolveDiskRingIds: a present member skips the default fallback", () => {
    const out = Disk.resolveDiskRingIds([], [{ id: "usb-1" }], [], ["home-fs"], MAX);
    assert.deepEqual(out, ["usb-1"]);
});

test("resolveDiskRingIds: capped at maxCount (manual + removable overflow)", () => {
    const removable = [{ id: "r1" }, { id: "r2" }, { id: "r3" }, { id: "r4" }, { id: "r5" }];
    const out = Disk.resolveDiskRingIds(["m1", "m2"], removable, [], [], 6);
    assert.deepEqual(out, ["m1", "m2", "r1", "r2", "r3", "r4"]);
    assert.equal(out.length, 6);
});

test("resolveDiskRingIds: dedups repeated ids within the manual list", () => {
    const out = Disk.resolveDiskRingIds(["a", "a", "b"], [], [], [], MAX);
    assert.deepEqual(out, ["a", "b"]);
});

test("resolveDiskRingIds: tolerates null/undefined inputs", () => {
    assert.deepEqual(Disk.resolveDiskRingIds(null, null, null, null, MAX), []);
    assert.deepEqual(Disk.resolveDiskRingIds(undefined, undefined, undefined, undefined, undefined), []);
});

test("resolveDiskRingIds: drops falsy / id-less removable entries", () => {
    const out = Disk.resolveDiskRingIds([], [{ id: "" }, null, { label: "x" }, { id: "ok" }], [], [], MAX);
    assert.deepEqual(out, ["ok"]);
});

test("resolveDiskRingIds: omitted maxCount returns the full union (no cap)", () => {
    const removable = [{ id: "r1" }, { id: "r2" }, { id: "r3" }, { id: "r4" }, { id: "r5" }, { id: "r6" }, { id: "r7" }];
    const out = Disk.resolveDiskRingIds([], removable, [], []);
    assert.equal(out.length, 7);
});

// ── mountedIds gate (the #58 self-heal) ─────────────────────────────
// A manual id absent from the live mounted set is dropped; fixed disks
// (always mounted) survive. Empty/undefined mountedIds means "no data" → no gate.

test("resolveDiskRingIds: a manual id NOT in the live mounted set is dropped (self-heal)", () => {
    // SCENARIO #58: a manually-checked USB key is unplugged. ksysguard's tree
    // still lists its frozen UUID, but the live mount table (mountedIds) does
    // not — the ring must disappear.
    const out = Disk.resolveDiskRingIds(["samsung", "photos", "usb-bios"], [], [], [], MAX,
        ["samsung", "photos", "bazzite"]);
    assert.deepEqual(out, ["samsung", "photos"]);
});

test("resolveDiskRingIds: manual ids present in the mounted set are all kept", () => {
    const out = Disk.resolveDiskRingIds(["samsung", "sync", "photos"], [], [], [], MAX,
        ["samsung", "sync", "photos", "bazzite", "boot"]);
    assert.deepEqual(out, ["samsung", "sync", "photos"]);
});

test("resolveDiskRingIds: empty mountedIds does NOT gate (startup poll window)", () => {
    // Before the first mount poll returns mountedIds is [] — a real system
    // always has a root mount, so empty means 'no data', not 'nothing mounted'.
    // Gating then would wrongly blank every fixed-disk ring for a frame.
    const out = Disk.resolveDiskRingIds(["a", "b"], [], [], [], MAX, []);
    assert.deepEqual(out, ["a", "b"]);
});

test("resolveDiskRingIds: undefined mountedIds does NOT gate (standalone, no mount tracking)", () => {
    const out = Disk.resolveDiskRingIds(["a", "b"], [], [], [], MAX, undefined);
    assert.deepEqual(out, ["a", "b"]);
});

test("resolveDiskRingIds: mounted gate drops a manual id but keeps the auto-shown removable", () => {
    // The unplugged manual key 'old-usb' is gone from mountedIds; a freshly
    // mounted removable 'new-usb' is in both removableMounts and mountedIds.
    const out = Disk.resolveDiskRingIds(["home", "old-usb"], [{ id: "new-usb" }], [], [], MAX,
        ["home", "new-usb"]);
    assert.deepEqual(out, ["home", "new-usb"]);
});
