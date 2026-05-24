// TDD spec for the drag-and-drop reorder logic.
//
// Run:  node --test tests/
//
// The implementation lives in contents/ui/core/ReorderLogic.js. That file is
// designed to be importable BOTH from QML (as a namespace) AND from Node
// (via a CommonJS-style `module.exports` shim at the bottom).
//
// We use require() through createRequire because the source is .js (not
// .mjs) and uses module.exports.

import { createRequire } from 'node:module';
import { test } from 'node:test';
import assert from 'node:assert/strict';

const require = createRequire(import.meta.url);
const Logic = require('../contents/ui/core/ReorderLogic.js');

// ─────────────────────────────────────────────────────────────────────────
// computeDropTarget(mouseY, rowStep, count)
//   - mouseY: y position of the cursor relative to the ListView content top
//   - rowStep: height of one row + spacing between rows
//   - count: number of items in the list
//   Returns: the model index where the dragged item would land if released
//            now. Always clamped to [0, count-1].
// ─────────────────────────────────────────────────────────────────────────

test('computeDropTarget: cursor inside row 0 → 0', () => {
    assert.equal(Logic.computeDropTarget(0, 40, 5), 0);
    assert.equal(Logic.computeDropTarget(20, 40, 5), 0);
    assert.equal(Logic.computeDropTarget(39, 40, 5), 0);
});

test('computeDropTarget: cursor inside row 1 → 1', () => {
    assert.equal(Logic.computeDropTarget(40, 40, 5), 1);
    assert.equal(Logic.computeDropTarget(60, 40, 5), 1);
    assert.equal(Logic.computeDropTarget(79, 40, 5), 1);
});

test('computeDropTarget: cursor inside last row → count-1', () => {
    assert.equal(Logic.computeDropTarget(160, 40, 5), 4);
    assert.equal(Logic.computeDropTarget(199, 40, 5), 4);
});

test('computeDropTarget: cursor below last row clamps to count-1', () => {
    assert.equal(Logic.computeDropTarget(500, 40, 5), 4);
});

test('computeDropTarget: cursor above row 0 clamps to 0', () => {
    assert.equal(Logic.computeDropTarget(-50, 40, 5), 0);
});

test('computeDropTarget: count of 1 always returns 0', () => {
    assert.equal(Logic.computeDropTarget(0, 40, 1), 0);
    assert.equal(Logic.computeDropTarget(500, 40, 1), 0);
});

// ─────────────────────────────────────────────────────────────────────────
// computeYShift(rowIndex, dragSource, dropTarget, step)
//   The visual y-offset that should be applied to a row at `rowIndex` to
//   make room for the dragged item.
//   - The dragged row itself (rowIndex === dragSource) never shifts; its
//     visual position is handled separately (it floats under the cursor).
//   - When dragSource === dropTarget (e.g. cursor over origin), NO rows
//     shift. This is what "returning to origin" looks like.
//   - When dragging DOWN (src < tgt), rows in (src, tgt] shift UP by step.
//   - When dragging UP (src > tgt), rows in [tgt, src) shift DOWN by step.
//   - When inactive (src < 0 or tgt < 0), no shifts.
// ─────────────────────────────────────────────────────────────────────────

test('computeYShift: inactive (no drag) → 0 for all', () => {
    for (let i = 0; i < 5; i++) {
        assert.equal(Logic.computeYShift(i, -1, -1, 40), 0);
        assert.equal(Logic.computeYShift(i, -1, 2, 40), 0);
        assert.equal(Logic.computeYShift(i, 2, -1, 40), 0);
    }
});

test('computeYShift: dragged row itself never shifts', () => {
    // src=2, tgt=0 — drag up
    assert.equal(Logic.computeYShift(2, 2, 0, 40), 0);
    // src=2, tgt=4 — drag down
    assert.equal(Logic.computeYShift(2, 2, 4, 40), 0);
    // src=2, tgt=2 — hovering origin
    assert.equal(Logic.computeYShift(2, 2, 2, 40), 0);
});

test('computeYShift: drag DOWN — intermediate rows shift up', () => {
    // List of 5 rows, drag row 0 down to position 3.
    //   Row 0 (dragged): 0
    //   Rows 1, 2, 3: -40 (shift up to fill the gap left by 0)
    //   Row 4: 0
    assert.equal(Logic.computeYShift(0, 0, 3, 40), 0);
    assert.equal(Logic.computeYShift(1, 0, 3, 40), -40);
    assert.equal(Logic.computeYShift(2, 0, 3, 40), -40);
    assert.equal(Logic.computeYShift(3, 0, 3, 40), -40);
    assert.equal(Logic.computeYShift(4, 0, 3, 40), 0);
});

