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
        property string sensorTempId: ""
        property string sensorTempLabel: "SENSOR"
        property int sensorTempMinC: 20
        property int sensorTempMaxC: 60
        property int cpuTempMinC: 30
        property int cpuTempMaxC: 90
        property int gpuTempMinC: 30
        property int gpuTempMaxC: 90
        property string tempUnit: "auto"
        property var tempSensors: []
        property bool sensorTempResolved: false
        property real sensorTempLive: NaN

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

    // A parent carrying a `rowModel` property simulates the DraggableList
    // Loader context, so currentMetricId resolves like a real row.
    Item {
        id: sensorTempRowContext
        property var rowModel: ({
                "metricId": "sensorTemp"
            })

        Ui.MetricsRowDelegate {
            id: sensorTempDelegate
            controller: fakeController
            subOptions: subOptions
        }
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

        function test_sensorTemp_row_gets_its_settings_editor() {
            compare(sensorTempDelegate.currentMetricId, "sensorTemp");
            verify(sensorTempDelegate.extraContent, "sensorTemp row → settings editor");
        }
    }
}
