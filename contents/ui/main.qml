pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.ksysguard.sensors as Sensors
import "MetricsCatalog.js" as Catalog

PlasmoidItem {
    id: root

    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    // ── Sensors ──────────────────────────────────────────────────────────
    // The sensor IDs come from Catalog. Sensors.Sensor is a QML-only type so
    // the instances themselves must be declared here.
    Sensors.Sensor {
        id: cpuTotal
        sensorId: Catalog.sensorIdFor("cpu")
    }
    Sensors.Sensor {
        id: ramSensor
        sensorId: Catalog.sensorIdFor("ram")
    }
    Sensors.Sensor {
        id: swapSensor
        sensorId: Catalog.sensorIdFor("swap")
    }
    Sensors.Sensor {
        id: gpuSensor
        sensorId: Catalog.sensorIdFor("gpu")
    }
    Sensors.Sensor {
        id: diskSensor
        sensorId: Catalog.sensorIdFor("disk")
    }

    // Per-core CPU sensors (6 cores on this rig — see CLAUDE.md).
    Sensors.Sensor {
        id: cpu0
        sensorId: "cpu/cpu0/usage"
    }
    Sensors.Sensor {
        id: cpu1
        sensorId: "cpu/cpu1/usage"
    }
    Sensors.Sensor {
        id: cpu2
        sensorId: "cpu/cpu2/usage"
    }
    Sensors.Sensor {
        id: cpu3
        sensorId: "cpu/cpu3/usage"
    }
    Sensors.Sensor {
        id: cpu4
        sensorId: "cpu/cpu4/usage"
    }
    Sensors.Sensor {
        id: cpu5
        sensorId: "cpu/cpu5/usage"
    }

    readonly property var coreValues: [cpu0.value || 0, cpu1.value || 0, cpu2.value || 0, cpu3.value || 0, cpu4.value || 0, cpu5.value || 0]

    // ── id → sensor instance lookup (replaces a chained ternary) ────────
    readonly property var sensorMap: ({
            cpu: cpuTotal,
            ram: ramSensor,
            swap: swapSensor,
            gpu: gpuSensor,
            disk: diskSensor
        })

    function metricValue(id) {
        const s = sensorMap[id];
        return s ? (s.value || 0) : 0;
    }

    // ── Enabled metrics (read config + filter through Catalog) ──────────
    readonly property var enabledList: Catalog.filterByOrder(Catalog.parseCsv(Plasmoid.configuration.enabledMetrics), Catalog.parseCsv(Plasmoid.configuration.metricOrder))

    // ── Layout ───────────────────────────────────────────────────────────
    fullRepresentation: GridLayout {
        readonly property bool vertical: Plasmoid.configuration.orientation === "vertical"
        readonly property int count: Math.max(1, root.enabledList.length)

        columns: vertical ? 1 : count
        rowSpacing: 12
        columnSpacing: 12
        implicitWidth: vertical ? 180 : 180 * count
        implicitHeight: vertical ? 180 * count : 180

        Repeater {
            model: root.enabledList

            delegate: Ring {
                required property string modelData

                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 80
                Layout.minimumHeight: 80

                label: Catalog.labelFor(modelData)
                value: root.metricValue(modelData)
                nestedValues: modelData === "cpu" && Plasmoid.configuration.showCpuCores ? root.coreValues : []
                textOpacity: Plasmoid.configuration.textOpacity
                trackOpacity: Plasmoid.configuration.trackOpacity
                arcOpacity: Plasmoid.configuration.arcOpacity
            }
        }
    }
}
