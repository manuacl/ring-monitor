// Plasma-only: parse `findmnt` pairs output into the mounted-filesystem list.
//
// ksysguard exposes no mountpoint and no removable flag (only the volume
// label + usedPercent/…), so the Plasma build cannot tell a user-plugged USB
// key from a fixed disk by sensors alone — nor can it tell whether a partition
// is still mounted (its SensorTreeModel freezes on unmount, #58). We get that
// missing data by running
//   findmnt -P -o UUID,TARGET,LABEL
// through plasma5support's executable DataSource (see MountInfo.qml) and
// parsing it here. findmnt reads the kernel mount table (/proc/self/mountinfo),
// so — unlike lsblk's block-device view — it lists EVERY mount, including a
// btrfs filesystem surfaced only through subvolumes (which lsblk's singular
// MOUNTPOINT column can report empty), and a network / fuse mount. It also
// reflects an unmount immediately. The UUID is exactly ksysguard's disk/<uuid>
// key, so the rows join straight onto the per-partition sensors — which is what
// lets the live-mount self-heal gate trust "absent here ⇒ no longer mounted".
//
// Pairs (`-P`) output, one line per mount, robust against spaces in the
// label / target:
//   UUID="6f45-2b2f" TARGET="/run/media/manu/BIOS" LABEL="BIOS"
//
// The UUID is lower-cased: findmnt (via libblkid) prints FAT/vfat volume
// serials in UPPERCASE (e.g. "6F45-2B2F") while ksysguard keys its disk/<uuid>
// sensors — and thus the persisted enabledPartitions / partitionLabels — in
// lowercase. Without this, a vfat USB key's UUID would never match its
// ksysguard sensor or the saved selection, so its ring would render at 0% and
// the self-heal gate would wrongly drop it. ext4/btrfs UUIDs are already
// lowercase, so this is a no-op for them. (Confirmed live: "6F45-2B2F" vs
// config "6f45-2b2f" for the BIOS key.)
//
// A filesystem mounted at several targets (a btrfs root at /, /var, /home; any
// bind mount) appears on several findmnt lines with the same UUID — we keep the
// first and dedup the rest. Pseudo / network mounts with no UUID (proc, tmpfs,
// cgroup, NFS, fuse) carry an empty UUID and are dropped: they have no
// disk/<uuid> sensor to join onto anyway.
//
// Removable classification is NOT done here — it's the shared
// DiskMetrics.isRemovableMount(mountpoint) predicate, applied by the consumer
// so the standalone /proc path classifies through the same rule.
//
// Dual-loaded by QML (`import "MountInfo.js" as MountInfo`) and Node.
//
// Public surface:
//   parseMountPairs(stdout) - [{uuid, label, mountpoint}], one per mounted
//                             filesystem that has a UUID and an absolute-path
//                             target. Rows without a UUID and rows whose target
//                             isn't an absolute path are dropped; a duplicate
//                             UUID keeps the first row.

function parseMountPairs(stdout) {
    var out = [];
    if (typeof stdout !== "string" || stdout.length === 0)
        return out;
    var seen = {};
    var lines = stdout.split("\n");
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        if (!line)
            continue;
        var row = {};
        var re = /([A-Z_]+)="([^"]*)"/g;
        var m;
        while ((m = re.exec(line)) !== null)
            row[m[1]] = m[2];
        // Lower-case to match ksysguard's lowercase disk/<uuid> keys — findmnt
        // emits FAT/vfat serials uppercase (see the header note).
        var uuid = (row.UUID || "").toLowerCase();
        var mountpoint = row.TARGET || "";
        // Absolute-path target only: drops the no-UUID pseudo rows and any row
        // whose target isn't a real path, keeping the join keyed on real
        // mounted filesystems.
        if (!uuid || mountpoint.indexOf("/") !== 0 || seen[uuid])
            continue;
        seen[uuid] = true;
        out.push({
            uuid: uuid,
            label: row.LABEL || uuid,
            mountpoint: mountpoint,
        });
    }
    return out;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        parseMountPairs: parseMountPairs,
    };
}
