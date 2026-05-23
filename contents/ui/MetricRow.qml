import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "MetricsCatalog.js" as Catalog

// One row of the draggable metrics list:
//
//     [CheckBox: <label>]   <description>
//
// Pure presentation — the label string comes from MetricsCatalog,
// `enabled`/`description` are inputs, and toggling emits a signal.
// No coupling to the page or the DraggableList scaffolding; this lets
// us instantiate it directly in `tests/qml/tst_MetricRow.qml`.

RowLayout {
    id: row

    // ── Inputs ──────────────────────────────────────────────────────
    property string metricId: ""
    property bool enabled: false
    property string description: ""

    // ── Output ──────────────────────────────────────────────────────
    signal toggled(bool on)

    spacing: Kirigami.Units.smallSpacing

    QQC2.CheckBox {
        id: checkBox
        text: Catalog.labelFor(row.metricId)
        checked: row.enabled
        onClicked: row.toggled(checked)
        Layout.minimumWidth: Kirigami.Units.gridUnit * 5
    }

    QQC2.Label {
        id: descriptionLabel
        text: row.description
        opacity: 0.55
        Layout.fillWidth: true
        elide: Text.ElideRight
    }

    // ── Test hooks ──────────────────────────────────────────────────
    // The QML test runner reads these to assert what's actually
    // rendered, without poking into child indexes.
    readonly property alias _labelText: checkBox.text
    readonly property alias _descriptionText: descriptionLabel.text
    readonly property alias _checked: checkBox.checked
}
