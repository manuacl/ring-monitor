import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import "ReorderLogic.js" as Logic
import "MetricsCatalog.js" as Catalog

// Body of the Metrics config page. Owns the reorderable list, the
// internal ListModel, and the per-row UI (CheckBox + drag handle +
// optional sub-toggle for CPU cores).
//
// Bidirectional state is exposed as plain QML properties; the wrapper
// (configMetrics.qml) bridges them to Plasma's cfg_* magic via
// `property alias` declarations. The body never touches Plasma APIs
// directly.
//
// i18n strings use qsTr() rather than Plasma's i18n() — see
// docs/plasma-isolation/plan.md for the rationale (works in both
// Plasma applet runtime and a future standalone build).

ColumnLayout {
    id: body

    // ── Adapter input ───────────────────────────────────────────────
    property var theme

    // ── Bridged via aliases in the wrapper (cfg_metricOrder ↔ body.metricOrderCsv, etc.) ──
    property string metricOrderCsv: ""
    property string enabledMetricsCsv: ""
    property bool showCpuCores: false
    property bool mergeCpuTemp: false
    property bool mergeGpuTemp: false
    property string tempUnit: "auto"

    // ── Internal — the displayed order is a ListModel built from metricOrderCsv ──
    ListModel {
        id: orderModel
    }

    // Descriptions are owned by the body so it stays self-contained.
    // The wrapper does not need to know about per-metric copy.
    readonly property var metricDescriptions: ({
            cpu: qsTr("Overall processor usage"),
            cpuTemp: qsTr("CPU temperature"),
            ram: qsTr("Physical memory used"),
            swap: qsTr("Swap usage"),
            gpu: qsTr("GPU usage"),
            gpuTemp: qsTr("GPU temperature"),
            disk: qsTr("Disk space used (all partitions)")
        })

    function currentOrder() {
        const arr = [];
        for (let i = 0; i < orderModel.count; i++)
            arr.push(orderModel.get(i).metricId);
        return arr;
    }

    function loadOrder() {
        orderModel.clear();
        // mergeWithCatalog appends any catalog id missing from the
        // persisted CSV — so a release adding new metrics (e.g. 0.4 →
        // cpuTemp / gpuTemp) populates the config list without forcing
        // existing users to reset their config or migrate manually.
        const ids = Catalog.mergeWithCatalog(Catalog.parseCsv(body.metricOrderCsv));
        for (let i = 0; i < ids.length; i++) {
            orderModel.append({
                metricId: ids[i]
            });
        }
    }

    function commitOrder() {
        body.metricOrderCsv = currentOrder().join(",");
    }

    function isEnabled(id) {
        return Catalog.parseCsv(body.enabledMetricsCsv).indexOf(id) !== -1;
    }

    function setEnabled(id, on) {
        body.enabledMetricsCsv = Catalog.toggleEnabled(Catalog.parseCsv(body.enabledMetricsCsv), id, on).join(",");
        // Mirror of the auto-enable behaviour in the merge checkboxes:
        // disabling the base ring removes its merge target, so drop the
        // merge toggle too instead of leaving a misleading checkmark.
        if (!on && id === "cpu" && body.mergeCpuTemp)
            body.mergeCpuTemp = false;
        if (!on && id === "gpu" && body.mergeGpuTemp)
            body.mergeGpuTemp = false;
    }

    onMetricOrderCsvChanged: loadOrder()
    Component.onCompleted: loadOrder()

    Layout.fillWidth: true
    spacing: body.theme ? body.theme.smallSpacing : 4

    QQC2.Label {
        text: qsTr("Toggle metrics to display. Drag a row by the handle on the left to reorder.")
        wrapMode: Text.WordWrap
        opacity: 0.7
        Layout.fillWidth: true
    }

    DraggableList {
        id: list
        Layout.fillWidth: true
        Layout.preferredHeight: implicitHeight
        model: orderModel
        rowHeight: body.theme ? body.theme.unit * 2 : 36

        smallSpacing: body.theme ? body.theme.smallSpacing : 4
        iconSize: body.theme ? body.theme.iconSize : 16
        highlightColor: body.theme ? body.theme.highlightColor : "#3daee9"
        backgroundColor: body.theme ? body.theme.backgroundColor : "#1e1e1e"

        rowContent: Component {
            MetricRow {
                // The Loader (inside DraggableList) puts the row data
                // on us as `parent.rowModel` / `parent.rowIndex`.
                readonly property string _metricId: parent && parent.rowModel ? parent.rowModel.metricId : ""

                metricId: _metricId
                enabled: body.isEnabled(_metricId)
                description: body.metricDescriptions[_metricId] || ""
                onToggled: on => body.setEnabled(_metricId, on)

                // Theme tokens — `body` is resolved through the
                // Component's definition scope (MetricsBody.qml).
                unit: body.theme.unit
                smallSpacing: body.theme.smallSpacing

                // Per-metric sub-options indented below the row.
                //   cpu     → "show cores" toggle
                //   cpuTemp → "merge into the cpu ring" toggle
                //   gpuTemp → "merge into the gpu ring" toggle
                extraContent: {
                    if (_metricId === "cpu")
                        return cpuCoresToggle;
                    if (_metricId === "cpuTemp")
                        return cpuTempMergeToggle;
                    if (_metricId === "gpuTemp")
                        return gpuTempMergeToggle;
                    return null;
                }
            }
        }

        onReordered: function (from, to) {
            // Apply the move through the pure helper, then sync the
            // ListModel + commit back to the CSV (which propagates to
            // cfg_metricOrder via the wrapper's alias).
            const next = Logic.applyMove(body.currentOrder(), from, to);
            orderModel.clear();
            for (let i = 0; i < next.length; i++) {
                orderModel.append({
                    metricId: next[i]
                });
            }
            body.commitOrder();
        }
    }

    // Temperature display unit — global across all rings, sits below
    // the per-metric toggles since it's only meaningful when at least
    // one *Temp option is on. "Follow system" resolves via
    // Qt.locale().measurementSystem in MainContent (Imperial-US → °F,
    // everything else → °C — see Catalog.resolveTempMode).
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: body.theme ? body.theme.smallSpacing : 4
        spacing: body.theme ? body.theme.smallSpacing : 4
        visible: body.isEnabled("cpuTemp") || body.isEnabled("gpuTemp")

        QQC2.Label {
            text: qsTr("Temperature unit:")
        }
        QQC2.RadioButton {
            id: tempUnitAuto
            text: qsTr("Follow system")
            checked: body.tempUnit === "auto"
            onClicked: body.tempUnit = "auto"
        }
        QQC2.RadioButton {
            id: tempUnitCelsius
            text: qsTr("Celsius")
            checked: body.tempUnit === "celsius"
            onClicked: body.tempUnit = "celsius"
        }
        QQC2.RadioButton {
            id: tempUnitFahrenheit
            text: qsTr("Fahrenheit")
            checked: body.tempUnit === "fahrenheit"
            onClicked: body.tempUnit = "fahrenheit"
        }
        Item {
            Layout.fillWidth: true
        }
    }

    // Sub-options rendered as children of their parent metric row.
    // Defined at body scope so bindings to body.* survive row
    // destruction/recreation on reorder.
    Component {
        id: cpuCoresToggle
        QQC2.CheckBox {
            text: qsTr("Show CPU cores as concentric rings")
            checked: body.showCpuCores
            onClicked: body.showCpuCores = checked
        }
    }

    // Merge needs both rings to be enabled. "cpuTemp disabled" is
    // handled upstream by MetricRow's Loader.enabled cascade. For the
    // other half — ticking Merge while cpu is off — auto-enable cpu
    // so the merge has somewhere to land instead of silently no-op'ing.
    Component {
        id: cpuTempMergeToggle
        QQC2.CheckBox {
            text: qsTr("Merge into the CPU ring (right half)")
            checked: body.mergeCpuTemp
            onClicked: {
                body.mergeCpuTemp = checked;
                if (checked && !body.isEnabled("cpu"))
                    body.setEnabled("cpu", true);
            }
        }
    }

    Component {
        id: gpuTempMergeToggle
        QQC2.CheckBox {
            text: qsTr("Merge into the GPU ring (right half)")
            checked: body.mergeGpuTemp
            onClicked: {
                body.mergeGpuTemp = checked;
                if (checked && !body.isEnabled("gpu"))
                    body.setEnabled("gpu", true);
            }
        }
    }

    // ── Test hooks ──────────────────────────────────────────────────
    readonly property alias _orderModel: orderModel
    readonly property alias _list: list
    readonly property alias _tempUnitAuto: tempUnitAuto
    readonly property alias _tempUnitCelsius: tempUnitCelsius
    readonly property alias _tempUnitFahrenheit: tempUnitFahrenheit
}
