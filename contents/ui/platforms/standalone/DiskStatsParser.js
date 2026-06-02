// Pure parser for `/proc/diskstats` — standalone-build companion to the
// Plasma adapter's ksysguard `disk/all/{read,write}` sensors (issue #77).
//
// Only the standalone backend reads /proc, so this lives beside its
// adapter (the placement rule in ../../core/CLAUDE.md), not in core/.
// The peak-scaling + MB/s formatting it feeds into IS shared, so that
// half lives in core/DiskIoScale.js; this module is just the
// /proc/diskstats → byte/s glue.
//
// `/proc/diskstats` exposes monotonic per-device counters. To get a
// throughput you need two samples an interval apart and the delta of the
// sector counters × 512 B (the kernel reports diskstats sectors as 512 B
// regardless of the device's physical/logical sector size) over the
// elapsed time.
//
// Sample line (kernel 6.x):
//
//   259  0 nvme0n1 125043 4821 9876543 41230 ...
//
// Fields after the device name, in order: reads_completed, reads_merged,
// sectors_read, ms_reading, writes_completed, writes_merged,
// sectors_written, ms_writing, ios_in_progress, ms_doing_io, ...
// (newer kernels append discard + flush fields; we read only the two
// sector counters, so trailing additions are ignored).
//
// Aggregation counts WHOLE physical disks only — summing a disk and its
// partitions (sda + sda1 + sda2) would multiply the throughput. Virtual
// stacked devices (loop/ram/zram/dm-/md/sr/fd) are excluded for the same
// reason and because they don't represent real spindle/flash traffic.
//
// Dual-loaded by QML and Node (module.exports shim at the bottom).
//
// Public surface:
//   parseDiskStats(content)               - { name: {readSectors, writeSectors} }
//   aggregateWholeDisks(map)              - {readSectors, writeSectors} over physical disks
//   ratesFromSamples(prev, cur, secs)     - {readBps, writeBps}; wrap/zero-safe

var SECTOR_BYTES = 512;

// Token indices AFTER the device name (parts[2]). sectors_read is the
// 3rd post-name field, sectors_written the 7th.
var IDX_SECTORS_READ = 5;
var IDX_SECTORS_WRITTEN = 9;

// Virtual / stacked block devices that don't represent physical disk
// traffic (or would double-count it). Each of these classes is always
// numbered (loop0, ram0, zram0, dm-0, md0, sr0, fd0), so the trailing
// `\d` anchors the match to the real device families and stops the bare
// prefixes from swallowing an unrelated physical disk whose name merely
// starts with the same letters (e.g. a hypothetical `dm…` without the
// `dm-` hyphen).
var VIRTUAL_PREFIX_RE = /^(loop|ram|zram|dm-|md|sr|fd)\d/;

function parseDiskStats(content) {
    var out = {};
    if (typeof content !== "string" || content.length === 0)
        return out;
    var lines = content.split("\n");
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        if (line.length === 0)
            continue;
        var parts = line.split(/\s+/);
        // major minor name + at least the two sector counters we read.
        if (parts.length <= IDX_SECTORS_WRITTEN)
            continue;
        var name = parts[2];
        if (!name)
            continue;
        var readSectors = parseInt(parts[IDX_SECTORS_READ], 10);
        var writeSectors = parseInt(parts[IDX_SECTORS_WRITTEN], 10);
        out[name] = {
            "readSectors": isNaN(readSectors) ? 0 : readSectors,
            "writeSectors": isNaN(writeSectors) ? 0 : writeSectors
        };
    }
    return out;
}

function _isVirtual(name) {
    return VIRTUAL_PREFIX_RE.test(name);
}

// A device is a sub-device of a whole disk present in the same snapshot
// — counting both would multiply the throughput. Two naming schemes:
//   - Ordinary partitions: trailing digits, optional `p` separator for
//     nvme/mmcblk — sda1→sda, nvme0n1p2→nvme0n1, mmcblk0p1→mmcblk0. A
//     whole disk's stripped form isn't present (nvme0n1→nvme0n; sda has
//     no trailing digit). The `\d+` (not strict-prefix) matters: it
//     keeps nvme0n11 a whole namespace rather than a "partition" of
//     nvme0n1.
//   - eMMC hardware areas: mmcblk0boot0 / mmcblk0boot1 / mmcblk0rpmb sit
//     beside the data device and carry near-zero traffic; without this
//     they'd survive the digit rule (mmcblk0boot0→mmcblk0boot, absent)
//     and double-count.
function _isPartitionOf(name, namesSet) {
    var m = /^(.*?)(\d+)$/.exec(name);
    if (m) {
        var base = m[1];
        if (namesSet[base])
            return true;
        if (base.charAt(base.length - 1) === "p" && namesSet[base.slice(0, -1)])
            return true;
    }
    var area = /^(.*?)(boot\d+|rpmb)$/.exec(name);
    if (area && namesSet[area[1]])
        return true;
    return false;
}

// Sum the sector counters across whole physical disks (drop virtual
// devices and partitions). The result is what feeds the aggregate
// `disk/all`-style throughput ring.
function aggregateWholeDisks(map) {
    var total = { "readSectors": 0, "writeSectors": 0 };
    if (!map)
        return total;
    var names = Object.keys(map);
    var namesSet = {};
    for (var i = 0; i < names.length; i++)
        namesSet[names[i]] = true;
    for (var j = 0; j < names.length; j++) {
        var name = names[j];
        if (_isVirtual(name) || _isPartitionOf(name, namesSet))
            continue;
        total.readSectors += map[name].readSectors;
        total.writeSectors += map[name].writeSectors;
    }
    return total;
}

// Throughput in bytes/s from two {readSectors, writeSectors} samples
// over `intervalSec` seconds. A negative delta (counter reset on device
// re-enumeration, or prev>cur after a hotplug) clamps to 0 rather than
// flashing a huge spurious rate. Non-positive interval → 0.
function ratesFromSamples(prev, cur, intervalSec) {
    if (!prev || !cur || !(intervalSec > 0))
        return { "readBps": 0, "writeBps": 0 };
    var dRead = (cur.readSectors - prev.readSectors) * SECTOR_BYTES;
    var dWrite = (cur.writeSectors - prev.writeSectors) * SECTOR_BYTES;
    if (dRead < 0) dRead = 0;
    if (dWrite < 0) dWrite = 0;
    return {
        "readBps": dRead / intervalSec,
        "writeBps": dWrite / intervalSec
    };
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        SECTOR_BYTES: SECTOR_BYTES,
        parseDiskStats: parseDiskStats,
        aggregateWholeDisks: aggregateWholeDisks,
        ratesFromSamples: ratesFromSamples
    };
}
