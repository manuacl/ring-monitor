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

            displaced: Transition {
                NumberAnimation { properties: "y"; duration: 180; easing.type: Easing.OutCubic }
            }

            delegate: Item {
                id: row
                width: ListView.view.width
                height: Kirigami.Units.gridUnit * 2

                property bool held: false
                property int rowIndex: index
                property string metricId: model.metricId

                Rectangle {
                    id: rowBg
                    anchors.fill: parent
                    radius: 4
                    color: row.held ? Kirigami.Theme.highlightColor : (mouseHover.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent")
                    border.width: row.held ? 0 : 1
                    border.color: Qt.rgba(1, 1, 1, 0.08)

                    Drag.active: row.held
                    Drag.source: row
                    Drag.hotSpot.x: width / 2
                    Drag.hotSpot.y: height / 2

                    states: State {
                        when: row.held
                        ParentChange { target: rowBg; parent: listView }
                        // AnchorChanges doesn't support `anchors.fill` directly:
                        // undo each anchor that `anchors.fill: parent` sets implicitly.
                        AnchorChanges {
                            target: rowBg
                            anchors.top: undefined
                            anchors.bottom: undefined
                            anchors.left: undefined
                            anchors.right: undefined
                        }
                    }

                    HoverHandler { id: mouseHover }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        spacing: Kirigami.Units.smallSpacing

                        Kirigami.Icon {
                            source: "transform-move"
                            implicitWidth: Kirigami.Units.iconSizes.small
                            implicitHeight: Kirigami.Units.iconSizes.small
                            opacity: 0.5

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.SizeVerCursor
                                drag.target: rowBg
                                drag.axis: Drag.YAxis
                                onPressed: row.held = true
                                onReleased: {
                                    row.held = false
                                    rowBg.Drag.drop()
                                }
                            }
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

                DropArea {
                    anchors.fill: parent
                    onEntered: function(drag) {
                        const from = drag.source.rowIndex
                        const to = row.rowIndex
                        if (from !== to && from >= 0 && to >= 0) {
                            orderModel.move(from, to, 1)
                            page.commitOrder()
                        }
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
