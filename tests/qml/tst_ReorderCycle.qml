import QtQuick
import QtTest
import "../../contents/ui/core" as Ui
import "../../contents/ui/core/ReorderLogic.js" as Logic

// Full integration test: simulate a user-driven drag inside DraggableList,
// run it through the same `onReordered` handler that configMetrics uses
// (apply Logic.applyMove → clear+repopulate ListModel), and verify the
// final order is what the user dragged towards.
//
// This is the regression guard for the wiring between DraggableList's
// `reordered` signal and the parent's ListModel mutation — the bit that
// the standalone DraggableList tests don't cover.

Item {
    id: root
    width: 400
    height: 400

    readonly property int rowH: 40
    readonly property int spacing: 4
    readonly property int step: rowH + spacing

    ListModel {
        id: orderModel
        ListElement {
            metricId: "cpu"
        }
        ListElement {
            metricId: "ram"
        }
        ListElement {
            metricId: "swap"
        }
        ListElement {
            metricId: "gpu"
        }
    }

    function currentOrder() {
        const out = [];
        for (let i = 0; i < orderModel.count; i++)
            out.push(orderModel.get(i).metricId);
        return out;
    }

    Ui.DraggableList {
        id: list
        anchors.fill: parent
        model: orderModel
        rowHeight: root.rowH
        rowSpacing: root.spacing
        rowContent: Component {
            Item {}
        }
        onReordered: function (from, to) {
            // Verbatim copy of the configMetrics handler.
            const next = Logic.applyMove(root.currentOrder(), from, to);
            orderModel.clear();
            for (let i = 0; i < next.length; i++) {
                orderModel.append({
                    metricId: next[i]
                });
            }
        }
    }

    TestCase {
        name: "ReorderCycle"
        when: windowShown

        function init() {
            // Reset to canonical order so tests don't bleed into each other.
            orderModel.clear();
            const seed = ["cpu", "ram", "swap", "gpu"];
            for (let i = 0; i < seed.length; i++)
                orderModel.append({
                    metricId: seed[i]
                });
            tryCompare(list, "count", 4);
            // Let the delegates (and their DropAreas) fully wire up after
            // the model reset. Without this the next drag's DropArea
            // entered events get dropped on the floor.
            wait(80);
        }

        function drag(srcIndex, tgtIndex) {
            const handleX = 10;
            const srcY = srcIndex * root.step + root.rowH / 2;
            const tgtY = tgtIndex * root.step + root.rowH / 2;
            const dir = tgtIndex > srcIndex ? 1 : -1;

            mousePress(list, handleX, srcY);
            mouseMove(list, handleX, srcY + dir * 12);
            wait(20);
            mouseMove(list, handleX, srcY + dir * 30);
            wait(20);
            mouseMove(list, handleX, tgtY);
            wait(20);
            tryCompare(list, "_dropTarget", tgtIndex);
            mouseRelease(list, handleX, tgtY);
        }

        // ── Cycle tests ────────────────────────────────────────────
        function test_drag_first_to_last_position() {
            drag(0, 3);
            compare(currentOrder(), ["ram", "swap", "gpu", "cpu"]);
        }
        function test_drag_last_to_first_position() {
            drag(3, 0);
            compare(currentOrder(), ["gpu", "cpu", "ram", "swap"]);
        }
        function test_drag_middle_one_up() {
            drag(2, 1);
            compare(currentOrder(), ["cpu", "swap", "ram", "gpu"]);
        }
        function test_drag_middle_one_down() {
            drag(1, 2);
            compare(currentOrder(), ["cpu", "swap", "ram", "gpu"]);
        }
    }
}
