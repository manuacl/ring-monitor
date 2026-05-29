import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import "ReorderLogic.js" as Logic
import "MetricsCatalog.js" as Catalog
import "DiskMetrics.js" as DiskMetrics

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
    // Metric ids with a live data source, injected by the platform wrapper.
    // null = unknown → every row enable-able (see isMetricAvailable).
    property var availableMetrics: null
    // Discovered disk partitions ([{id, label}]) injected by the platform
    // wrapper (Plasma: configMetrics via DiskPartitions; standalone:
    // SettingsDialog via the backend). Drives the per-partition checkboxes
    // under the disk row.
    property var diskPartitions: []
    // The backend's default partition selection (standalone: the $HOME-bearing
    // filesystem; Plasma: [] = aggregate). When the user hasn't selected
    // anything yet, the picker seeds enabledPartitions with this so the
    // default renders as a real, checked, editable row instead of showing the
    // widget's $HOME ring with every checkbox unchecked.
    property var defaultPartitionIds: []

    // ── Bridged via aliases in the wrapper (cfg_metricOrder ↔ body.metricOrderCsv, etc.) ──
    property string metricOrderCsv: ""
    property string enabledMetricsCsv: ""
    property string enabledPartitionsCsv: ""
    property string partitionOrderCsv: ""
    property bool showCpuCores: false
    property bool mergeCpuTemp: false
    property bool mergeGpuTemp: false
    property string tempUnit: "auto"

    // ── Internal — the displayed order is a ListModel built from metricOrderCsv ──
    ListModel {
        id: orderModel
    }

    // Parallel model for the disk partition reorder list (built from
    // partitionOrderCsv merged with the discovered diskPartitions).
    ListModel {
        id: partitionOrderModel
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
            disk: qsTr("Disk space per selected partition")
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

    // Availability unknown (null) → every metric is enable-able. Otherwise
    // a metric is available only if the backend lists it.
    function isMetricAvailable(id) {
        return !body.availableMetrics || body.availableMetrics.indexOf(id) !== -1;
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

    function isPartitionEnabled(id) {
        return Catalog.parseCsv(body.enabledPartitionsCsv).indexOf(id) !== -1;
    }

    function setPartitionEnabled(id, on) {
        body.enabledPartitionsCsv = Catalog.toggleEnabled(Catalog.parseCsv(body.enabledPartitionsCsv), id, on).join(",");
    }

    function currentPartitionOrder() {
        const arr = [];
        for (let i = 0; i < partitionOrderModel.count; i++)
            arr.push(partitionOrderModel.get(i).partId);
        return arr;
    }

    // Rebuild the partition reorder model: saved order first, then
    // newly-discovered partitions appended alphabetically (the default).
    function loadPartitionOrder() {
        partitionOrderModel.clear();
        const ordered = DiskMetrics.orderPartitions(body.partitionOrderCsv, body.diskPartitions || []);
        for (let i = 0; i < ordered.length; i++) {
            partitionOrderModel.append({
                partId: ordered[i].id,
                partLabel: ordered[i].label
            });
        }
    }

    function commitPartitionOrder() {
        body.partitionOrderCsv = currentPartitionOrder().join(",");
    }

    // Seed the selection with the backend default when nothing is chosen yet,
    // so the picker reflects what the widget actually renders (the default
    // ring) as a checked, editable row. Empty selection = always the default
    // (the disk metric shows ≥1 partition); to hide it, disable the metric.
    function _seedDefaultIfEmpty() {
        if (body.enabledPartitionsCsv === "" && body.defaultPartitionIds && body.defaultPartitionIds.length > 0)
            body.enabledPartitionsCsv = body.defaultPartitionIds.join(",");
    }

    onMetricOrderCsvChanged: loadOrder()
    onPartitionOrderCsvChanged: loadPartitionOrder()
    onDiskPartitionsChanged: {
        loadPartitionOrder();
        _seedDefaultIfEmpty();
    }
    onDefaultPartitionIdsChanged: _seedDefaultIfEmpty()
    Component.onCompleted: {
        loadOrder();
        loadPartitionOrder();
        _seedDefaultIfEmpty();
    }

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
                available: body.isMetricAvailable(_metricId)
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
                    if (_metricId === "disk")
                        return diskPartitionsPicker;
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

    // Reorderable list of discovered filesystems — checked partitions render
    // as equal-thickness concentric rings inside the disk gauge, in this
    // list's order (top = outermost ring, bottom = innermost). Default order
    // is alphabetical by label; drag the handle to reorder. Empty selection
    // falls back to the backend default (the $HOME filesystem on standalone;
    // the disk/all aggregate on Plasma). A hint shows when no partitions were
    // discovered (e.g. the config dialog ran before ksysguard populated the
    // tree). This DraggableList is nested inside the disk row's extraContent,
    // which is itself indented inside the metrics DraggableList — the inner
    // drag handle sits to the right of the outer one, so the two don't fight.
    Component {
        id: diskPartitionsPicker
        ColumnLayout {
            spacing: body.theme ? body.theme.smallSpacing : 4
            QQC2.Label {
                visible: partitionOrderModel.count === 0
                text: qsTr("No partitions detected.")
                opacity: 0.7
            }
            DraggableList {
                id: partitionList
                visible: partitionOrderModel.count > 0
                // No explicit dragKey: DraggableList auto-scopes each instance,
                // so this nested list and the outer metrics list don't fire
                // each other's DropAreas.
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                model: partitionOrderModel
                rowHeight: body.theme ? body.theme.unit * 1.6 : 28
                smallSpacing: body.theme ? body.theme.smallSpacing : 4
                iconSize: body.theme ? body.theme.iconSize : 16
                highlightColor: body.theme ? body.theme.highlightColor : "#3daee9"
                backgroundColor: body.theme ? body.theme.backgroundColor : "#1e1e1e"

                rowContent: Component {
                    QQC2.CheckBox {
                        readonly property string _partId: parent && parent.rowModel ? parent.rowModel.partId : ""
                        text: parent && parent.rowModel ? parent.rowModel.partLabel : ""
                        checked: body.isPartitionEnabled(_partId)
                        onClicked: body.setPartitionEnabled(_partId, checked)
                    }
                }

                onReordered: function (from, to) {
                    // ListModel.move reorders in place (keeps partId/partLabel),
                    // then commit serializes the new model order to the CSV.
                    partitionOrderModel.move(from, to, 1);
                    body.commitPartitionOrder();
                }
            }
        }
    }

    // ── Test hooks ──────────────────────────────────────────────────
    readonly property alias _orderModel: orderModel
    readonly property alias _partitionOrderModel: partitionOrderModel
    readonly property alias _list: list
    readonly property alias _tempUnitAuto: tempUnitAuto
    readonly property alias _tempUnitCelsius: tempUnitCelsius
    readonly property alias _tempUnitFahrenheit: tempUnitFahrenheit
}
