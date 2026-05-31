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
//   filterToMounted(partitions, mountedIds)
//                                       - keep only the partitions whose id is in
//                                         the live mounted set; passthrough when
//                                         mountedIds is empty/absent (no live data
//                                         yet). Gates the Plasma config picker so a
//                                         frozen-but-unmounted partition drops out.
//   stalePartitions(enabledCsv, orderCsv, discovered, labelCacheJson)
//                                       - configured ids no longer present
//                                         (unplugged), each {id, label}.
//   parseUuidMap / serializeUuidMap / pruneMap
//                                       - generic tolerant UUID→string JSON map
//                                         primitives, shared by the label cache
//                                         AND the per-partition color map below.
//   mergeLabelCache                     - the UUID→label cache backing the
//                                         friendly name on stale rows.
//   colorFor / withColor / withoutColor / resolveRingColors
//                                       - the per-partition disk ring color map
//                                         (UUID→#rrggbb), issue #67. A partition
//                                         with no entry inherits the shared ring
//                                         color (resolveRingColors' fallback).
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
// from the kernel mount table). When supplied (non-empty), a MANUAL id absent
// from it is dropped: that is the #58 self-heal — a configured partition that
// has been unmounted (a removable unplugged) loses its ring whether it was
// hand-checked or auto-checked, while a fixed disk (always mounted) is
// unaffected. ksysguard's own partition list can't drive this because it FREEZES
// on unmount (still lists the gone UUID) — only the live mount table reflects
// reality. An empty/absent mountedIds means "no live mount data" (a real system
// always has a root mount,
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

// Keep only the discovered partitions that are currently mounted, by id. The
// Plasma config picker feeds its partition list from ksysguard's
// SensorTreeModel, which FREEZES on unmount (#58) and keeps listing a
// just-unplugged filesystem — so without this gate the picker offers a
// dead partition as a live, selectable checkbox. Intersecting with the live
// kernel mount set (findmnt via MountInfo) drops it; and because the picker
// passes the SAME filtered list to stalePartitions(), a still-configured but
// unmounted partition then surfaces as a greyed "no longer connected" row
// instead. mountedIds empty/absent means "no live mount data yet" (the poll
// hasn't returned) → passthrough, so the picker isn't emptied during the
// warm-up window — same convention as resolveDiskRingIds' mount gate. Returns
// a new array; does not mutate the input.
function filterToMounted(partitions, mountedIds) {
    partitions = partitions || [];
    if (!mountedIds || mountedIds.length === 0)
        return partitions.slice();
    var mounted = {};
    for (var i = 0; i < mountedIds.length; i++)
        mounted[mountedIds[i]] = true;
    return partitions.filter(function (p) {
        return p && mounted[p.id];
    });
}

// Is partition `id` currently shown as a ring, from the disk picker's point of
// view (drives the checkbox `checked` state so the box reflects ring
// visibility)? The picker only lists currently-mounted partitions, so:
//   - a removable (id in removableIds) is shown UNLESS opted out (auto-show);
//   - a fixed disk is shown iff it is manually enabled.
// Mirrors resolveDiskRingIds' membership for a mounted partition, minus the
// maxCount cap / default fallback (those are whole-set display concerns, not a
// per-partition truth). The checkbox toggle is the inverse: toggling a
// removable writes the opt-out list, a fixed disk writes the manual selection.
function isPartitionShown(id, removableIds, enabledIds, optOutIds) {
    if ((removableIds || []).indexOf(id) !== -1)
        return (optOutIds || []).indexOf(id) === -1;
    return (enabledIds || []).indexOf(id) !== -1;
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
    var cache = parseUuidMap(labelCacheJson);
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

// Parse a persisted UUID→string JSON map (label cache OR color map). Tolerates
// empty / malformed JSON (a hand-edited config or a partial write) by returning
// {} rather than throwing.
function parseUuidMap(json) {
    if (!json)
        return {};
    try {
        var obj = JSON.parse(json);
        return (obj && typeof obj === "object" && !Array.isArray(obj)) ? obj : {};
    } catch (e) {
        return {};
    }
}

// Serialize with sorted keys so an unchanged map always produces the SAME
// string — assigning it back to the bridged property is then a no-op and
// doesn't trigger a spurious config write on every discovery pass.
function serializeUuidMap(obj) {
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
    var prev = parseUuidMap(prevJson);
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
    return serializeUuidMap(out);
}

// Drop every entry whose id is not in keepIds, returning the re-serialized map.
// Bounds the per-partition color map to the referenced partitions (enabled ∪
// order) so a custom color can't outlive its partition — same "can't grow
// without bound" guarantee mergeLabelCache gives the label cache (issue #67).
function pruneMap(json, keepIds) {
    var map = parseUuidMap(json);
    var keep = {};
    var ids = keepIds || [];
    for (var i = 0; i < ids.length; i++)
        keep[ids[i]] = true;
    var out = {};
    var keys = Object.keys(map);
    for (var j = 0; j < keys.length; j++) {
        if (keep[keys[j]])
            out[keys[j]] = map[keys[j]];
    }
    return serializeUuidMap(out);
}

// ── Per-partition disk ring color map (UUID→#rrggbb), issue #67 ──────────────
// Each selected filesystem can carry its own ring color; a partition with no
// entry inherits the shared ring color. Built on the parseUuidMap /
// serializeUuidMap primitives above (no separate module — the dual-load
// convention forbids a .js importing a sibling .js, so the color map lives here
// beside the label cache it shares its plumbing with).

// The stored color for `id`, or "" when none is set (caller falls back to the
// shared ring color). Guards against a non-string value from a hand-edited config.
function colorFor(json, id) {
    var c = parseUuidMap(json)[id];
    return (typeof c === "string" && c.length > 0) ? c : "";
}

function withColor(json, id, color) {
    var map = parseUuidMap(json);
    map[id] = String(color);
    return serializeUuidMap(map);
}

function withoutColor(json, id) {
    var map = parseUuidMap(json);
    if (Object.prototype.hasOwnProperty.call(map, id))
        delete map[id];
    return serializeUuidMap(map);
}

// One color per id, aligned to the `ids` array (the rendered disk-ring set,
// outermost first): the stored override when present, else `fallback` (the
// shared ring color resolved by the caller). Drives Ring.equalColors.
function resolveRingColors(ids, json, fallback) {
    ids = ids || [];
    var map = parseUuidMap(json);
    var out = [];
    for (var i = 0; i < ids.length; i++) {
        var c = map[ids[i]];
        out.push((typeof c === "string" && c.length > 0) ? c : fallback);
    }
    return out;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        averagePercent: averagePercent,
        sortByLabel: sortByLabel,
        orderPartitions: orderPartitions,
        resolveDiskRingIds: resolveDiskRingIds,
        filterToMounted: filterToMounted,
        isPartitionShown: isPartitionShown,
        stalePartitions: stalePartitions,
        parseUuidMap: parseUuidMap,
        serializeUuidMap: serializeUuidMap,
        pruneMap: pruneMap,
        mergeLabelCache: mergeLabelCache,
        colorFor: colorFor,
        withColor: withColor,
        withoutColor: withoutColor,
        resolveRingColors: resolveRingColors,
        isRemovableMount: isRemovableMount,
    };
}
