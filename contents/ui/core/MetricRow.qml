import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import "MetricsCatalog.js" as Catalog

// One row of the draggable metrics list:
//
//     [CheckBox: <label>]   <description>
//         └─ <optional extraContent — indented sub-row, e.g. per-metric option>
//
// Pure presentation — the label string comes from MetricsCatalog,
// `enabled`/`description` are inputs, and toggling emits a signal.
// `extraContent` is an optional Component rendered indented below the
// main row (used to attach a metric-specific sub-option, e.g. the
// "show CPU cores" toggle that hangs off the CPU row).
//
// Disabled-state convention (applies to all rows, including any future
// metric with extraContent children):
//   - The row's main checkbox keeps full opacity so the user can clearly
//     see / re-enable it.
//   - The description label dims.
//   - The extraContent inherits `enabled: row.enabled` so its child
//     controls (CheckBoxes etc.) become non-interactive AND visually
//     disabled by Qt's theme. Don't render an "enabled" sub-option for
//     a row whose master toggle is off.
//
// Availability is a SEPARATE axis from enabled/checked. `available` is
// false when the backend reports no live data source for this metric
// (GPU on a non-NVIDIA box, swap on a swapless host, an unresolved
// CPU-temp sensor). An unavailable row dims, annotates itself ("not
// detected"), and makes the checkbox non-interactive so the user can't
// enable a metric that would render a dead 0% ring — while still seeing
// why. It can flip back to available at runtime (a late-modprobed
// sensor), at which point the row re-enables.
//
// No coupling to the page or the DraggableList scaffolding; this lets
// us instantiate it directly in `tests/qml/tst_MetricRow.qml`.

Item {
    id: row

    // ── Inputs ──────────────────────────────────────────────────────
    property string metricId: ""
    property bool enabled: false
    // The metric has a live data source on this host. Defaults true so a
    // parent that doesn't track availability (or hasn't resolved it yet)
    // shows every row as enable-able.
    property bool available: true
    property string description: ""
    property Component extraContent: null

    // Description opacity: dim when disabled, dim further (and ignore the
    // enabled state) when the metric isn't available. Extracted to dodge a
    // nested ternary in the binding.
    readonly property real _descriptionOpacity: {
        if (!row.available)
            return 0.3;
        return row.enabled ? 0.55 : 0.3;
    }

    // Theme tokens — injected by the parent via the platforms/plasma/Theme adapter.
    // Sensible defaults match Kirigami's typical values.
    property real unit: 18
    property real smallSpacing: 4

    // ── Output ──────────────────────────────────────────────────────
    signal toggled(bool on)

    implicitWidth: column.implicitWidth
    implicitHeight: column.implicitHeight

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            spacing: row.smallSpacing

            QQC2.CheckBox {
                id: checkBox
                text: Catalog.labelFor(row.metricId)
                checked: row.enabled
                // Decoupled from the row's enabled (checked) state: the box
                // stays interactive whenever the metric is available so the
                // user can toggle it on or off, but goes non-interactive
                // when there's no data source behind it.
                enabled: row.available
                onClicked: row.toggled(checked)
                Layout.minimumWidth: row.unit * 5
            }

            QQC2.Label {
                id: descriptionLabel
                text: row.description
                opacity: row._descriptionOpacity
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            // Why the row can't be enabled — only shown when unavailable.
            QQC2.Label {
                id: unavailableLabel
                visible: !row.available
                text: qsTr("not detected")
                opacity: 0.5
                font.italic: true
            }
        }

        Loader {
            id: extraLoader
            Layout.fillWidth: true
            Layout.leftMargin: row.unit * 2   // indent under the checkbox
            Layout.bottomMargin: row.extraContent ? row.smallSpacing : 0
            sourceComponent: row.extraContent
            active: row.extraContent !== null
            visible: active
            // QML cascades `enabled` to descendants — child controls
            // (e.g. a sub-CheckBox) get the theme's disabled rendering
            // and become non-interactive when the master is off.
            enabled: row.enabled
        }
    }

    // ── Test hooks ──────────────────────────────────────────────────
    // The QML test runner reads these to assert what's actually
    // rendered, without poking into child indexes.
    readonly property alias _labelText: checkBox.text
    readonly property alias _descriptionText: descriptionLabel.text
    readonly property alias _checked: checkBox.checked
    readonly property alias _checkBox: checkBox
    readonly property alias _descriptionLabel: descriptionLabel
    readonly property alias _unavailableLabel: unavailableLabel
    readonly property alias _extraLoader: extraLoader
}
