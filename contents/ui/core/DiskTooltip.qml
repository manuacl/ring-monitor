import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import "DiskTooltipModel.js" as Model

// Hover tooltip for the disk ring(s) (issue #68): one line per shown disk —
// a removable/fixed icon tinted to that ring's colour, the volume label with a
// dimmed `mountpoint · fstype` sub-line, the usage % + used/total, and the free
// space. All strings come from the pure DiskTooltipModel so this view stays
// presentational.
//
// The popup chrome here is DUPLICATED from ProcessTooltip (#69), not shared:
// extracting it into a HoverTooltip base required injecting the body via a
// Loader contentItem, and a Window-type QQC2 popup renders WRONG with a Loader
// contentItem (in-scene/clipped instead of a floating surface — caught live on
// Qt 6.10, both rings). The body must be the popup's DIRECT contentItem. The
// default-property alternative captures this file's own HoverHandler. So the
// two tooltips each own their chrome; keep them in sync. See core/CLAUDE.md
// § "QQC2 popup over the widget…".
//
// Inputs (the parent — MainContent — wires them on the disk ring delegate):
//   armed   - true only on the disk ring; gates the HoverHandler.
//   details - [partitionDetail] in ring order, each metrics.partitionDetail(id).
//   colors  - per-ring colours aligned to `details` (MainContent._diskColors).
//   fallbackColor - the shared ring colour, for a row with no colour.
// Output:
//   samplingActive - true the instant the pointer enters (armed-gated); the
//                    parent binds metrics.diskTooltipActive to it.
Item {
    id: root

    property bool armed: false
    property var details: []
    property var colors: []
    property color fallbackColor: Kirigami.Theme.highlightColor
    property string title: qsTr("Disks")

    readonly property bool samplingActive: hover.hovered

    // Presentational rows from the pure model (label, subLabel, usageText,
    // freeText, iconName, removable); zipped with `colors` by index in the view.
    readonly property var _rows: Model.buildRows(root.details)
    // Test hooks (underscore = internal).
    readonly property alias _rowCount: rowRepeater.count
    property bool _show: false
    // Grow-only width high-water mark — see the popup's `width`. Reset on the
    // dismiss edge so a one-off wide sample doesn't pin every later hover.
    property real _maxContentWidth: 0
    readonly property bool _displayed: root.armed && root._show

    anchors.fill: parent

    HoverHandler {
        id: hover
        enabled: root.armed
    }

    Timer {
        id: showDelay
        interval: 500
        onTriggered: root._show = true
    }

    onSamplingActiveChanged: {
        if (samplingActive) {
            showDelay.restart();
        } else {
            showDelay.stop();
            root._show = false;
        }
    }

    on_DisplayedChanged: if (!root._displayed)
        root._maxContentWidth = 0

    QQC2.ToolTip {
        id: tip
        parent: root
        // A Window-type popup so it ISN'T clipped to the host window. `popupType`
        // is Qt 6.8+ but the floor is 6.6 — a declarative `popupType:` is a hard
        // load error on < 6.8 (takes the whole widget down, this is core/). Set it
        // imperatively + guarded. Full rationale: core/CLAUDE.md.
        Component.onCompleted: if (tip.popupType !== undefined)
            tip.popupType = QQC2.Popup.Window
        visible: root.armed && root._show
        // Content-driven width, bound explicitly (a Window popup won't auto-adopt
        // it) AND grow-only via the high-water mark. Height stays implicit.
        width: Math.max(root._maxContentWidth, col.implicitWidth) + leftPadding + rightPadding
        // Edge-aware: prefer below-and-right, FLIP on screen overflow.
        x: {
            var gx = root.mapToGlobal(0, 0).x;
            var screenRight = root.Screen.virtualX + root.Screen.width;
            if (gx + width > screenRight)
                return root.width - width;  // overflow right → right-align (grow left)
            return 0;                       // default → left-align (grow right)
        }
        y: {
            var gy = root.mapToGlobal(0, 0).y;
            var screenBottom = root.Screen.virtualY + root.Screen.height;
            if (gy + root.height + height > screenBottom)
                return -height;             // overflow bottom → above the ring
            return root.height;             // default → below the ring
        }

        contentItem: ColumnLayout {
            id: col
            spacing: Kirigami.Units.smallSpacing
            // Feed the grow-only width high-water mark; never let it shrink.
            onImplicitWidthChanged: if (implicitWidth > root._maxContentWidth)
                root._maxContentWidth = implicitWidth

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

                    // Removable/fixed glyph, tinted to this ring's colour (isMask
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
}
