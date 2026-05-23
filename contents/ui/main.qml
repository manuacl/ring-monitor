import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.ksysguard.sensors as Sensors

PlasmoidItem {
    id: root

    preferredRepresentation: fullRepresentation

    Sensors.Sensor {
        id: cpuSensor
        sensorId: "cpu/all/usage"
    }

    Sensors.Sensor {
        id: ramSensor
        sensorId: "memory/physical/usedPercent"
    }

    fullRepresentation: RowLayout {
        implicitWidth: 380
        implicitHeight: 180
        spacing: 12

        Ring {
            Layout.fillWidth: true
            Layout.fillHeight: true
            label: "CPU"
            value: cpuSensor.value || 0
        }

        Ring {
            Layout.fillWidth: true
            Layout.fillHeight: true
            label: "RAM"
            value: ramSensor.value || 0
        }
    }
}
