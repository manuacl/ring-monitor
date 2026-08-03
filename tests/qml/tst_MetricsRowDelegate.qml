import QtQuick
import QtTest
import "../../contents/ui/core" as Ui

// Tests for MetricsRowDelegate.qml — the DraggableList row delegate.
// Outside a Loader there is no parent.rowModel, so currentMetricId is
// "" and the delegate must stay inert against a minimal controller
// (the per-row wiring is exercised through tst_MetricsBody).

Item {
    id: root
    width: 600
    height: 100

    QtObject {
        id: fakeController
        property var metricDescriptions: ({})
        property var theme: null

        function isEnabled(id) {
            return false;
        }
        function isMetricAvailable(id) {
            return true;
        }
        function setEnabled(id, on) {}
    }

    Ui.MetricSubOptions {
        id: subOptions
        controller: fakeController
    }

    Ui.MetricsRowDelegate {
        id: delegate
        anchors.fill: parent
        controller: fakeController
        subOptions: subOptions
    }

    TestCase {
        name: "MetricsRowDelegate"
        when: windowShown

        function test_inert_without_a_loader_row_context() {
            compare(delegate.currentMetricId, "");
            compare(delegate.metricId, "");
            // No matching sub-option for an empty id → no extraContent.
            verify(!delegate.extraContent);
        }
    }
}
