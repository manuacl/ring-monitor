// Pure helpers for the multi-partition disk ring (shared by both platforms).
//
// The disk metric can render as N equal-thickness concentric rings, one per
// selected filesystem, with the centre number being the average of the
// displayed partitions. The per-partition discovery + value reads are
// platform-specific (ksysguard on Plasma, /proc/mounts + statvfs on
// standalone — see platforms/*/), but the two view-side computations below
// are identical on both hosts, so they live in core/ and are Node-tested.
//
// Dual-loaded by QML and Node. No `.pragma library`.
//
// Public surface:
//   averagePercent(values)              - mean of a 0-100 array, 0 on empty
//                                         or any non-finite member (the centre
//                                         readout for the multi-ring disk).
//   sortByLabel(partitions)             - alphabetical (case-insensitive) by
//                                         label; the default picker order.
//   orderPartitions(savedOrderCsv, available)
//                                       - saved order first, then newly-
//                                         discovered appended alphabetically.
//   resolveDiskRingIds(manualIds, removableMounts, optOutIds, defaultIds,
//                      maxCount, mountedIds)
//                                       - the final ordered set of disk rings to
//                                         draw: the manual selection (gated on
//                                         the live mountedIds set so an unmounted
//                                         partition's ring self-heals away)
//                                         unioned with the currently-mounted
//                                         removable media (auto-show), minus user
//                                         opt-outs, falling back to defaultIds
//                                         when empty, capped at maxCount.
//   stalePartitions(enabledCsv, orderCsv, discovered, labelCacheJson)
//                                       - configured ids no longer present
//                                         (unplugged), each {id, label}.
//   parseLabelCache / serializeLabelCache / mergeLabelCache
//                                       - the UUID→label cache backing the
//                                         friendly name on stale rows.
//   isRemovableMount(mountpoint)        - true when a filesystem's mountpoint
//                                         marks it as user-plugged removable
//                                         media (auto-show / auto-check).
//
// Selecting the enabled subset in display order is done with the existing
// MetricsCatalog.filterByOrder(enabledCsvIds, orderedIds) — no disk-specific
// helper (it was a duplicate of filterByOrder with the args swapped).

// KDE's udisks2 auto-mounts a user-plugged removable filesystem under
// /run/media/<user>/ (older / non-KDE setups use /media/<user>/); fixed disks
// mount under /, /boot, /var, /home, … So the mountpoint prefix is the
// portable "did the user just plug this in?" signal. It's the only such signal
// available on Plasma — ksysguard exposes no removable flag — and the
// standalone /proc/mounts path sees the same mountpoints, so both platforms
// classify identically through this one helper.
function isRemovableMount(mountpoint) {
    if (typeof mountpoint !== "string" || mountpoint.length === 0)
        return false;
    return mountpoint.indexOf("/run/media/") === 0 || mountpoint.indexOf("/media/") === 0;
}

function averagePercent(values) {
    if (!values || values.length === 0)
        return 0;
    var sum = 0;
    for (var i = 0; i < values.length; i++) {
        var v = values[i];
        if (typeof v !== "number" || !isFinite(v))
            return 0;
        sum += v;
    }
    return sum / values.length;
}

// Return a new array of partitions sorted alphabetically by label
// (case-insensitive), ties broken by id for determinism. Used to order
// the partition checkboxes in the picker. Does not mutate the input.
function sortByLabel(partitions) {
    return (partitions || []).slice().sort(function (a, b) {
        var la = String(a.label || "").toLowerCase();
        var lb = String(b.label || "").toLowerCase();
        if (la < lb)
            return -1;
        if (la > lb)
            return 1;
        if (a.id < b.id)
            return -1;
        if (a.id > b.id)
            return 1;
        return 0;
    });
}

