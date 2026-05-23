import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    property string cfg_metricOrder
    property string cfg_enabledMetrics
    property alias cfg_showCpuCores: coresCheck.checked

    // HACK: declared to suppress "no property called cfg_xxx" warnings from
    // Plasma trying to set every config key on every page. See KDE bug 484541.
    // Plasma 6 also auto-generates cfg_<key>Default properties for the
    // "Reset to defaults" feature — those must also be declared as placeholders.
    property var cfg_orientation
    property var cfg_orientationDefault
    property var cfg_textOpacity
    property var cfg_textOpacityDefault
    property var cfg_trackOpacity
    property var cfg_trackOpacityDefault
    property var cfg_arcOpacity
    property var cfg_arcOpacityDefault
    property var cfg_metricOrderDefault
    property var cfg_enabledMetricsDefault
    property var cfg_showCpuCoresDefault

    readonly property var metricMeta: ({
        cpu:  { label: i18n("CPU"),  description: i18n("Overall processor usage") },
        ram:  { label: i18n("RAM"),  description: i18n("Physical memory used") },
        swap: { label: i18n("Swap"), description: i18n("Swap usage") },
        gpu:  { label: i18n("GPU"),  description: i18n("GPU usage") },
        disk: { label: i18n("Disk"), description: i18n("Disk space used (all partitions)") },
    })

    readonly property var enabledList: (cfg_enabledMetrics || "").split(",").filter(function(x) { return x })

    function isEnabled(id) { return enabledList.indexOf(id) !== -1 }

    function setEnabled(id, on) {
        const arr = enabledList.filter(function(x) { return x !== id })
        if (on) arr.push(id)
        cfg_enabledMetrics = arr.join(",")
    }

    // ── Order model (mirror of cfg_metricOrder, mutable for drag-and-drop) ──
    ListModel { id: orderModel }

    function loadOrder() {
        orderModel.clear()
        const ids = (cfg_metricOrder || "").split(",").filter(function(x) { return x })
        for (let i = 0; i < ids.length; i++) {
            orderModel.append({ metricId: ids[i] })
        }
    }
    function commitOrder() {
        const arr = []
        for (let i = 0; i < orderModel.count; i++) arr.push(orderModel.get(i).metricId)
        cfg_metricOrder = arr.join(",")
    }

    // Reload model whenever the config key changes (initial load + external edits)
    onCfg_metricOrderChanged: loadOrder()
    Component.onCompleted: loadOrder()

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        QQC2.Label {
            text: i18n("Toggle metrics to display. Drag a row by the handle on the left to reorder, or use the arrows.")
            wrapMode: Text.WordWrap
            opacity: 0.7
            Layout.fillWidth: true
        }

        ListView {
            id: listView
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(1, orderModel.count) * (Kirigami.Units.gridUnit * 2 + 4)
            spacing: 4
            interactive: false
            model: orderModel

            // Deferred-drop reorder pattern:
            //   - On press, dragSourceIndex captures the picked row.
            //   - As the user drags over other rows, DropArea sets dropTargetIndex
            //     but the model is NOT mutated. Other rows shift via `transform`
            //     to create a gap at the projected drop location.
            //   - On release, the actual orderModel.move() commits the new order.
            property int dragSourceIndex: -1
            property int dropTargetIndex: -1

            delegate: Item {
                id: row
                width: ListView.view.width
                height: Kirigami.Units.gridUnit * 2

                readonly property bool held: listView.dragSourceIndex === index
                readonly property int rowIndex: index
                readonly property string metricId: model.metricId

                // Visual shift to "make room" for the dragged item. Held row
                // doesn't shift — it floats free under the mouse via ParentChange.
                readonly property real yShift: {
                    const src = listView.dragSourceIndex
                    const tgt = listView.dropTargetIndex
                    if (src < 0 || tgt < 0 || src === tgt) return 0
                    if (index === src) return 0   // the dragged row, ignore
                    const step = row.height + listView.spacing
                    if (src < tgt && index > src && index <= tgt) return -step
                    if (src > tgt && index >= tgt && index < src) return step
                    return 0
                }
                transform: Translate {
                    y: row.yShift
                    Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                }

                Rectangle {
                    id: rowBg
                    width: row.width
                    height: row.height
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    radius: 4
                    color: row.held ? Qt.rgba(Kirigami.Theme.highlightColor.r,
                                              Kirigami.Theme.highlightColor.g,
                                              Kirigami.Theme.highlightColor.b, 0.35)
                                    : (mouseHover.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent")
                    border.width: row.held ? 0 : 1
                    border.color: Qt.rgba(1, 1, 1, 0.08)
                    z: row.held ? 100 : 0   // dragged row on top

                    Drag.active: row.held
                    Drag.source: row
                    Drag.hotSpot.x: width / 2
                    Drag.hotSpot.y: height / 2

                    states: State {
                        when: row.held
                        ParentChange { target: rowBg; parent: listView }
                        AnchorChanges {
                            target: rowBg
                            anchors.horizontalCenter: undefined
                            anchors.verticalCenter: undefined
                        }
                    }

                    HoverHandler { id: mouseHover }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        spacing: Kirigami.Units.smallSpacing

                        // Drag handle (visual only — the actual MouseArea is a
                        // SIBLING of rowBg below, so it doesn't move when the
                        // rectangle gets reparented during drag).
                        Kirigami.Icon {
                            id: handleIcon
                            source: "transform-move"
                            implicitWidth: Kirigami.Units.iconSizes.small
                            implicitHeight: Kirigami.Units.iconSizes.small
                            opacity: 0.5
                        }

                        QQC2.CheckBox {
                            text: page.metricMeta[row.metricId] ? page.metricMeta[row.metricId].label : row.metricId
                            checked: page.isEnabled(row.metricId)
                            onClicked: page.setEnabled(row.metricId, checked)
                            Layout.minimumWidth: Kirigami.Units.gridUnit * 5
                        }

                        QQC2.Label {
                            text: page.metricMeta[row.metricId] ? page.metricMeta[row.metricId].description : ""
                            opacity: row.held ? 0.9 : 0.55
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        QQC2.ToolButton {
                            icon.name: "go-up"
                            enabled: row.rowIndex > 0
                            onClicked: { orderModel.move(row.rowIndex, row.rowIndex - 1, 1); page.commitOrder() }
                        }
                        QQC2.ToolButton {
                            icon.name: "go-down"
                            enabled: row.rowIndex < orderModel.count - 1
                            onClicked: { orderModel.move(row.rowIndex, row.rowIndex + 1, 1); page.commitOrder() }
                        }
                    }
                }

                // MouseArea SIBLING of rowBg — anchored to row (not rowBg), so
                // it stays in place when rowBg gets reparented during drag.
                // Positioned over the handle icon visually.
                MouseArea {
                    id: dragHandleArea
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 6
                    width: Kirigami.Units.iconSizes.small + 4
                    height: Kirigami.Units.iconSizes.small + 4
                    cursorShape: Qt.SizeVerCursor
                    drag.target: rowBg
                    drag.axis: Drag.YAxis
                    onPressed: {
                        listView.dragSourceIndex = row.rowIndex
                        listView.dropTargetIndex = row.rowIndex
                    }
                    onReleased: {
                        const src = listView.dragSourceIndex
                        const tgt = listView.dropTargetIndex
                        listView.dragSourceIndex = -1
                        listView.dropTargetIndex = -1
                        rowBg.Drag.drop()
                        if (src >= 0 && tgt >= 0 && src !== tgt) {
                            orderModel.move(src, tgt, 1)
                            page.commitOrder()
                        }
                    }
                }

                // DropArea tracks the proposed drop position. We don't mutate
                // the model here — that happens on release. Items shift via
                // the `transform` binding above based on dropTargetIndex.
                DropArea {
                    anchors.fill: parent
                    onEntered: function(drag) {
                        if (!drag.source || drag.source === row) return
                        listView.dropTargetIndex = row.rowIndex
                    }
                }
            }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.largeSpacing
            Layout.bottomMargin: Kirigami.Units.smallSpacing
        }

        QQC2.CheckBox {
            id: coresCheck
            text: i18n("Show CPU cores as concentric rings")
        }
    }
}
