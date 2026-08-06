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

    // The cpuTemp/gpuTemp rows stack the merge toggle above the custom
    // ring-bounds editor (#164 section 5). The bounds editor stays
    // visible regardless of the merge toggle: the range applies to the
    // dedicated temp ring AND to the merged half-arc.
    readonly property Component cpuTempOptions: Component {
        Column {
            QQC2.CheckBox {
                text: qsTr("Merge into the CPU ring (right half)")
                checked: root.controller.mergeCpuTemp

                onClicked: {
                    root.controller.mergeCpuTemp = checked;
                    if (checked && !root.controller.isEnabled("cpu"))
                        root.controller.setEnabled("cpu", true);
                }
            }

            TempRangeSettings {
                minC: root.controller.cpuTempMinC
                maxC: root.controller.cpuTempMaxC
                tempUnit: root.controller.tempUnit

                onMinCEdited: function (value) {
                    root.controller.cpuTempMinC = value;
                }

                onMaxCEdited: function (value) {
                    root.controller.cpuTempMaxC = value;
                }
            }
        }
    }

    readonly property Component gpuTempOptions: Component {
        Column {
            QQC2.CheckBox {
                text: qsTr("Merge into the GPU ring (right half)")
                checked: root.controller.mergeGpuTemp

                onClicked: {
                    root.controller.mergeGpuTemp = checked;
                    if (checked && !root.controller.isEnabled("gpu"))
                        root.controller.setEnabled("gpu", true);
                }
            }

            TempRangeSettings {
                minC: root.controller.gpuTempMinC
                maxC: root.controller.gpuTempMaxC
                tempUnit: root.controller.tempUnit

                onMinCEdited: function (value) {
                    root.controller.gpuTempMinC = value;
                }

                onMaxCEdited: function (value) {
                    root.controller.gpuTempMaxC = value;
                }
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
            availableSensors: root.controller.tempSensors
            sensorResolved: root.controller.sensorTempResolved
            sensorLiveValue: root.controller.sensorTempLive

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
