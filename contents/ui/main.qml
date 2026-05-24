import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import "platform" as Platform
import "MetricsCatalog.js" as Catalog

PlasmoidItem {
    id: root

    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    // ── Platform adapters ────────────────────────────────────────────────
    // Theme re-exports Kirigami tokens. ConfigStore re-exports
    // Plasmoid.configuration. MetricsBackend wraps the KSysGuard sensor
    // instances. main.qml never touches org.kde.* APIs directly anymore.
    // See docs/plasma-isolation/plan.md for the broader rationale.
    Platform.Theme {
        id: theme
    }

    Platform.ConfigStore {
        id: configStore
    }

    Platform.MetricsBackend {
        id: metrics
    }

    // ── Enabled metrics (read config + filter through Catalog) ──────────
    readonly property var enabledList: Catalog.filterByOrder(Catalog.parseCsv(configStore.enabledMetrics), Catalog.parseCsv(configStore.metricOrder))

    // ── Layout ───────────────────────────────────────────────────────────
    fullRepresentation: GridLayout {
        readonly property bool vertical: configStore.orientation === "vertical"
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
                value: metrics.metricValue(modelData)
                nestedValues: modelData === "cpu" && configStore.showCpuCores ? metrics.coreValues : []
                ringColor: theme.highlightColor
                textColor: theme.textColor
                textOpacity: configStore.textOpacity
                trackOpacity: configStore.trackOpacity
                arcOpacity: configStore.arcOpacity
            }
        }
    }
}
