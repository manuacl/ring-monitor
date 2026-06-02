// Pure discovery logic for the standalone disk multi-partition ring.
//
// Standalone-only (the Plasma build gets the same information from
// ksysguard's per-filesystem sensors), so it lives beside the standalone
// adapter rather than in core/ — same placement rule as the /proc parsers.
//
// The MetricsBackend feeds three raw inputs from the ProcReader C++ helper:
//   - /proc/mounts contents          → parseMounts
//   - ProcReader.blockDeviceInfo()    → device → { uuid, label }
//   - ProcReader.canonicalHome()      → resolved $HOME for the default pick
// and this module turns them into the partition list + default selection.
//
// Why dedup by device: a single filesystem (e.g. the btrfs root) is often
// mounted at many paths (/etc, /var, /var/home, /sysroot on an rpm-ostree
// host). They all report identical statvfs numbers, so we collapse them to
// ONE partition per device — exactly what ksysguard does on the Plasma side
// (it keys per-filesystem by UUID and shows one entry per FS).
//
// Dual-loaded by QML and Node. No `.pragma library`.
//
// Public surface:
//   parseMounts(content)                 - [{device, mountpoint, fstype}]
//                                          for real block-device filesystems
//                                          only (drops composefs/overlay/
//                                          tmpfs/fuse/squashfs pseudo mounts,
//                                          and the EFI System Partition —
//                                          see _isEfiSystemPartition, #66).
//   buildPartitions(mounts, blockInfo)   - dedup by device → [{id, label,
//                                          mountpoint, fstype, device}]; id = fs UUID
//                                          (falls back to device), label =
//                                          volume label (falls back to device
//                                          basename), mountpoint = a
//                                          representative mount for statvfs.
//   defaultSelection(mounts, partitions, canonicalHome)
//                                        - [id] of the filesystem bearing
//                                          $HOME (longest mountpoint prefix),
//                                          or [] if none matched.

// Filesystem types to drop even when the device looks like a block device
// (loop-mounted read-only system images — snaps, etc.). composefs/overlay/
// tmpfs/fuse are already excluded by the "/dev/" device prefix check.
var _SKIP_FSTYPES = { squashfs: true };

// The EFI System Partition (ESP) is a real block device — a FAT-family
// filesystem mounted at the firmware boot path — so the "/dev/" + fstype
// rules above don't catch it. ksystemstats exposes no usedPercent sensor
// for the ESP, so the Plasma picker omits it; we mirror that so the two
// builds' partition sets agree (issue #66).
//
// We match on BOTH an EFI mountpoint AND a FAT fstype, deliberately narrow:
//   - DON'T drop the xbootldr /boot partition (typically ext4) — it is NOT
//     the ESP and Plasma DOES show it. An earlier "/boot prefix" rule
//     wrongly hid it.
//   - DON'T drop a user's FAT data disk mounted elsewhere (e.g. a vfat USB
//     under /run/media) — it's not on an EFI mountpoint.
// /boot is included in the mountpoint set only for the no-xbootldr layout
// where the ESP itself is mounted straight at /boot (then it IS vfat, so the
// fstype gate still fires); an ext4 /boot fails the fstype gate and stays.
var _EFI_MOUNTS = { "/boot/efi": true, "/efi": true, "/boot": true };
var _FAT_FSTYPES = { vfat: true, msdos: true, fat: true };

function _isEfiSystemPartition(mountpoint, fstype) {
    return _EFI_MOUNTS[mountpoint] === true && _FAT_FSTYPES[fstype] === true;
}

// /proc/mounts octal-escapes space (\040), tab (\011), newline (\012) and
// backslash (\134) in the device and mountpoint fields.
function _unescapeOctal(s) {
    return s.replace(/\\([0-7]{3})/g, function (_, oct) {
        return String.fromCharCode(parseInt(oct, 8));
    });
}

function _basename(path) {
    var parts = String(path).split("/");
    return parts[parts.length - 1] || path;
}