test('computeYShift: drag UP — intermediate rows shift down', () => {
    // Drag row 3 up to position 1.
    //   Rows 0: 0
    //   Rows 1, 2: +40 (shift down to make room above 3)
    //   Row 3 (dragged): 0
    //   Row 4: 0
    assert.equal(Logic.computeYShift(0, 3, 1, 40), 0);
    assert.equal(Logic.computeYShift(1, 3, 1, 40), 40);
    assert.equal(Logic.computeYShift(2, 3, 1, 40), 40);
    assert.equal(Logic.computeYShift(3, 3, 1, 40), 0);
    assert.equal(Logic.computeYShift(4, 3, 1, 40), 0);
});

test('computeYShift: target equals source (cursor over origin) → no shifts', () => {
    // KEY scenario from the user bug report:
    //   "Je drag CPU [at idx 3] vers position 0, les items s'écartent.
    //    Je reviens (sans drop) à la position initiale [3], les items
    //    doivent revenir à leur place (= shift = 0 partout)."
    for (let i = 0; i < 5; i++) {
        assert.equal(Logic.computeYShift(i, 3, 3, 40), 0);
    }
});

test('computeYShift: target adjacent to source (no gap to make)', () => {
    // src=2, tgt=3: row 3 shifts up by 40 to fill the gap.
    assert.equal(Logic.computeYShift(3, 2, 3, 40), -40);
    // src=2, tgt=1: row 1 shifts down by 40.
    assert.equal(Logic.computeYShift(1, 2, 1, 40), 40);
});

// ─────────────────────────────────────────────────────────────────────────
// applyMove(arr, from, to)
//   Returns a NEW array with `arr[from]` moved to index `to`.
//   This is what gets committed on drop.
// ─────────────────────────────────────────────────────────────────────────

test('applyMove: move first to last', () => {
    assert.deepEqual(Logic.applyMove(['a', 'b', 'c', 'd'], 0, 3),
                     ['b', 'c', 'd', 'a']);
});

test('applyMove: move last to first', () => {
    assert.deepEqual(Logic.applyMove(['a', 'b', 'c', 'd'], 3, 0),
                     ['d', 'a', 'b', 'c']);
});

test('applyMove: from === to is a no-op (returns equivalent array)', () => {
    assert.deepEqual(Logic.applyMove(['a', 'b', 'c'], 1, 1),
                     ['a', 'b', 'c']);
});

test('applyMove: does not mutate the input', () => {
    const input = ['a', 'b', 'c'];
    Logic.applyMove(input, 0, 2);
    assert.deepEqual(input, ['a', 'b', 'c']);
});

test('applyMove: move into middle', () => {
    assert.deepEqual(Logic.applyMove(['cpu', 'ram', 'swap', 'gpu', 'disk'], 0, 2),
                     ['ram', 'swap', 'cpu', 'gpu', 'disk']);
    assert.deepEqual(Logic.applyMove(['cpu', 'ram', 'swap', 'gpu', 'disk'], 3, 1),
                     ['cpu', 'gpu', 'ram', 'swap', 'disk']);
});

// ─────────────────────────────────────────────────────────────────────────
// Integration scenarios — full sequences that mirror the user's bug reports
// ─────────────────────────────────────────────────────────────────────────

test('SCENARIO: drag row 3 up to row 0 then back to origin — final shifts all 0', () => {
    const step = 40;
    const src = 3;

    // User is at tgt=0 (top): rows 0,1,2 shifted down.
    assert.equal(Logic.computeYShift(0, src, 0, step), step);
    assert.equal(Logic.computeYShift(1, src, 0, step), step);
    assert.equal(Logic.computeYShift(2, src, 0, step), step);
    assert.equal(Logic.computeYShift(3, src, 0, step), 0);

    // User drags back to tgt=3 (origin): all shifts must be 0.
    for (let i = 0; i < 5; i++) {
        assert.equal(Logic.computeYShift(i, src, src, step), 0,
                     `row ${i} should not be shifted when at origin`);
    }
});

test('SCENARIO: consecutive drags — second drag is independent of first', () => {
    // First drag: row 3 → 0. Final commit reorders the array.
    let arr = ['a', 'b', 'c', 'd', 'e'];
    arr = Logic.applyMove(arr, 3, 0);
    assert.deepEqual(arr, ['d', 'a', 'b', 'c', 'e']);

    // Second drag should start fresh — dropTarget for cursor over row 2
    // should be 2, not the previously committed value.
    // (This is what the user's bug report says fails: "tous les drags
    // suivants ne peuvent être droppés que à la position du précédent")
    const step = 40;
    assert.equal(Logic.computeDropTarget(2 * step, step, arr.length), 2);
    assert.equal(Logic.computeDropTarget(4 * step, step, arr.length), 4);
});
