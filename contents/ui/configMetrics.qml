import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import "ReorderLogic.js" as Logic

KCM.SimpleKCM {
    id: page

    property string cfg_metricOrder
    property string cfg_enabledMetrics
    property alias cfg_showCpuCores: coresCheck.checked

    // HACK: see KDE bug 484541 — Plasma sets every cfg_<key> on every page,
    // and also a cfg_<key>Default for each. Declare placeholders here for
    // the keys handled on other pages (and the Default variants of our own
    // keys) so the warnings don't spam the journal.
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

    readonly property var enabledList:
        (cfg_enabledMetrics || "").split(",").filter(function(x) { return x })

    function isEnabled(id) { return enabledList.indexOf(id) !== -1 }

    function setEnabled(id, on) {
        const arr = enabledList.filter(function(x) { return x !== id })
        if (on) arr.push(id)
        cfg_enabledMetrics = arr.join(",")
    }

    // ── Order model — mirror of cfg_metricOrder, mutable for reorder ──
    ListModel { id: orderModel }

    function currentOrder() {
        const arr = []
        for (let i = 0; i < orderModel.count; i++) arr.push(orderModel.get(i).metricId)
        return arr
    }
    function loadOrder() {
        orderModel.clear()
        const ids = (cfg_metricOrder || "").split(",").filter(function(x) { return x })
        for (let i = 0; i < ids.length; i++) {
            orderModel.append({ metricId: ids[i] })
        }
    }
    function commitOrder() {
        cfg_metricOrder = currentOrder().join(",")
    }

    onCfg_metricOrderChanged: loadOrder()
    Component.onCompleted: loadOrder()

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        QQC2.Label {
            text: i18n("Toggle metrics to display. Drag a row by the handle on the left to reorder.")
            wrapMode: Text.WordWrap
            opacity: 0.7
            Layout.fillWidth: true
        }

        DraggableList {
            id: list
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            model: orderModel
            rowHeight: Kirigami.Units.gridUnit * 2

            rowContent: Component {
                RowLayout {
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.CheckBox {
                        text: page.metricMeta[model.metricId]
                              ? page.metricMeta[model.metricId].label
                              : model.metricId
                        checked: page.isEnabled(model.metricId)
                        onClicked: page.setEnabled(model.metricId, checked)
                        Layout.minimumWidth: Kirigami.Units.gridUnit * 5
                    }

                    QQC2.Label {
                        text: page.metricMeta[model.metricId]
                              ? page.metricMeta[model.metricId].description
                              : ""
                        opacity: 0.55
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }
            }

            onReordered: function(from, to) {
                // Apply the move through the pure helper, then sync the
                // ListModel + config. Going through Logic.applyMove keeps
                // the move semantics consistent with what the tests verify.
                const next = Logic.applyMove(page.currentOrder(), from, to)
                orderModel.clear()
                for (let i = 0; i < next.length; i++) {
                    orderModel.append({ metricId: next[i] })
                }
                page.commitOrder()
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
