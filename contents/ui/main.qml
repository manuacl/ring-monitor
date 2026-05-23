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
    Sensors.Sensor { id: cpuTotal;   sensorId: "cpu/all/usage" }
    Sensors.Sensor { id: ramSensor;  sensorId: "memory/physical/usedPercent" }
    Sensors.Sensor { id: swapSensor; sensorId: "memory/swap/usedPercent" }
    Sensors.Sensor { id: gpuSensor;  sensorId: "gpu/all/usage" }
    Sensors.Sensor { id: diskSensor; sensorId: "disk/all/usedPercent" }

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

    // ── Enabled metrics (read from config, filtered to known order) ─────
    readonly property var metricOrder: ["cpu", "ram", "swap", "gpu", "disk"]
    readonly property var enabledList: {
        const csv = Plasmoid.configuration.enabledMetrics || ""
        const set = new Set(csv.split(",").filter(function(x) { return x }))
        return metricOrder.filter(function(id) { return set.has(id) })
    }

    function metricLabel(id) {
        return ({
            cpu: "CPU", ram: "RAM", swap: "SWAP", gpu: "GPU", disk: "DISK"
        })[id] || id.toUpperCase()
    }

    // ── Layout ───────────────────────────────────────────────────────────
    fullRepresentation: GridLayout {
        readonly property bool vertical: Plasmoid.configuration.orientation === "vertical"
        readonly property int count: Math.max(1, root.enabledList.length)

        columns: vertical ? 1 : count
        rowSpacing: 12
        columnSpacing: 12
        implicitWidth:  vertical ? 180 : 180 * count
        implicitHeight: vertical ? 180 * count : 180

        Repeater {
            model: root.enabledList

            delegate: Ring {
                required property string modelData

                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 80
                Layout.minimumHeight: 80

                label: root.metricLabel(modelData)
                value: modelData === "cpu"  ? (cpuTotal.value   || 0)
                     : modelData === "ram"  ? (ramSensor.value  || 0)
                     : modelData === "swap" ? (swapSensor.value || 0)
                     : modelData === "gpu"  ? (gpuSensor.value  || 0)
                     : modelData === "disk" ? (diskSensor.value || 0)
                     : 0
                nestedValues: (modelData === "cpu" && Plasmoid.configuration.showCpuCores)
                              ? root.coreValues : []
                textOpacity:  Plasmoid.configuration.textOpacity
                trackOpacity: Plasmoid.configuration.trackOpacity
                arcOpacity:   Plasmoid.configuration.arcOpacity
            }
        }
    }
}
