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
            verify(subOptions.cpuTempOptions);
            verify(subOptions.gpuTempOptions);
            verify(subOptions.diskIoSplitToggle);
            verify(subOptions.sensorTempSettings);
            verify(subOptions.diskPartitionsPicker);
        }

        // The cpuTemp/gpuTemp rows stack the merge toggle above the
        // bounds editor (#164 section 5); both must instantiate against
        // a minimal controller.
        function test_temp_options_instantiate_against_controller() {
            const cpu = subOptions.cpuTempOptions.createObject(root);
            verify(cpu, "cpuTempOptions must instantiate with a minimal controller");
            verify(findChild(cpu, "minCSpinBox"), "cpuTempOptions must embed the bounds editor");
            cpu.destroy();
            const gpu = subOptions.gpuTempOptions.createObject(root);
            verify(gpu, "gpuTempOptions must instantiate with a minimal controller");
            verify(findChild(gpu, "maxCSpinBox"), "gpuTempOptions must embed the bounds editor");
            gpu.destroy();
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
