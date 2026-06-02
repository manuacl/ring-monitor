// Tests for DiskDiscovery.js — standalone /proc/mounts parsing, dedup by
// device, and the $HOME-bearing default selection.

import { createRequire } from "node:module";
import { test } from "node:test";
import assert from "node:assert/strict";

const require = createRequire(import.meta.url);
const Disk = require("../contents/ui/platforms/standalone/DiskDiscovery.js");

// A real /proc/mounts sample (trimmed) from an rpm-ostree host — the
// composefs-overlay `/` + btrfs root mounted at many subvols is the shared
// shape of Silverblue, Kinoite, MicroOS, Bazzite, … (it's where this was
// captured, not a target: the parser keys on mount topology, never a distro).
// The btrfs root (sda3) is mounted 5×; composefs / + a fuse AppImage + tmpfs
// must be dropped, and so must sda1 (the vfat ESP at /boot/efi) as the EFI
// System Partition (issue #66). sda2 is the ext4 xbootldr partition at /boot
// — NOT the ESP, and Plasma shows it, so it stays. This is the live shape
// that motivated the feature.
const OSTREE_MOUNTS =
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
    const m = Disk.parseMounts(OSTREE_MOUNTS);
    const devices = m.map((x) => x.device);
    assert.ok(!devices.includes("composefs"), "composefs overlay must be dropped");
    assert.ok(!devices.includes("tmpfs"), "tmpfs must be dropped");
    assert.ok(!devices.includes("Limux.AppImage"), "fuse AppImage must be dropped");
    // sda3 appears 5×; sda1 (vfat ESP at /boot/efi) is dropped; sda2 (ext4
    // /boot) and the other three block devices stay, once each = 9 entries.
    assert.equal(m.length, 9);
    assert.ok(devices.includes("/dev/sda2"), "ext4 /boot (xbootldr) must be kept");
    assert.ok(!devices.includes("/dev/sda1"), "vfat ESP at /boot/efi must be dropped");
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

test("parseMounts: drops the vfat ESP, keeps the ext4 /boot (issue #66)", () => {
    // SCENARIO: the standalone picker listed sda1 (the vfat ESP at /boot/efi)
    // that the Plasma/ksystemstats picker omits. Only the ESP is filtered —
    // matched as FAT-family on an EFI mountpoint (/boot/efi or systemd-boot
    // /efi). An ext4 /boot (xbootldr) is NOT the ESP and must survive, since
    // Plasma shows it.
    const m = Disk.parseMounts(
        "/dev/sda1 /boot/efi vfat rw 0 0\n" +
        "/dev/sda2 /boot ext4 rw 0 0\n" +
        "/dev/sda3 /efi vfat rw 0 0\n" +
        "/dev/sda4 / ext4 rw 0 0\n",
    );
    assert.deepEqual(m.map((x) => x.mountpoint), ["/boot", "/"]);
});

test("parseMounts: drops a vfat ESP mounted straight at /boot (no-xbootldr layout)", () => {
    // On a simple layout the ESP is mounted directly at /boot and is vfat —
    // the fstype gate still fires, so it's dropped.
    const m = Disk.parseMounts("/dev/sda1 /boot vfat rw 0 0\n");
    assert.equal(m.length, 0);
});

test("parseMounts: keeps a FAT data disk mounted off the EFI path", () => {
    // A vfat USB/data partition the user mounted elsewhere is NOT the ESP —
    // the mountpoint gate keeps it (Plasma would show it too).
    const m = Disk.parseMounts(
        "/dev/sdd1 /run/media/manu/USB vfat rw 0 0\n" +
        "/dev/sde1 /bootdata ext4 rw 0 0\n",
    );
    assert.deepEqual(m.map((x) => x.mountpoint), ["/run/media/manu/USB", "/bootdata"]);
});

// ── buildPartitions (dedup by device) ────────────────────────────────

