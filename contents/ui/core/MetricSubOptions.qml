import QtQuick
import QtQuick.Controls as QQC2

QtObject {
    id: root

    required property var controller

    readonly property Component cpuCoresToggle: Component {
        QQC2.CheckBox {
            text: qsTr("Show CPU cores as concentric rings")
            checked: root.controller.showCpuCores
            onClicked: root.controller.showCpuCores = checked
        }
    }

    readonly property Component cpuTempMergeToggle: Component {
        QQC2.CheckBox {
            text: qsTr("Merge into the CPU ring (right half)")
            checked: root.controller.mergeCpuTemp

            onClicked: {
                root.controller.mergeCpuTemp = checked;
                if (checked && !root.controller.isEnabled("cpu"))
                    root.controller.setEnabled("cpu", true);
            }
        }
    }

    readonly property Component gpuTempMergeToggle: Component {
        QQC2.CheckBox {
            text: qsTr("Merge into the GPU ring (right half)")
            checked: root.controller.mergeGpuTemp

            onClicked: {
                root.controller.mergeGpuTemp = checked;
                if (checked && !root.controller.isEnabled("gpu"))
                    root.controller.setEnabled("gpu", true);
            }
        }
    }

    readonly property Component diskIoSplitToggle: Component {
        QQC2.CheckBox {
            text: qsTr("Split read / write (left / right)")
            checked: root.controller.splitDiskIo
            onClicked: root.controller.splitDiskIo = checked
        }
    }

    readonly property Component sensorTempSettings: Component {
        SensorTempSettings {
            sensorId: root.controller.sensorTempId
            sensorLabel: root.controller.sensorTempLabel
            minC: root.controller.sensorTempMinC
            maxC: root.controller.sensorTempMaxC
            tempUnit: root.controller.tempUnit

            onSensorIdEdited: function (value) {
                root.controller.sensorTempId = value;
            }

            onSensorLabelEdited: function (value) {
                root.controller.sensorTempLabel = value;
            }

            onMinCEdited: function (value) {
                root.controller.sensorTempMinC = value;
            }

            onMaxCEdited: function (value) {
                root.controller.sensorTempMaxC = value;
            }
        }
    }

    readonly property Component diskPartitionsPicker: Component {
        DiskPartitionPicker {
            controller: root.controller
        }
    }
}
