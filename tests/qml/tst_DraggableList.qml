import QtQuick
import QtQuick.Controls
import QtTest
import "../../contents/ui" as Ui

// QML tests for DraggableList — covers two failure classes:
//
//   1. Row data forwarding (Loader → rowContent). The bug history:
//      relying on QML's implicit context-property propagation through
//      Loader gave "empty labels". The fix is explicit Loader
//      properties (`rowModel` / `rowIndex`) read via `parent.X`.
//
//   2. Drag mechanic (mouse → reorder). The bug history: a manual
//      mapToItem / _draggedY implementation placed the dragged row at
//      a random spot. The fix is Qt's native MouseArea.drag.target +
//      DropArea.onEntered.
//
// Run with:  qmltestrunner-qt6 -input tests/qml

Item {
    id: root
    width: 400
    height: 400

    // ── Test fixtures ─────────────────────────────────────────────────
    property var capturedIds: []
    property var capturedIndices: []

    ListModel {
        id: testModel
        ListElement {
            metricId: "alpha"
        }
        ListElement {
            metricId: "beta"
        }
        ListElement {
            metricId: "gamma"
        }
    }

    // Track the geometry the tests rely on. rowHeight × count + spacing
    // gives the step we move the cursor by.
    readonly property int rowH: 40
    readonly property int spacing: 4
    readonly property int step: rowH + spacing

    Ui.DraggableList {
        id: list
        anchors.fill: parent
        model: testModel
        rowHeight: root.rowH
        rowSpacing: root.spacing
        rowContent: Component {
            Item {
                Component.onCompleted: {
                    root.capturedIds.push(parent && parent.rowModel ? parent.rowModel.metricId : "(null)");
                    root.capturedIndices.push(parent && parent.rowIndex !== undefined ? parent.rowIndex : -1);
                }
            }
        }
    }

    SignalSpy {
        id: reorderedSpy
        target: list
        signalName: "reordered"
    }

    TestCase {
        name: "DraggableListForwarding"
        when: windowShown

        // ── Loader → rowContent data forwarding ───────────────────────
        function test_rowContent_receives_metricId_via_parent_rowModel() {
            wait(100);
            verify(root.capturedIds.length >= 3, "expected at least 3 delegates created");
            compare(root.capturedIds[0], "alpha");
            compare(root.capturedIds[1], "beta");
            compare(root.capturedIds[2], "gamma");
        }
        function test_rowContent_receives_index_via_parent_rowIndex() {
            wait(100);
            verify(root.capturedIndices.length >= 3);
            compare(root.capturedIndices[0], 0);
            compare(root.capturedIndices[1], 1);
            compare(root.capturedIndices[2], 2);
        }
    }

    TestCase {
        name: "DraggableListDrag"
        when: windowShown

        function init() {
            reorderedSpy.clear();
            // Make sure list is laid out.
            wait(100);
        }

        // Press a row's handle (left strip) at its vertical centre, then
        // walk the cursor down to another row, then release. Asserts
        // that `reordered(src, tgt)` fires with the model indices.

        function test_drag_row0_down_to_row2_emits_reordered_0_2() {
            tryCompare(list, "count", 3);
            const handleX = 10;
            const srcY = 0 * step + root.rowH / 2;
            const tgtY = 2 * step + root.rowH / 2;

            mousePress(list, handleX, srcY);
            verify(list._dragSource === 0, "_dragSource after press should be 0, got " + list._dragSource);
            mouseMove(list, handleX, srcY + 12);
            wait(20);
            mouseMove(list, handleX, srcY + 30);
            wait(20);
            mouseMove(list, handleX, tgtY);
            wait(20);
            tryCompare(list, "_dropTarget", 2);
            mouseRelease(list, handleX, tgtY);

            compare(reorderedSpy.count, 1);
            compare(reorderedSpy.signalArguments[0][0], 0, "from index");
            compare(reorderedSpy.signalArguments[0][1], 2, "to index");
        }

        function test_drag_row2_up_to_row0_emits_reordered_2_0() {
            tryCompare(list, "count", 3);
            const handleX = 10;
            const srcY = 2 * step + root.rowH / 2;
            const tgtY = 0 * step + root.rowH / 2;

            mousePress(list, handleX, srcY);
            mouseMove(list, handleX, srcY - 12);
            wait(20);
            mouseMove(list, handleX, srcY - 30);
            wait(20);
            mouseMove(list, handleX, tgtY);
            wait(20);
            tryCompare(list, "_dropTarget", 0);
            mouseRelease(list, handleX, tgtY);

            compare(reorderedSpy.count, 1);
            compare(reorderedSpy.signalArguments[0][0], 2);
            compare(reorderedSpy.signalArguments[0][1], 0);
        }

        function test_drag_to_same_row_does_not_emit() {
            tryCompare(list, "count", 3);
            // Press but release without moving past the drag threshold.
            const handleX = 10;
            const srcY = 1 * step + root.rowH / 2;

            mousePress(list, handleX, srcY);
            mouseMove(list, handleX, srcY + 2);
            mouseRelease(list, handleX, srcY + 2);

            compare(reorderedSpy.count, 0, "no-op drag must not emit");
        }

        function test_drag_to_adjacent_row1_emits_reordered_0_1() {
            tryCompare(list, "count", 3);
            const handleX = 10;
            const srcY = 0 * step + root.rowH / 2;
            const tgtY = 1 * step + root.rowH / 2;

            mousePress(list, handleX, srcY);
            mouseMove(list, handleX, srcY + 12);
            wait(20);
            mouseMove(list, handleX, tgtY);
            wait(20);
            tryCompare(list, "_dropTarget", 1);
            mouseRelease(list, handleX, tgtY);

            compare(reorderedSpy.count, 1);
            compare(reorderedSpy.signalArguments[0][0], 0);
            compare(reorderedSpy.signalArguments[0][1], 1);
        }
    }
}
