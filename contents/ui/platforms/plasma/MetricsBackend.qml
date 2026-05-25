import QtQuick
import org.kde.ksysguard.sensors as Sensors
import "../../core/MetricsCatalog.js" as Catalog

// Platform adapter: wraps the KSysGuard sensor system used by the
// Plasma build. Exposes the metric values main.qml needs as a stable
// surface — the internal sensor instances + sensorMap are
// implementation details, not part of the public API.
//
// Public surface:
//   readonly property var coreValues  - per-core CPU usage (length = nCores)
//   function metricValue(id)          - latest value for one of the
//                                       Catalog metric ids (cpu/ram/swap/gpu/disk)
//
// A standalone build will ship a parallel MetricsBackend.qml backed by
// /proc reads (e.g. /proc/stat for CPU, /proc/meminfo for RAM) or by
// psutil via a PyQt6 process, exposing the same property surface.
//
// The MetricsCatalog.sensorIdFor() lookup stays in the shared core
// module — keeping metric-id → sensor-id mapping in one place so both
// platforms agree on the catalog.

Item {
    // ── Public surface ──────────────────────────────────────────────
    readonly property var coreValues: [cpu0.value || 0, cpu1.value || 0, cpu2.value || 0, cpu3.value || 0, cpu4.value || 0, cpu5.value || 0]

    function metricValue(id) {
        // Pure helper (tested in metrics-catalog.test.mjs).
        return Catalog.valueFromSensorMap(sensorMap, id);
    }

    // ── Internal — id → sensor instance lookup ──────────────────────
    readonly property var sensorMap: ({
            cpu: cpuTotal,
            ram: ramSensor,
            swap: swapSensor,
            gpu: gpuSensor,
            disk: diskSensor
        })

    // ── Internal — per-metric sensors ───────────────────────────────
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

    // ── Internal — per-core CPU sensors (6 cores on this rig — see CLAUDE.md) ──
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
}
