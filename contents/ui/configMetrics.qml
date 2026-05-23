import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    property string cfg_enabledMetrics
    property alias cfg_showCpuCores: coresCheck.checked

    // Master list of supported metrics. Order here is the display order in the
    // widget. Extend this list as new metrics get backed by Ring rendering.
    readonly property var supportedMetrics: [
        { id: "cpu",  label: "CPU",     description: "Utilisation globale du processeur" },
        { id: "ram",  label: "RAM",     description: "Mémoire vive utilisée" },
        { id: "swap", label: "SWAP",    description: "Swap utilisé" },
        { id: "gpu",  label: "GPU",     description: "Utilisation du GPU" },
        { id: "disk", label: "Disque",  description: "Espace disque utilisé (toutes partitions)" },
    ]

    function isEnabled(id) {
        return ("," + (cfg_enabledMetrics || "") + ",").indexOf("," + id + ",") !== -1
    }

    function toggle(id) {
        const arr = (cfg_enabledMetrics || "").split(",").filter(function(x) { return x && x !== id })
        if (!isEnabled(id)) arr.push(id)
        // Re-order according to supportedMetrics master order
        const order = supportedMetrics.map(function(m) { return m.id })
        arr.sort(function(a, b) { return order.indexOf(a) - order.indexOf(b) })
        cfg_enabledMetrics = arr.join(",")
    }

    Kirigami.FormLayout {
        anchors.fill: parent

        Repeater {
            model: page.supportedMetrics

            delegate: RowLayout {
                Kirigami.FormData.label: modelData.label + " :"
                Layout.fillWidth: true

                QQC2.CheckBox {
                    checked: page.isEnabled(modelData.id)
                    onClicked: page.toggle(modelData.id)
                    text: modelData.description
                }
            }
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            id: coresCheck
            Kirigami.FormData.label: i18n("CPU cœurs :")
            text: i18n("Afficher les cœurs en anneaux concentriques")
        }
    }
}