// Order the available partitions for the reorderable picker: ids present
// in the saved order CSV come first (in that order), then any remaining
// (newly-discovered) partitions appended alphabetically by label. Saved
// ids no longer present are dropped. An empty saved order → fully
// alphabetical (the default). Returns a new [{id, label, ...}] array.
//
// Mirror of MetricsCatalog.mergeWithCatalog, but the "catalog" is the
// dynamically-discovered partition set and the default tail is sorted by
// label rather than a fixed canonical sequence. The list order is the ring
// nesting order: first = outermost ring, last = innermost.
function orderPartitions(savedOrderCsv, available) {
    available = available || [];
    var byId = {};
    for (var i = 0; i < available.length; i++)
        byId[available[i].id] = available[i];
    var savedIds = String(savedOrderCsv || "").split(",").filter(function (x) {
        return x;
    });
    var out = [];
    var used = {};
    for (var j = 0; j < savedIds.length; j++) {
        var p = byId[savedIds[j]];
        if (p && !used[savedIds[j]]) {
            out.push(p);
            used[savedIds[j]] = true;
        }
    }
    var rest = [];
    for (var k = 0; k < available.length; k++) {
        if (!used[available[k].id])
            rest.push(available[k]);
    }
    return out.concat(sortByLabel(rest));
}

// The final ordered set of disk-partition ring ids to render. The manual
// selection (the user's explicit checkboxes, already filtered to display order
// by MetricsCatalog.filterByOrder) comes first; then every currently-mounted
// removable filesystem not already manually selected and not in the user's
// opt-out set is appended (the auto-show). An empty union falls back to
// defaultIds — the platform default ([] = aggregate ring on Plasma, the $HOME
// filesystem on standalone). Capped at maxCount so the concentric stack stays
// readable. Order-preserving and deduped.
//
// removableMounts is the live mounted-removable set ([{id, label}], id = the
// UUID) the platform's MountInfo discovers; optOutIds are UUIDs the user hid
// despite being mounted (a Phase 3 override — empty until that lands).
//
// mountedIds is the live set of ALL currently-mounted UUIDs (fixed + removable,
// from lsblk). When supplied (non-empty), a MANUAL id absent from it is dropped:
// that is the #58 self-heal — a configured partition that has been unmounted
// (a removable unplugged) loses its ring whether it was hand-checked or
// auto-checked, while a fixed disk (always mounted) is unaffected. ksysguard's
// own partition list can't drive this because it FREEZES on unmount (still lists
// the gone UUID) — only the live lsblk set reflects reality. An empty/absent
// mountedIds means "no live mount data" (a real system always has a root mount,
// so empty ⇒ the poll hasn't returned yet) or a platform without mount tracking
// (standalone today) → don't gate, so fixed-disk rings aren't hidden during the
// startup poll window. See contents/ui/platforms/plasma/MountInfo.qml and #58.
function resolveDiskRingIds(manualIds, removableMounts, optOutIds, defaultIds, maxCount, mountedIds) {
    manualIds = manualIds || [];
    removableMounts = removableMounts || [];
    var optOut = {};
    var optList = optOutIds || [];
    for (var o = 0; o < optList.length; o++)
        optOut[optList[o]] = true;
    var mounted = null;
    if (mountedIds && mountedIds.length > 0) {
        mounted = {};
        for (var k = 0; k < mountedIds.length; k++)
            mounted[mountedIds[k]] = true;
    }
    var seen = {};
    var out = [];
    for (var i = 0; i < manualIds.length; i++) {
        var mid = manualIds[i];
        if (mid && !seen[mid] && (mounted === null || mounted[mid])) {
            seen[mid] = true;
            out.push(mid);
        }
    }
    for (var j = 0; j < removableMounts.length; j++) {
        var rid = removableMounts[j] && removableMounts[j].id;
        if (rid && !seen[rid] && !optOut[rid]) {
            seen[rid] = true;
            out.push(rid);
        }
    }
    // Empty union → platform default. Route it through the same dedup so the
    // "deduped" contract holds on this path too; opt-out is deliberately NOT
    // applied here (it suppresses removable auto-show, not the platform default).
    if (out.length === 0) {
        var def = defaultIds || [];
        for (var d = 0; d < def.length; d++) {
            var did = def[d];
            if (did && !seen[did]) {
                seen[did] = true;
                out.push(did);
            }
        }
    }
    if (typeof maxCount === "number" && maxCount >= 0)
        out = out.slice(0, maxCount);
    return out;
}

