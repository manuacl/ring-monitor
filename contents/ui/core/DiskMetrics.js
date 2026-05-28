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
//   selectPartitions(availableIds, csvIds)
//                                       - intersection of a persisted CSV
//                                         selection with the partitions the
//                                         backend actually discovered,
//                                         preserving discovery order. Mirrors
//                                         MetricsCatalog.filterByOrder but
//                                         keyed the other way (available is
//                                         the order, csv is the membership).

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

function selectPartitions(availableIds, csvIds) {
    if (!availableIds || availableIds.length === 0)
        return [];
    var wanted = {};
    for (var i = 0; i < (csvIds ? csvIds.length : 0); i++)
        wanted[csvIds[i]] = true;
    var out = [];
    for (var j = 0; j < availableIds.length; j++) {
        if (wanted[availableIds[j]])
            out.push(availableIds[j]);
    }
    return out;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        averagePercent: averagePercent,
        selectPartitions: selectPartitions,
        sortByLabel: sortByLabel,
        orderPartitions: orderPartitions,
    };
}
