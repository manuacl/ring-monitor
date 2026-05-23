// Pure logic for drag-and-drop reordering of a vertical list.
//
// This file is dual-loaded:
//   - QML imports it as a namespace: `import "ReorderLogic.js" as Logic`
//     Top-level `function` declarations become methods on the namespace.
//   - Node tests require it via the `module.exports` shim at the bottom.
//
// Keep this file dependency-free: no QML types, no DOM, no Qt globals.
//
// We intentionally don't use `.pragma library` because that's QML-only
// syntax and would break the Node test runner. The functions here are
// pure so per-import state isn't an issue.

function computeDropTarget(mouseY, rowStep, count) {
    if (count <= 0) return 0;
    if (rowStep <= 0) return 0;
    var idx = Math.floor(mouseY / rowStep);
    if (idx < 0) return 0;
    if (idx > count - 1) return count - 1;
    return idx;
}

function computeYShift(rowIndex, dragSource, dropTarget, step) {
    if (dragSource < 0 || dropTarget < 0) return 0;
    if (rowIndex === dragSource) return 0;
    if (dragSource === dropTarget) return 0;
    if (dragSource < dropTarget) {
        if (rowIndex > dragSource && rowIndex <= dropTarget) return -step;
        return 0;
    }
    if (rowIndex >= dropTarget && rowIndex < dragSource) return step;
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
