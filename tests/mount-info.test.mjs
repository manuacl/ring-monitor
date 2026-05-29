// Tests for MountInfo.js — Plasma-side `lsblk -P` pairs parsing.
//
// Run:  node --test tests/mount-info.test.mjs
//
// Implementation: contents/ui/platforms/plasma/MountInfo.js.
// Dual-loaded by QML and Node via the module.exports shim at the bottom.

import { createRequire } from "node:module";
import { test } from "node:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import assert from "node:assert/strict";

const require = createRequire(import.meta.url);
const MountInfo = require("../contents/ui/platforms/plasma/MountInfo.js");

const __dirname = dirname(fileURLToPath(import.meta.url));
const QML = readFileSync(
    join(__dirname, "..", "contents", "ui", "platforms", "plasma", "MountInfo.qml"),
    "utf8");

// Real `lsblk -P -o UUID,MOUNTPOINT,LABEL` shape on the dev box, with a USB
// key (BIOS) plugged. Includes: a partition with no UUID (the swap/zram-ish
// line), an unmounted partition (empty MOUNTPOINT), and the btrfs root that
// lsblk reports once even though it's mounted at many paths.
const SAMPLE =
    'UUID="ADD0-32B6" MOUNTPOINT="/boot/efi" LABEL=""\n' +
    'UUID="dc3453e6-4610-4b89-b66c-82c29195ab01" MOUNTPOINT="/boot" LABEL="bazzite_xboot"\n' +
    'UUID="6286e04e-b217-43bf-834f-d6a054ac4376" MOUNTPOINT="/var/home" LABEL="bazzite"\n' +
    'UUID="81af2d89-3967-403a-8f96-643b32f1620f" MOUNTPOINT="/var/mnt/photos" LABEL="photos"\n' +
    'UUID="6f45-2b2f" MOUNTPOINT="/run/media/manu/BIOS" LABEL="BIOS"\n';

test("parseLsblkPairs: parses each mounted filesystem", () => {
    const rows = MountInfo.parseLsblkPairs(SAMPLE);
    assert.equal(rows.length, 5);
    const usb = rows.find((r) => r.uuid === "6f45-2b2f");
    assert.deepEqual(usb, {
        uuid: "6f45-2b2f",
        label: "BIOS",
        mountpoint: "/run/media/manu/BIOS",
    });
});

test("parseLsblkPairs: empty label falls back to the UUID (lower-cased)", () => {
    const rows = MountInfo.parseLsblkPairs(SAMPLE);
    // The EFI row's serial is uppercase in lsblk ("ADD0-32B6") → lower-cased,
    // and with an empty LABEL the fallback uses that same lowercase uuid.
    const efi = rows.find((r) => r.uuid === "add0-32b6");
    assert.equal(efi.label, "add0-32b6");
});

test("parseLsblkPairs: drops rows with no UUID", () => {
    const out = MountInfo.parseLsblkPairs(
        'UUID="" MOUNTPOINT="/boot/efi" LABEL="esp"\n' +
        'UUID="good-1" MOUNTPOINT="/data" LABEL="data"\n');
    assert.deepEqual(out.map((r) => r.uuid), ["good-1"]);
});

test("parseLsblkPairs: drops rows with no mountpoint (unmounted)", () => {
    const out = MountInfo.parseLsblkPairs(
        'UUID="unmounted-1" MOUNTPOINT="" LABEL="spare"\n' +
        'UUID="mounted-1" MOUNTPOINT="/data" LABEL="data"\n');
    assert.deepEqual(out.map((r) => r.uuid), ["mounted-1"]);
});

test("parseLsblkPairs: drops swap (mountpoint is [SWAP], not a path)", () => {
    const out = MountInfo.parseLsblkPairs(
        'UUID="zram-1" MOUNTPOINT="[SWAP]" LABEL="zram0"\n' +
        'UUID="mounted-1" MOUNTPOINT="/data" LABEL="data"\n');
    assert.deepEqual(out.map((r) => r.uuid), ["mounted-1"]);
});

test("parseLsblkPairs: lower-cases the UUID to match ksysguard (vfat serials are UPPERCASE)", () => {
    // SCENARIO: a vfat USB key. lsblk prints its volume serial uppercase
    // ("6F45-2B2F"), but ksysguard keys disk/<uuid> sensors — and the persisted
    // enabledPartitions — lowercase. Without normalization the ring renders at
    // 0% (no matching sensor) and the live-mount gate wrongly drops it.
    const out = MountInfo.parseLsblkPairs(
        'UUID="6F45-2B2F" MOUNTPOINT="/run/media/manu/BIOS" LABEL="BIOS"\n');
    assert.equal(out[0].uuid, "6f45-2b2f");
});

