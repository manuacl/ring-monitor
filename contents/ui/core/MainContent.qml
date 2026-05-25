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
    //
    // The full enabled list = (CSV ∩ ordered). On top of that,
    // applyMergedTempMode drops cpuTemp / gpuTemp from the strip when
    // the user asked to merge them into the cpu / gpu ring AND both
    // sides are enabled (a merge with nothing to merge into stays a
    // standalone temperature ring).
    readonly property var _rawEnabledList: Catalog.filterByOrder(Catalog.parseCsv(content.configStore.enabledMetrics), Catalog.parseCsv(content.configStore.metricOrder))
    readonly property var enabledList: Catalog.applyMergedTempMode(_rawEnabledList, content.configStore.mergeCpuTemp, content.configStore.mergeGpuTemp)
    readonly property bool vertical: content.configStore.orientation === "vertical"
    readonly property int count: Math.max(1, content.enabledList.length)

    // Effective temperature mode: "celsius" or "fahrenheit", resolved
    // from the user's preference + the system locale's measurement
    // system. Computed once at this layer and forwarded to delegates so
    // every ring uses the same unit.
    readonly property string _tempMode: Catalog.resolveTempMode(content.configStore.tempUnit, Qt.locale().measurementSystem)

    columns: vertical ? 1 : count
    rowSpacing: 12
    columnSpacing: 12
    implicitWidth: vertical ? 180 : 180 * count
    implicitHeight: vertical ? 180 * count : 180

    Repeater {
        model: content.enabledList

        delegate: Ring {
            id: ringDelegate
            required property string modelData

            // Three flavours of ring share this delegate:
            //   1. usage rings (cpu/ram/swap/gpu/disk) — value is a %
            //      → drives both sweep and centre text via `value`.
            //   2. temperature rings (cpuTemp/gpuTemp) — sensor reports
            //      raw °C → value = tempToPercent(°C) for sweep,
            //      rawValue = converted °C/°F for the centre text.
            //   3. merged cpu/gpu — usage on the left half, temp on
            //      the right half (split mode), triggered by the
            //      merge* config when both sides are enabled.
            readonly property bool _isTemp: Catalog.isTempMetric(modelData)
            readonly property bool _splitOn: Catalog.isSplitForBase(modelData, content._rawEnabledList, content.configStore.mergeCpuTemp, content.configStore.mergeGpuTemp)
            // Raw °C for the secondary readout (split right half OR
            // dedicated temp metric). Cheap query — always evaluated
            // for the metrics that have a temperature sensor.
            readonly property real _rawTempC: _isTemp ? content.metrics.metricValue(modelData) : (_splitOn ? content.metrics.metricRawTemp(modelData) : 0)
            // { value, unit } in the user's selected unit. Reused by
            // both the dedicated-temp-metric path and the split-mode
            // right-half path.
            readonly property var _tempInfo: (_isTemp || _splitOn) ? Catalog.convertTemp(_rawTempC, content._tempMode) : null

            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 80
            Layout.minimumHeight: 80

            label: Catalog.labelFor(modelData)
            // During loading every ring sweeps to 100% — a "warming
            // up" visual cue. Once metrics.loading flips false (first
            // ksysguard tick lands), values animate down to actuals
            // via the existing Behavior on displayValue (400ms easing).
            // rawValue stays NaN during loading so the centre text
            // shows the same 100 → actual reveal as the sweep.
            //
            // For usage rings: value is the % directly. For temperature
            // rings: value drives the sweep so it must be the mapped
            // percent; the actual °C goes into rawValue below.
            value: content.metrics.loading ? 100 : (_isTemp ? Catalog.tempToPercent(_rawTempC) : content.metrics.metricValue(modelData))
            rawValue: !content.metrics.loading && _isTemp && _tempInfo ? _tempInfo.value : NaN
            unit: _isTemp && _tempInfo ? _tempInfo.unit : "%"
            nestedValues: modelData === "cpu" && content.configStore.showCpuCores ? content.metrics.coreValues : []
            splitMode: _splitOn
            // splitValue stays a percentage (0-100) so the geometry math
            // and tempToPercent threshold work in °C regardless of the
            // display unit; only splitRawValue / splitUnit change.
            splitValue: content.metrics.loading ? 100 : (_splitOn ? content.metrics.metricTempPercent(modelData) : 0)
            splitRawValue: !content.metrics.loading && _splitOn && _tempInfo ? _tempInfo.value : 0
            splitUnit: _splitOn && _tempInfo ? _tempInfo.unit : ""
            ringColor: ColorThemes.resolveColor(content.configStore.colorTheme, ColorThemes.effectiveIsDark(content.configStore.colorMode, content.theme.isDarkMode), content.theme.highlightColor, content.configStore.customColorLight, content.configStore.customColorDark)
            textColor: content.theme.textColor
            textOpacity: content.configStore.textOpacity
            trackOpacity: content.configStore.trackOpacity
            arcOpacity: content.configStore.arcOpacity
        }
    }
}
