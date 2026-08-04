import QtQuick
import QtTest
import "../../contents/ui/core" as Ui

// Tests for MetricSubOptions.qml — the registry of per-metric sub-option
// Components. Smoke-level: the Components must exist and instantiate
// against a minimal controller (the real wiring is exercised through
// tst_MetricsBody / tst_SensorTempSettings).

Item {
    id: root
    width: 400
    height: 300

    QtObject {
        id: fakeController
        property bool showCpuCores: false
        property bool mergeCpuTemp: false
        property bool mergeGpuTemp: false
        property bool splitDiskIo: false
        property string sensorTempId: ""
        property string sensorTempLabel: "SENSOR"
        property int sensorTempMinC: 20
        property int sensorTempMaxC: 60
        property string tempUnit: "auto"

        function isEnabled(id) {
            return false;
        }
        function setEnabled(id, on) {}
    }

    Ui.MetricSubOptions {
        id: subOptions
        controller: fakeController
    }

    TestCase {
        name: "MetricSubOptions"
        when: windowShown

        function test_all_sub_option_components_exist() {
            verify(subOptions.cpuCoresToggle);
            verify(subOptions.cpuTempMergeToggle);
            verify(subOptions.gpuTempMergeToggle);
            verify(subOptions.diskIoSplitToggle);
            verify(subOptions.sensorTempSettings);
            verify(subOptions.diskPartitionsPicker);
        }

        function test_sensor_temp_settings_instantiates_against_controller() {
            const obj = subOptions.sensorTempSettings.createObject(root);
            verify(obj, "sensorTempSettings must instantiate with a minimal controller");
            compare(obj.sensorId, "");
            compare(obj.sensorLabel, "SENSOR");
            compare(obj.minC, 20);
            compare(obj.maxC, 60);
            obj.destroy();
        }
    }
}
