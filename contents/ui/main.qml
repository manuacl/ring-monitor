import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.ksysguard.sensors as Sensors

PlasmoidItem {
    id: root

    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    // ── Sensors ──────────────────────────────────────────────────────────
    Sensors.Sensor { id: cpuTotal;  sensorId: "cpu/all/usage" }
    Sensors.Sensor { id: ramSensor; sensorId: "memory/physical/usedPercent" }

    Sensors.Sensor { id: cpu0; sensorId: "cpu/cpu0/usage" }
    Sensors.Sensor { id: cpu1; sensorId: "cpu/cpu1/usage" }
    Sensors.Sensor { id: cpu2; sensorId: "cpu/cpu2/usage" }
    Sensors.Sensor { id: cpu3; sensorId: "cpu/cpu3/usage" }
    Sensors.Sensor { id: cpu4; sensorId: "cpu/cpu4/usage" }
    Sensors.Sensor { id: cpu5; sensorId: "cpu/cpu5/usage" }

    readonly property var coreValues: [
        cpu0.value || 0, cpu1.value || 0, cpu2.value || 0,
        cpu3.value || 0, cpu4.value || 0, cpu5.value || 0
    ]

    // ── Layout ───────────────────────────────────────────────────────────
    fullRepresentation: RowLayout {
        implicitWidth: 380
        implicitHeight: 180
        spacing: 12

        Ring {
            Layout.fillWidth: true
            Layout.fillHeight: true
            label: "CPU"
            value: cpuTotal.value || 0
            nestedValues: root.coreValues
        }

        Ring {
            Layout.fillWidth: true
            Layout.fillHeight: true
            label: "RAM"
            value: ramSensor.value || 0
        }
    }
}
