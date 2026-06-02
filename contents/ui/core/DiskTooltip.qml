import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import "DiskTooltipModel.js" as Model

// Hover tooltip for the disk ring(s) (issue #68): one line per shown disk —
// a removable/fixed icon tinted to that ring's colour, the volume label with a
// dimmed `mountpoint · fstype` sub-line, the usage % + used/total, and the free
// space. Reuses the shared HoverTooltip popup chrome; the body is built from the
// pure DiskTooltipModel so this view stays presentational.
//
// Inputs (the parent — MainContent — wires them on the disk ring delegate):
//   armed   - true only on the disk ring.
//   details - [partitionDetail] in ring order (outermost first), each the
//             metrics.partitionDetail(id) object. Re-evaluated on the disk tick.
//   colors  - per-ring colours aligned to `details` (MainContent._diskColors);
//             the icon tints to its ring so the tooltip line maps to the gauge.
//   fallbackColor - the shared ring colour, used when a row has no colour.
HoverTooltip {
    id: root

    property var details: []
    property var colors: []
    property color fallbackColor: Kirigami.Theme.highlightColor
    property string title: qsTr("Disks")

    // Presentational rows from the pure model (label, subLabel, usageText,
    // freeText, iconName, removable); zipped with `colors` by index below.
    readonly property var _rows: Model.buildRows(root.details)
    readonly property int _rowCount: root.contentItem ? root.contentItem.rowCount : 0

    contentComponent: ColumnLayout {
        id: col
        readonly property alias rowCount: rowRepeater.count
        spacing: root.contentSpacing

        QQC2.Label {
            text: root.title
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            Layout.fillWidth: true
            Layout.bottomMargin: Kirigami.Units.smallSpacing
        }

        Repeater {
            id: rowRepeater
            model: root._rows

            delegate: RowLayout {
                id: diskRow
                required property var modelData
                required property int index
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                // Removable vs fixed glyph, tinted to this ring's colour (isMask
                // recolours the monochrome icon) so the line maps to its gauge.
                Kirigami.Icon {
                    source: diskRow.modelData.iconName
                    isMask: true
                    color: (root.colors && root.colors[diskRow.index]) ? root.colors[diskRow.index] : root.fallbackColor
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true
                    QQC2.Label {
                        text: diskRow.modelData.label
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        // Cap so one long label can't stretch the popup absurdly.
                        Layout.maximumWidth: Kirigami.Units.gridUnit * 12
                    }
                    QQC2.Label {
                        text: diskRow.modelData.subLabel
                        visible: text.length > 0
                        font: Kirigami.Theme.smallFont
                        opacity: 0.55
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                ColumnLayout {
                    spacing: 0
                    Layout.alignment: Qt.AlignRight
                    QQC2.Label {
                        text: diskRow.modelData.usageText
                        horizontalAlignment: Text.AlignRight
                        Layout.alignment: Qt.AlignRight
                    }
                    QQC2.Label {
                        text: diskRow.modelData.freeText
                        visible: text.length > 0
                        font: Kirigami.Theme.smallFont
                        opacity: 0.55
                        horizontalAlignment: Text.AlignRight
                        Layout.alignment: Qt.AlignRight
                    }
                }
            }
        }

        // ~one-tick warm-up before the first partitionDetail resolves.
        QQC2.Label {
            visible: rowRepeater.count === 0
            text: qsTr("Gathering…")
            opacity: 0.6
        }
    }
}