// Mirrors MetricsCatalog.parseCsv — duplicated rather than imported because
// the dual-load (no-pragma) .js modules can't import each other.
function _csvIds(csv) {
    return String(csv || "").split(",").filter(function (x) {
        return x;
    });
}

// Configured partition ids that are no longer discovered — the filesystem was
// unplugged or the disk swapped, yet its UUID lingers in enabledPartitions /
// partitionOrder. Returned in a stable order (order CSV first, then enabled-
// only ids), deduped. The label comes from the last-known-label cache, falling
// back to the bare UUID when never cached. These render as the greyed,
// removable "no longer connected" rows in the picker; the draggable list
// (orderPartitions) still excludes them — ring rendering is unaffected.
function stalePartitions(enabledCsv, orderCsv, discovered, labelCacheJson) {
    discovered = discovered || [];
    var present = {};
    for (var i = 0; i < discovered.length; i++)
        present[discovered[i].id] = true;
    var cache = parseLabelCache(labelCacheJson);
    var seen = {};
    var out = [];
    var sources = [orderCsv, enabledCsv];
    for (var s = 0; s < sources.length; s++) {
        var ids = _csvIds(sources[s]);
        for (var j = 0; j < ids.length; j++) {
            var id = ids[j];
            if (!present[id] && !seen[id]) {
                seen[id] = true;
                out.push({
                    id: id,
                    label: cache[id] || id
                });
            }
        }
    }
    return out;
}

// Parse the persisted UUID→label cache. Tolerates empty / malformed JSON (a
// hand-edited config or a partial write) by returning {} rather than throwing.
function parseLabelCache(json) {
    if (!json)
        return {};
    try {
        var obj = JSON.parse(json);
        return (obj && typeof obj === "object" && !Array.isArray(obj)) ? obj : {};
    } catch (e) {
        return {};
    }
}

// Serialize with sorted keys so an unchanged cache always produces the SAME
// string — assigning it back to the bridged property is then a no-op and
// doesn't trigger a spurious config write on every discovery pass.
function serializeLabelCache(obj) {
    obj = obj || {};
    var keys = Object.keys(obj).sort();
    var ordered = {};
    for (var i = 0; i < keys.length; i++)
        ordered[keys[i]] = obj[keys[i]];
    return JSON.stringify(ordered);
}

// Rebuild the label cache, bounded to the referenced ids (enabled ∪ order):
// take the fresh discovered label when present, else preserve the last-known
// label (so an unplugged partition keeps its friendly name), else omit. Ids no
// longer referenced are dropped so the cache can't grow without bound.
function mergeLabelCache(prevJson, discovered, referencedIds) {
    discovered = discovered || [];
    referencedIds = referencedIds || [];
    var prev = parseLabelCache(prevJson);
    var labelOf = {};
    for (var i = 0; i < discovered.length; i++)
        labelOf[discovered[i].id] = discovered[i].label;
    var out = {};
    var done = {};
    for (var j = 0; j < referencedIds.length; j++) {
        var id = referencedIds[j];
        if (done[id])
            continue;
        done[id] = true;
        if (labelOf.hasOwnProperty(id))
            out[id] = labelOf[id];
        else if (prev.hasOwnProperty(id))
            out[id] = prev[id];
    }
    return serializeLabelCache(out);
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        averagePercent: averagePercent,
        sortByLabel: sortByLabel,
        orderPartitions: orderPartitions,
        resolveDiskRingIds: resolveDiskRingIds,
        stalePartitions: stalePartitions,
        parseLabelCache: parseLabelCache,
        serializeLabelCache: serializeLabelCache,
        mergeLabelCache: mergeLabelCache,
        isRemovableMount: isRemovableMount,
    };
}
