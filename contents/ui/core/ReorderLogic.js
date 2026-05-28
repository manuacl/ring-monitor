// SPDX-License-Identifier: GPL-3.0-or-later
// Pure logic for drag-and-drop reordering of a vertical list.
//
// This file is dual-loaded:
//   - QML imports it as a namespace: `import "ReorderLogic.js" as Logic`
//     Top-level `function` declarations become methods on the namespace.
//   - Node tests require it via the `module.exports` shim at the bottom.
//
// Keep this file dependency-free: no QML types, no DOM, no Qt globals.
// No `.pragma library` (QML-only, breaks Node).

function computeDropTarget(mouseY, rowStep, count) {
    if (count <= 0) return 0;
    if (rowStep <= 0) return 0;
    var idx = Math.floor(mouseY / rowStep);
    if (idx < 0) return 0;
    if (idx > count - 1) return count - 1;
    return idx;
}

// Visual shift to apply to row `rowIndex` while the user is dragging
// `dragSource` towards `dropTarget`. The fourth argument is the SOURCE
// row's vertical extent (height + spacing) — the space it vacates as it
// leaves to land on the target. Rows between source and target shift by
// that extent in the appropriate direction; everyone else stays put.
//
// For uniform-height lists `srcExtent` is just the constant step. For
// variable-height lists (e.g. when a row has an extraContent sub-row)
// the caller passes the source row's actual height.
function computeYShift(rowIndex, dragSource, dropTarget, srcExtent) {
    if (dragSource < 0 || dropTarget < 0) return 0;
    if (rowIndex === dragSource) return 0;
    if (dragSource === dropTarget) return 0;
    if (dragSource < dropTarget) {
        if (rowIndex > dragSource && rowIndex <= dropTarget) return -srcExtent;
        return 0;
    }
    if (rowIndex >= dropTarget && rowIndex < dragSource) return srcExtent;
    return 0;
}

function applyMove(arr, from, to) {
    var copy = arr.slice();
    var item = copy.splice(from, 1)[0];
    copy.splice(to, 0, item);
    return copy;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        computeDropTarget: computeDropTarget,
        computeYShift: computeYShift,
        applyMove: applyMove,
    };
}
