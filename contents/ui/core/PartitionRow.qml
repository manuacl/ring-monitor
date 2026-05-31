import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

// One row of the disk-partition picker, with an `available` axis mirroring
// MetricRow's:
//
//   available  → a CheckBox the user toggles to include the partition as a
//                concentric disk ring (drag handle is supplied by the
//                enclosing DraggableList).
//   !available → the partition is configured but no longer discovered
//                (unplugged disk): a greyed label + "not connected" tag + a
//                trash button that asks the parent to forget it.
//
// Pure presentation — the label is an input, the partition id lives in the
// parent (DIP: this leaf takes what it renders and emits signals; the parent
// wires them to enabledPartitions / removeStalePartition). Kept separate from
// MetricRow because a partition row is label-driven (not a catalog metric id)
// and its unavailable variant is a remove action, not a frozen checkbox.

Item {
    id: row

    // ── Inputs ──────────────────────────────────────────────────────
    property string partLabel: ""
    property bool available: true
    property bool checked: false

    // Per-partition ring color (issue #67). `customColor` is the stored
    // override ("" = none → the ring inherits the shared color, shown here
    // via `inheritedColor`). `colorPickerComponent` is the platform-injected
    // picker Component; when absent the swatch + clear button don't render
    // (e.g. a host that doesn't wire a picker). Only the available variant
    // gets a color control — a disconnected partition has no ring to color.
    property Component colorPickerComponent
    property string customColor: ""
    property color inheritedColor: "#3daee9"

    // Theme tokens — injected by the parent. Defaults match Kirigami's.
    property real smallSpacing: 4
    property real iconSize: 16

    // ── Output ──────────────────────────────────────────────────────
    signal toggled(bool on)
    signal removeRequested
    // Emitted when the user confirms a color in the picker, and when they
    // clear the override (back to the shared ring color).
    signal colorPicked(color picked)
    signal colorCleared

    readonly property bool _hasCustomColor: row.customColor !== ""
    readonly property bool _colorControlVisible: row.available && row.colorPickerComponent !== null

    implicitWidth: layout.implicitWidth
    implicitHeight: layout.implicitHeight

    RowLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: row.smallSpacing

        QQC2.CheckBox {
            id: checkBox
            visible: row.available
            text: row.partLabel
            checked: row.checked
            onClicked: row.toggled(checked)
            Layout.fillWidth: true
        }

        // ── Per-partition color swatch (available variant) ──────────
        // The swatch shows the override when set, else the inherited
        // (shared) color so the user sees the current ring color before
        // overriding. Confirming the dialog emits colorPicked.
        Loader {
            id: colorButton
            visible: row._colorControlVisible
            sourceComponent: row.colorPickerComponent
            onLoaded: {
                if (!item)
                    return;
                item.color = Qt.binding(function () {
                    return row._hasCustomColor ? row.customColor : row.inheritedColor;
                });
                item.accepted.connect(function () {
                    row.colorPicked(item.color);
                });
            }
        }
        // Clear the override → back to the shared widget color. Only
        // meaningful (and visible) once a custom color is set.
        QQC2.ToolButton {
            id: clearColorButton
            visible: row._colorControlVisible && row._hasCustomColor
            icon.name: "edit-clear"
            flat: true
            onClicked: row.colorCleared()
            QQC2.ToolTip.text: qsTr("Use the general ring color")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: 500
        }

        // ── Stale variant ───────────────────────────────────────────
        QQC2.Label {
            id: staleLabel
            visible: !row.available
            text: row.partLabel
            opacity: 0.4
            font.italic: true
            elide: Text.ElideRight
            Layout.fillWidth: true
            // Align under the available rows' label: mirror DraggableList's
            // drag-handle width (handleArea = iconSize + 12) since stale rows
            // sit outside the list and have no handle of their own.
            Layout.leftMargin: row.iconSize + 12

            HoverHandler {
                id: staleHover
            }
            QQC2.ToolTip.text: qsTr("This filesystem is no longer connected — remove it from the selection.")
            QQC2.ToolTip.visible: staleHover.hovered
            QQC2.ToolTip.delay: 500
        }
        QQC2.Label {
            id: unavailableLabel
            visible: !row.available
            text: qsTr("not connected")
            opacity: 0.5
            font.italic: true
        }
        QQC2.ToolButton {
            id: removeButton
            visible: !row.available
            icon.name: "edit-delete-remove"
            flat: true
            onClicked: row.removeRequested()
            QQC2.ToolTip.text: qsTr("Remove this disconnected filesystem")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: 500
        }
    }

    // ── Test hooks ──────────────────────────────────────────────────
    readonly property alias _checkBox: checkBox
    readonly property alias _colorButton: colorButton
    readonly property alias _clearColorButton: clearColorButton
    readonly property alias _staleLabel: staleLabel
    readonly property alias _unavailableLabel: unavailableLabel
    readonly property alias _removeButton: removeButton
}
