import QtQuick
import QtQuick.Layouts
import "MetricsCatalog.js" as Catalog
import "ColorThemes.js" as ColorThemes

// Body of the plasmoid's fullRepresentation. Renders the active rings
// in a horizontal or vertical strip based on configStore.orientation.
//
// Decoupled from Plasma: receives the three platform adapters (theme,
// configStore, metrics) as object properties so the parent
// PlasmoidItem (or a future standalone Window) wires them in. This
// file imports zero org.kde.* modules — that's the seam.
//
// The 3 adapters are typed `var` (not a specific QML type) because the
// standalone build will swap them for differently-implemented Items
// that expose the same property surface. See
// docs/plasma-isolation/plan.md.

GridLayout {
    id: content

    // ── Adapter inputs (injected by the parent) ──────────────────────
    property var theme
    property var configStore
    property var metrics

    // ── Derived ──────────────────────────────────────────────────────
    readonly property var enabledList: Catalog.filterByOrder(Catalog.parseCsv(content.configStore.enabledMetrics), Catalog.parseCsv(content.configStore.metricOrder))
    readonly property bool vertical: content.configStore.orientation === "vertical"
    readonly property int count: Math.max(1, content.enabledList.length)

    columns: vertical ? 1 : count
    rowSpacing: 12
    columnSpacing: 12
    implicitWidth: vertical ? 180 : 180 * count
    implicitHeight: vertical ? 180 * count : 180

    Repeater {
        model: content.enabledList

        delegate: Ring {
            required property string modelData

            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 80
            Layout.minimumHeight: 80

            label: Catalog.labelFor(modelData)
            value: content.metrics.metricValue(modelData)
            nestedValues: modelData === "cpu" && content.configStore.showCpuCores ? content.metrics.coreValues : []
            ringColor: ColorThemes.resolveColor(content.configStore.colorTheme, ColorThemes.effectiveIsDark(content.configStore.colorMode, content.theme.isDarkMode), content.theme.highlightColor, content.configStore.customColorLight, content.configStore.customColorDark)
            textColor: content.theme.textColor
            textOpacity: content.configStore.textOpacity
            trackOpacity: content.configStore.trackOpacity
            arcOpacity: content.configStore.arcOpacity
        }
    }
}
