import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

// The disk-partition picker, extracted from MetricsBody so that file stays
// focused (and under the 500-line cap). Reorderable list of discovered
// filesystems — checked partitions render as equal-thickness concentric
// rings inside the disk gauge, top = outermost ring. Each available row
// carries a per-partition color swatch (issue #67). Configured-but-unplugged
// partitions surface below as greyed, removable stale rows. Full rationale:
// docs/components.md § MetricsBody.
//
// `controller` is the MetricsBody: this view holds no state of its own — it
// reads the partition model and delegates every action (toggle, reorder,
// color set/clear, stale removal) back through the controller (DIP). It's a
// nested DraggableList; DraggableList auto-scopes each instance, so its drags
// don't fight the outer metrics list.

ColumnLayout {
    id: picker

    property var controller

    readonly property var _theme: picker.controller ? picker.controller.theme : null

    spacing: picker._theme ? picker._theme.smallSpacing : 4

    QQC2.Label {
        id: emptyLabel
        visible: picker.controller._partitionOrderModel.count === 0
        text: qsTr("No partitions detected.")
        opacity: 0.7
    }

    DraggableList {
        id: partitionList
        visible: picker.controller._partitionOrderModel.count > 0
        Layout.fillWidth: true
        Layout.preferredHeight: implicitHeight
        model: picker.controller._partitionOrderModel
        rowHeight: picker._theme ? picker._theme.unit * 1.6 : 28
        smallSpacing: picker._theme ? picker._theme.smallSpacing : 4
        iconSize: picker._theme ? picker._theme.iconSize : 16
        highlightColor: picker._theme ? picker._theme.highlightColor : "#3daee9"
        backgroundColor: picker._theme ? picker._theme.backgroundColor : "#1e1e1e"

        rowContent: Component {
            PartitionRow {
                objectName: "diskPartitionRow"
                readonly property string _partId: parent && parent.rowModel ? parent.rowModel.partId : ""
                partLabel: parent && parent.rowModel ? parent.rowModel.partLabel : ""
                available: true
                checked: picker.controller.isPartitionEnabled(_partId)
                onToggled: on => picker.controller.setPartitionEnabled(_partId, on)
                smallSpacing: picker._theme.smallSpacing
                iconSize: picker._theme.iconSize

                // Per-partition ring color (issue #67): swatch opens the picker,
                // clear drops the override. inheritedColor is the actual shared
                // ring color (resolved in the config wrapper) so the "unset"
                // swatch previews exactly what the ring shows.
                colorPickerComponent: picker.controller.colorPickerComponent
                customColor: picker.controller.partitionColor(_partId)
                inheritedColor: picker.controller.sharedRingColor
                onColorPicked: color => picker.controller.setPartitionColor(_partId, color)
                onColorCleared: picker.controller.clearPartitionColor(_partId)
            }
        }

        onReordered: function (from, to) {
            // ListModel.move reorders in place (keeps partId/partLabel), then
            // commit serializes the new model order to the CSV.
            picker.controller._partitionOrderModel.move(from, to, 1);
            picker.controller.commitPartitionOrder();
        }
    }

    // Stale rows: configured partitions no longer present (unplugged). Greyed,
    // non-draggable, each with a trash button that clears it from the
    // selection + order + label cache + color map. Same PartitionRow in its
    // !available variant, below the draggable list so ring nesting is untouched.
    Repeater {
        model: picker.controller.stalePartitionList
        delegate: PartitionRow {
            required property var modelData
            Layout.fillWidth: true
            partLabel: modelData.label
            available: false
            onRemoveRequested: picker.controller.removeStalePartition(modelData.id)
            smallSpacing: picker._theme.smallSpacing
            iconSize: picker._theme.iconSize
        }
    }

    // ── Test hooks ──────────────────────────────────────────────────
    readonly property alias _emptyLabel: emptyLabel
    readonly property alias _partitionList: partitionList
}
