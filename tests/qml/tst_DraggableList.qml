import QtQuick
import QtQuick.Controls
import QtTest
import "../../contents/ui" as Ui

// QML test for DraggableList — covers the data forwarding mechanism that
// keeps causing label regressions.
//
// The bug class: rowContent is a Component loaded via Loader, and we used
// to rely on QML's context-property propagation for `model.X` access. That
// turned out to be flaky across Qt versions / KCM containers. The fix is
// to forward the row data via Loader-owned properties (`rowModel`,
// `rowIndex`) and have the rowContent read them via `parent.rowModel`.
//
// Run with:  qmltestrunner-qt6 -input tests/qml

Item {
    id: root
    width: 400
    height: 200

    // Capture what the rowContent sees, for assertions below.
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

    Ui.DraggableList {
        id: list
        model: testModel
        rowHeight: 30
        showHandle: false
        anchors.fill: parent
        rowContent: Component {
            Item {
                Component.onCompleted: {
                    // Read what DraggableList's Loader forwarded onto our
                    // QML parent (the Loader itself).
                    root.capturedIds.push(parent && parent.rowModel ? parent.rowModel.metricId : "(null)");
                    root.capturedIndices.push(parent && parent.rowIndex !== undefined ? parent.rowIndex : -1);
                }
            }
        }
    }

    TestCase {
        name: "DraggableListForwarding"
        when: windowShown

        function test_rowContent_receives_metricId_via_parent_rowModel() {
            // Let ListView instantiate delegates.
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
}
