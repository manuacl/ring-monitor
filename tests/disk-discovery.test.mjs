// Tests for DiskDiscovery.js — standalone /proc/mounts parsing, dedup by
// device, and the $HOME-bearing default selection.

import { createRequire } from "node:module";
import { test } from "node:test";
import assert from "node:assert/strict";

const require = createRequire(import.meta.url);
const Disk = require("../contents/ui/platforms/standalone/DiskDiscovery.js");

// Real Bazzite /proc/mounts sample (trimmed to the relevant lines). The
// btrfs root (sda3) is mounted 5×; composefs / + a fuse AppImage + tmpfs
// must be dropped. This is the live shape that motivated the feature.
const BAZZITE_MOUNTS =
    "composefs / overlay ro,relatime 0 0\n" +
    "/dev/sda3 /etc btrfs rw,relatime,subvol=/etc 0 0\n" +
    "/dev/sda3 /sysroot btrfs ro,relatime 0 0\n" +
    "/dev/sda3 /sysroot/ostree/deploy/default/var btrfs rw 0 0\n" +
    "/dev/sda3 /var btrfs rw,relatime 0 0\n" +
    "/dev/sda2 /boot ext4 rw,relatime 0 0\n" +
    "/dev/sda3 /var/home btrfs rw,relatime 0 0\n" +
    "/dev/sda1 /boot/efi vfat rw,relatime 0 0\n" +
    "/dev/nvme0n1p1 /var/mnt/samsung ext4 rw 0 0\n" +
    "/dev/sdc1 /var/mnt/sync btrfs rw 0 0\n" +
    "/dev/sdb1 /var/mnt/photos ext4 rw 0 0\n" +
    "tmpfs /run tmpfs rw,nosuid 0 0\n" +
    "Limux.AppImage /tmp/.mount_Limux fuse.Limux.AppImage ro 0 0\n";

// ── parseMounts ──────────────────────────────────────────────────────

test("parseMounts: drops composefs/tmpfs/fuse, keeps /dev block devices", () => {
    const m = Disk.parseMounts(BAZZITE_MOUNTS);
    const devices = m.map((x) => x.device);
    assert.ok(!devices.includes("composefs"), "composefs overlay must be dropped");
    assert.ok(!devices.includes("tmpfs"), "tmpfs must be dropped");
    assert.ok(!devices.includes("Limux.AppImage"), "fuse AppImage must be dropped");
    // sda3 appears 5×, the other five block devices once each = 10 entries.
    assert.equal(m.length, 10);
});

test("parseMounts: drops loop-mounted squashfs system images", () => {
    const m = Disk.parseMounts("/dev/loop0 /var/lib/snapd/snap/core squashfs ro 0 0\n");
    assert.equal(m.length, 0);
});

test("parseMounts: un-escapes octal-escaped mountpoints (spaces)", () => {
    const m = Disk.parseMounts("/dev/sdd1 /mnt/My\\040Disk ext4 rw 0 0\n");
    assert.equal(m[0].mountpoint, "/mnt/My Disk");
});

test("parseMounts: tolerates empty / malformed input", () => {
    assert.deepEqual(Disk.parseMounts(""), []);
    assert.deepEqual(Disk.parseMounts(null), []);
    assert.deepEqual(Disk.parseMounts("garbage line\n"), []);
});

// ── buildPartitions (dedup by device) ────────────────────────────────

test("buildPartitions: collapses the 5 sda3 mounts into ONE partition", () => {
    const m = Disk.parseMounts(BAZZITE_MOUNTS);
    const parts = Disk.buildPartitions(m, {});
    const sda3 = parts.filter((p) => p.device === "/dev/sda3");
    assert.equal(sda3.length, 1, "sda3 mounted 5× must dedup to one entry");
    // 5 unique devices total: sda3, sda2, sda1, nvme0n1p1, sdc1, sdb1 = 6.
    assert.equal(parts.length, 6);
});

test("buildPartitions: id = fs UUID, label = volume label when known", () => {
    const m = Disk.parseMounts(BAZZITE_MOUNTS);
    const blockInfo = {
        "/dev/sda3": { uuid: "6286e04e-b217-43bf-834f-d6a054ac4376", label: "bazzite" },
    };
    const parts = Disk.buildPartitions(m, blockInfo);
    const sda3 = parts.find((p) => p.device === "/dev/sda3");
    assert.equal(sda3.id, "6286e04e-b217-43bf-834f-d6a054ac4376");
    assert.equal(sda3.label, "bazzite");
});

test("buildPartitions: falls back to device path / basename without blockInfo", () => {
    const m = Disk.parseMounts(BAZZITE_MOUNTS);
    const parts = Disk.buildPartitions(m, {});
    const sda3 = parts.find((p) => p.device === "/dev/sda3");
    assert.equal(sda3.id, "/dev/sda3");   // no UUID → device path is the id
    assert.equal(sda3.label, "sda3");     // no label → device basename
});

// ── defaultSelection ($HOME-bearing filesystem) ──────────────────────

test("defaultSelection: picks the FS bearing $HOME via longest mountpoint prefix", () => {
    // SCENARIO: on Bazzite $HOME=/home/manu resolves to /var/home/manu.
    // The longest matching mountpoint is /var/home (not /var or /), both on
    // sda3 → the home partition is sda3 ("bazzite").
    const m = Disk.parseMounts(BAZZITE_MOUNTS);
    const blockInfo = {
        "/dev/sda3": { uuid: "6286e04e-b217-43bf-834f-d6a054ac4376", label: "bazzite" },
    };
    const parts = Disk.buildPartitions(m, blockInfo);
    const sel = Disk.defaultSelection(m, parts, "/var/home/manu");
    assert.deepEqual(sel, ["6286e04e-b217-43bf-834f-d6a054ac4376"]);
});

test("defaultSelection: empty when home cannot be resolved", () => {
    const m = Disk.parseMounts(BAZZITE_MOUNTS);
    const parts = Disk.buildPartitions(m, {});
    assert.deepEqual(Disk.defaultSelection(m, parts, ""), []);
    assert.deepEqual(Disk.defaultSelection(m, parts, null), []);
});

test("defaultSelection: a plain /home mount is matched directly", () => {
    const mounts = "/dev/sda2 /home ext4 rw 0 0\n/dev/sda1 / ext4 rw 0 0\n";
    const m = Disk.parseMounts(mounts);
    const parts = Disk.buildPartitions(m, {});
    const sel = Disk.defaultSelection(m, parts, "/home/alice");
    assert.deepEqual(sel, ["/dev/sda2"]);
});