test("buildPartitions: collapses the 5 sda3 mounts into ONE partition", () => {
    const m = Disk.parseMounts(OSTREE_MOUNTS);
    const parts = Disk.buildPartitions(m, {});
    const sda3 = parts.filter((p) => p.device === "/dev/sda3");
    assert.equal(sda3.length, 1, "sda3 mounted 5× must dedup to one entry");
    // Unique devices: sda3, sda2 (ext4 /boot), nvme0n1p1, sdc1, sdb1 = 5.
    // Only sda1 (the vfat ESP at /boot/efi) is filtered (issue #66).
    assert.equal(parts.length, 5);
});

test("buildPartitions: id = fs UUID, label = volume label when known", () => {
    const m = Disk.parseMounts(OSTREE_MOUNTS);
    const blockInfo = {
        "/dev/sda3": { uuid: "6286e04e-b217-43bf-834f-d6a054ac4376", label: "root" },
    };
    const parts = Disk.buildPartitions(m, blockInfo);
    const sda3 = parts.find((p) => p.device === "/dev/sda3");
    assert.equal(sda3.id, "6286e04e-b217-43bf-834f-d6a054ac4376");
    assert.equal(sda3.label, "root");
});

test("buildPartitions: carries the fstype (same across a device's mounts) for the tooltip (#68)", () => {
    const m = Disk.parseMounts(OSTREE_MOUNTS);
    const parts = Disk.buildPartitions(m, {});
    const sda3 = parts.find((p) => p.device === "/dev/sda3");
    assert.equal(sda3.fstype, "btrfs"); // the btrfs root, mounted 5× → one fstype
});

test("buildPartitions: falls back to device path / basename without blockInfo", () => {
    const m = Disk.parseMounts(OSTREE_MOUNTS);
    const parts = Disk.buildPartitions(m, {});
    const sda3 = parts.find((p) => p.device === "/dev/sda3");
    assert.equal(sda3.id, "/dev/sda3");   // no UUID → device path is the id
    assert.equal(sda3.label, "sda3");     // no label → device basename
});

// ── defaultSelection ($HOME-bearing filesystem) ──────────────────────

test("defaultSelection: picks the FS bearing $HOME via longest mountpoint prefix", () => {
    // SCENARIO: on an rpm-ostree host $HOME=/home/user resolves to
    // /var/home/user. The longest matching mountpoint is /var/home (not /var
    // or /), both on sda3 → the home partition is sda3.
    const m = Disk.parseMounts(OSTREE_MOUNTS);
    const blockInfo = {
        "/dev/sda3": { uuid: "6286e04e-b217-43bf-834f-d6a054ac4376", label: "root" },
    };
    const parts = Disk.buildPartitions(m, blockInfo);
    const sel = Disk.defaultSelection(m, parts, "/var/home/manu");
    assert.deepEqual(sel, ["6286e04e-b217-43bf-834f-d6a054ac4376"]);
});

test("defaultSelection: empty when home cannot be resolved", () => {
    const m = Disk.parseMounts(OSTREE_MOUNTS);
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

// ── defaultOrFirst (shared by the backend + the picker; must agree) ──

test("defaultOrFirst: returns the home FS when detected", () => {
    const m = Disk.parseMounts(OSTREE_MOUNTS);
    const parts = Disk.buildPartitions(m, {});
    assert.deepEqual(Disk.defaultOrFirst(m, parts, "/var/home/manu"), ["/dev/sda3"]);
});

test("defaultOrFirst: falls back to the first partition when home detection fails", () => {
    // SCENARIO (re-review): the backend rendered parts[0] but the picker
    // seeded [] because only the backend had this fallback — widget showed a
    // ring while every checkbox was unchecked. Both now use defaultOrFirst.
    const m = Disk.parseMounts(OSTREE_MOUNTS);
    const parts = Disk.buildPartitions(m, {});
    const fallback = Disk.defaultOrFirst(m, parts, ""); // home unresolved
    assert.equal(fallback.length, 1);
    assert.equal(fallback[0], parts[0].id);
});

test("defaultOrFirst: empty when there are no partitions at all", () => {
    assert.deepEqual(Disk.defaultOrFirst([], [], "/home/x"), []);
});