test("parseLsblkPairs: dedups case-insensitively after lower-casing", () => {
    const out = MountInfo.parseLsblkPairs(
        'UUID="AB12-CD34" MOUNTPOINT="/run/media/manu/a" LABEL="a"\n' +
        'UUID="ab12-cd34" MOUNTPOINT="/run/media/manu/b" LABEL="b"\n');
    assert.deepEqual(out.map((r) => r.uuid), ["ab12-cd34"]);
});

test("parseLsblkPairs: preserves spaces inside quoted label and mountpoint", () => {
    const out = MountInfo.parseLsblkPairs(
        'UUID="x1" MOUNTPOINT="/run/media/manu/My Backup" LABEL="My Backup"\n');
    assert.equal(out[0].mountpoint, "/run/media/manu/My Backup");
    assert.equal(out[0].label, "My Backup");
});

test("parseLsblkPairs: dedups repeated UUID, keeping the first row", () => {
    const out = MountInfo.parseLsblkPairs(
        'UUID="dup" MOUNTPOINT="/first" LABEL="a"\n' +
        'UUID="dup" MOUNTPOINT="/second" LABEL="b"\n');
    assert.equal(out.length, 1);
    assert.equal(out[0].mountpoint, "/first");
});

test("parseLsblkPairs: tolerates column order and extra whitespace", () => {
    const out = MountInfo.parseLsblkPairs(
        'LABEL="data"   MOUNTPOINT="/data"   UUID="u1"\n');
    assert.deepEqual(out, [{ uuid: "u1", label: "data", mountpoint: "/data" }]);
});

test("parseLsblkPairs: empty / non-string input → []", () => {
    assert.deepEqual(MountInfo.parseLsblkPairs(""), []);
    assert.deepEqual(MountInfo.parseLsblkPairs(null), []);
    assert.deepEqual(MountInfo.parseLsblkPairs(undefined), []);
});

// ── MountInfo.qml adapter — text-level guard ────────────────────────
// plasma5support import keeps this out of qmltestrunner (CI has no
// org.kde.plasma.plasma5support), same as the other Plasma adapters.

test("MountInfo.qml exposes the `mounted` surface", () => {
    assert.match(QML, /property\s+var\s+mounted\s*:/,
        "must expose a `mounted` property ([{uuid,label,mountpoint,removable}])");
});

test("MountInfo.qml reads mounts via plasma5support executable engine", () => {
    assert.match(QML, /import\s+org\.kde\.plasma\.plasma5support/,
        "must import plasma5support");
    assert.match(QML, /engine:\s*"executable"/, "DataSource engine must be executable");
});

test("MountInfo.qml runs lsblk -P by bare name (portable — engine has session PATH)", () => {
    assert.match(QML, /"lsblk -P /,
        "must invoke bare lsblk with -P pairs output (no hardcoded /usr/bin path)");
    assert.doesNotMatch(QML, /\/usr\/bin\/lsblk/,
        "must NOT hardcode an absolute lsblk path (portability)");
});

test("MountInfo.qml classifies through the shared helpers, not its own copy", () => {
    assert.match(QML, /MountInfo\.parseLsblkPairs\s*\(/, "must parse via MountInfo.js");
    assert.match(QML, /DiskMetrics\.isRemovableMount\s*\(/,
        "must classify removable via the shared core predicate");
});

test("MountInfo.qml keeps last-good on a failed lsblk run (no flicker to empty)", () => {
    // A nonzero exit must not overwrite `mounted` — see review finding #2.
    assert.match(QML, /data\["exit code"\]\s*!==\s*0/,
        "must bail before updating when lsblk exits nonzero");
});

test("MountInfo.qml gates the poll Timer on `active` (no consumer ⇒ no subprocess)", () => {
    // #59 review finding #1: the lsblk poll must be suppressible so a
    // disk-disabled widget spawns nothing. The backend drives `active`.
    assert.match(QML, /property\s+bool\s+active\s*:/,
        "must expose a bool `active` gate");
    assert.match(QML, /running:\s*root\.active/,
        "the poll Timer's `running` must be bound to `active`, not hardcoded true");
});

test("MountInfo.qml clears the last-good set when deactivated (no ghost ring on re-enable)", () => {
    // Phase 2 review: a removable unplugged while the disk ring was disabled
    // must not briefly resurface on re-enable before the async re-scan returns.
    assert.match(QML, /onActiveChanged:/,
        "must react to `active` changes");
    assert.match(QML, /onActiveChanged:[\s\S]{0,80}root\._mounted\s*=\s*\[\]/,
        "deactivation must clear _mounted to []");
});