function parseMounts(content) {
    var out = [];
    if (typeof content !== "string" || content.length === 0)
        return out;
    var lines = content.split("\n");
    for (var i = 0; i < lines.length; i++) {
        var fields = lines[i].split(/\s+/);
        if (fields.length < 3)
            continue;
        var device = _unescapeOctal(fields[0]);
        var mountpoint = _unescapeOctal(fields[1]);
        var fstype = fields[2];
        // Real, user-relevant storage = a /dev block device whose fstype
        // isn't a loop-mounted system image. This single rule drops
        // composefs (device "composefs"), tmpfs/devtmpfs, overlay, and the
        // fuse mounts (device is the fuse program, not /dev/...).
        if (device.indexOf("/dev/") !== 0)
            continue;
        if (_SKIP_FSTYPES[fstype])
            continue;
        if (_isEfiSystemPartition(mountpoint, fstype))
            continue;
        out.push({ device: device, mountpoint: mountpoint, fstype: fstype });
    }
    return out;
}

// Shortest mountpoint wins as the representative (fewest path segments,
// then lexicographic) — it's only used for the statvfs call, which returns
// identical numbers for any mount of the same filesystem.
function _representativeMount(mountpoints) {
    var best = mountpoints[0];
    for (var i = 1; i < mountpoints.length; i++) {
        var m = mountpoints[i];
        var mSeg = m.split("/").length;
        var bSeg = best.split("/").length;
        if (mSeg < bSeg || (mSeg === bSeg && m < best))
            best = m;
    }
    return best;
}

function buildPartitions(mounts, blockInfo) {
    blockInfo = blockInfo || {};
    var order = [];
    var byDevice = {};
    // fstype is a property of the filesystem, so it's identical across every
    // mount of one device — keep the first seen (feeds the #68 tooltip).
    var fstypeByDevice = {};
    for (var i = 0; i < mounts.length; i++) {
        var dev = mounts[i].device;
        if (!byDevice[dev]) {
            byDevice[dev] = [];
            order.push(dev);
        }
        byDevice[dev].push(mounts[i].mountpoint);
        if (fstypeByDevice[dev] === undefined)
            fstypeByDevice[dev] = mounts[i].fstype || "";
    }
    var out = [];
    for (var j = 0; j < order.length; j++) {
        var device = order[j];
        var info = blockInfo[device] || {};
        out.push({
            id: info.uuid || device,
            label: info.label || _basename(device),
            mountpoint: _representativeMount(byDevice[device]),
            fstype: fstypeByDevice[device] || "",
            device: device,
        });
    }
    return out;
}

// True when `mountpoint` is an ancestor of (or equal to) `path`.
function _isPrefixPath(mountpoint, path) {
    if (mountpoint === path)
        return true;
    if (mountpoint === "/")
        return path.indexOf("/") === 0;
    return path.indexOf(mountpoint + "/") === 0;
}

function defaultSelection(mounts, partitions, canonicalHome) {
    if (!canonicalHome || !mounts || mounts.length === 0)
        return [];
    var bestDevice = "";
    var bestLen = -1;
    for (var i = 0; i < mounts.length; i++) {
        var mp = mounts[i].mountpoint;
        if (_isPrefixPath(mp, canonicalHome) && mp.length > bestLen) {
            bestLen = mp.length;
            bestDevice = mounts[i].device;
        }
    }
    if (!bestDevice)
        return [];
    for (var j = 0; j < partitions.length; j++) {
        if (partitions[j].device === bestDevice)
            return [partitions[j].id];
    }
    return [];
}

// The selection the disk ring defaults to when the user has chosen nothing:
// the $HOME-bearing filesystem, falling back to the first discovered
// partition so the ring is never empty on an exotic layout where home
// detection fails. Used by BOTH the backend (what the widget renders) and
// the SettingsDialog (what the picker seeds) — they MUST agree, or the
// widget shows a ring while the picker shows everything unchecked.
function defaultOrFirst(mounts, partitions, canonicalHome) {
    var def = defaultSelection(mounts, partitions, canonicalHome);
    if (def.length === 0 && partitions && partitions.length > 0)
        return [partitions[0].id];
    return def;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        parseMounts: parseMounts,
        buildPartitions: buildPartitions,
        defaultSelection: defaultSelection,
        defaultOrFirst: defaultOrFirst,
    };
}
