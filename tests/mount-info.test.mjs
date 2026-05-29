// Tests for MountInfo.js — Plasma-side `findmnt -P` pairs parsing.
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

// Real `findmnt -P -o UUID,TARGET,LABEL` shape on the dev box, with a USB key
// (BIOS) plugged. findmnt lists the kernel mount table, so it includes: the
// composefs root and /proc (no UUID → dropped), the btrfs root reported at
// SEVERAL subvolume targets with one shared UUID (deduped to the first), an
// uppercase vfat serial (EFI), and the removable key under /run/media.
const SAMPLE =
    'UUID="" TARGET="/" LABEL=""\n' +
    'UUID="6286e04e-b217-43bf-834f-d6a054ac4376" TARGET="/etc" LABEL="bazzite"\n' +
    'UUID="6286e04e-b217-43bf-834f-d6a054ac4376" TARGET="/var/home" LABEL="bazzite"\n' +
    'UUID="dc3453e6-4610-4b89-b66c-82c29195ab01" TARGET="/boot" LABEL="bazzite_xboot"\n' +
    'UUID="ADD0-32B6" TARGET="/boot/efi" LABEL=""\n' +
    'UUID="81af2d89-3967-403a-8f96-643b32f1620f" TARGET="/var/mnt/photos" LABEL="photos"\n' +
    'UUID="6F45-2B2F" TARGET="/run/media/manu/BIOS" LABEL="BIOS"\n' +
    'UUID="" TARGET="/proc" LABEL=""\n';

test("parseMountPairs: parses each mounted filesystem (deduped, no-UUID dropped)", () => {
    const rows = MountInfo.parseMountPairs(SAMPLE);
    assert.equal(rows.length, 5); // bazzite, bazzite_xboot, efi, photos, BIOS
    const usb = rows.find((r) => r.uuid === "6f45-2b2f");
    assert.deepEqual(usb, {
        uuid: "6f45-2b2f",
        label: "BIOS",
        mountpoint: "/run/media/manu/BIOS",
    });
});

test("parseMountPairs: lower-cases the UUID to match ksysguard (vfat serials are UPPERCASE)", () => {
    // SCENARIO: a vfat USB key. findmnt prints its volume serial uppercase
    // ("6F45-2B2F"), but ksysguard keys disk/<uuid> sensors — and the persisted
    // enabledPartitions — lowercase. Without normalization the ring renders at
    // 0% (no matching sensor) and the live-mount gate wrongly drops it.
    const out = MountInfo.parseMountPairs(
        'UUID="6F45-2B2F" TARGET="/run/media/manu/BIOS" LABEL="BIOS"\n');
    assert.equal(out[0].uuid, "6f45-2b2f");
});

test("parseMountPairs: dedups case-insensitively after lower-casing", () => {
    const out = MountInfo.parseMountPairs(
        'UUID="AB12-CD34" TARGET="/run/media/manu/a" LABEL="a"\n' +
        'UUID="ab12-cd34" TARGET="/run/media/manu/b" LABEL="b"\n');
    assert.deepEqual(out.map((r) => r.uuid), ["ab12-cd34"]);
});

test("parseMountPairs: empty label falls back to the UUID (lower-cased)", () => {
    const rows = MountInfo.parseMountPairs(SAMPLE);
    // The EFI row's serial is uppercase in findmnt ("ADD0-32B6") → lower-cased,
    // and with an empty LABEL the fallback uses that same lowercase uuid.
    const efi = rows.find((r) => r.uuid === "add0-32b6");
    assert.equal(efi.label, "add0-32b6");
});

test("parseMountPairs: drops pseudo / network mounts (no UUID)", () => {
    const out = MountInfo.parseMountPairs(
        'UUID="" TARGET="/proc" LABEL=""\n' +
        'UUID="" TARGET="/var/lib/nfs/rpc_pipefs" LABEL=""\n' +
        'UUID="good-1" TARGET="/data" LABEL="data"\n');
    assert.deepEqual(out.map((r) => r.uuid), ["good-1"]);
});

test("parseMountPairs: dedups a filesystem mounted at several targets, keeping the first", () => {
    // A btrfs root reported at /etc then /var/home (subvolumes): one entry, and
    // its mountpoint is the FIRST target — used for removable classification.
    const rows = MountInfo.parseMountPairs(SAMPLE);
    const root = rows.filter((r) => r.uuid === "6286e04e-b217-43bf-834f-d6a054ac4376");
    assert.equal(root.length, 1);
    assert.equal(root[0].mountpoint, "/etc");
});

test("parseMountPairs: drops a row whose target isn't an absolute path (defensive)", () => {
    const out = MountInfo.parseMountPairs(
        'UUID="bad-1" TARGET="" LABEL="x"\n' +
        'UUID="good-1" TARGET="/data" LABEL="data"\n');
    assert.deepEqual(out.map((r) => r.uuid), ["good-1"]);
});

test("parseMountPairs: preserves spaces inside quoted label and target", () => {
    const out = MountInfo.parseMountPairs(
        'UUID="x1" TARGET="/run/media/manu/My Backup" LABEL="My Backup"\n');
    assert.equal(out[0].mountpoint, "/run/media/manu/My Backup");
    assert.equal(out[0].label, "My Backup");
});

test("parseMountPairs: tolerates column order and extra whitespace", () => {
    const out = MountInfo.parseMountPairs(
        'LABEL="data"   TARGET="/data"   UUID="u1"\n');
    assert.deepEqual(out, [{ uuid: "u1", label: "data", mountpoint: "/data" }]);
});

test("parseMountPairs: empty / non-string input → []", () => {
    assert.deepEqual(MountInfo.parseMountPairs(""), []);
    assert.deepEqual(MountInfo.parseMountPairs(null), []);
    assert.deepEqual(MountInfo.parseMountPairs(undefined), []);
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

test("MountInfo.qml runs findmnt -P by bare name (portable — engine has session PATH)", () => {
    assert.match(QML, /"findmnt -P /,
        "must invoke bare findmnt with -P pairs output (no hardcoded path)");
    assert.doesNotMatch(QML, /\/(usr\/)?s?bin\/findmnt/,
        "must NOT hardcode an absolute findmnt path (portability)");
});

test("MountInfo.qml classifies through the shared helpers, not its own copy", () => {
    assert.match(QML, /MountInfo\.parseMountPairs\s*\(/, "must parse via MountInfo.js");
    assert.match(QML, /DiskMetrics\.isRemovableMount\s*\(/,
        "must classify removable via the shared core predicate");
});

test("MountInfo.qml keeps last-good on a failed run (no flicker to empty)", () => {
    // A nonzero exit must not overwrite `mounted` — see review finding #2.
    assert.match(QML, /data\["exit code"\]\s*!==\s*0/,
        "must bail before updating when findmnt exits nonzero");
});

test("MountInfo.qml gates the poll Timer on `active` (no consumer ⇒ no subprocess)", () => {
    // #59 review finding #1: the poll must be suppressible so a disk-disabled
    // widget spawns nothing. The backend drives `active`.
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
