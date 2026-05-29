// Plasma-only: parse `lsblk` pairs output into the mounted-filesystem list.
//
// ksysguard exposes no mountpoint and no removable flag (only the volume
// label + usedPercent/…), so the Plasma build cannot tell a user-plugged USB
// key from a fixed disk by sensors alone. We get that missing data by running
//   lsblk -P -o UUID,MOUNTPOINT,LABEL
// through plasma5support's executable DataSource (see MountInfo.qml) and
// parsing it here. The UUID is exactly ksysguard's disk/<uuid> key, so the
// rows join straight onto the per-partition sensors.
//
// Pairs (`-P`) output, one line per device, robust against spaces in the
// label / mountpoint:
//   UUID="6f45-2b2f" MOUNTPOINT="/run/media/manu/BIOS" LABEL="BIOS"
//
// Removable classification is NOT done here — it's the shared
// DiskMetrics.isRemovableMount(mountpoint) predicate, applied by the consumer
// so the standalone /proc path classifies through the same rule.
//
// Dual-loaded by QML (`import "MountInfo.js" as MountInfo`) and Node.
//
// Public surface:
//   parseLsblkPairs(stdout) - [{uuid, label, mountpoint}], one per mounted
//                             filesystem that has a UUID and an absolute-path
//                             mountpoint. Rows without a UUID, unmounted rows
//                             (empty mountpoint), and pseudo-mounts whose
//                             mountpoint isn't a path (lsblk prints "[SWAP]")
//                             are dropped; duplicate UUIDs keep the first row.

function parseLsblkPairs(stdout) {
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
        var uuid = row.UUID || "";
        var mountpoint = row.MOUNTPOINT || "";
        // Absolute-path mountpoint only: drops unmounted rows ("") and lsblk's
        // "[SWAP]" pseudo-mount in one test.
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
        parseLsblkPairs: parseLsblkPairs,
    };
}
