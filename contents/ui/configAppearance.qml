import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    // Magic property names: cfg_<key> is bound automatically by Plasma
    // to plasmoid.configuration.<key>.
    property string cfg_orientation
    property alias cfg_textOpacity: textSlider.value
    property alias cfg_trackOpacity: trackSlider.value
    property alias cfg_arcOpacity: arcSlider.value

    // HACK: declared to suppress "no property called cfg_xxx" warnings from
    // Plasma trying to set every config key on every page. See KDE bug 484541.
    property var cfg_metricOrder
    property var cfg_enabledMetrics
    property var cfg_showCpuCores

    Kirigami.FormLayout {

        RowLayout {
            Kirigami.FormData.label: i18n("Orientation:")

            QQC2.RadioButton {
                text: i18n("Horizontal")
                checked: page.cfg_orientation === "horizontal"
                onClicked: page.cfg_orientation = "horizontal"
            }
            QQC2.RadioButton {
                text: i18n("Vertical")
                checked: page.cfg_orientation === "vertical"
                onClicked: page.cfg_orientation = "vertical"
            }
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Text opacity:")
            Layout.fillWidth: true

            QQC2.Slider {
                id: textSlider
                from: 0
                to: 1
                stepSize: 0.05
                Layout.fillWidth: true
            }
            QQC2.Label {
                text: Math.round(textSlider.value * 100) + " %"
                Layout.minimumWidth: Kirigami.Units.gridUnit * 3
                horizontalAlignment: Text.AlignRight
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Track opacity:")
            Layout.fillWidth: true

            QQC2.Slider {
                id: trackSlider
                from: 0
                to: 1
                stepSize: 0.05
                Layout.fillWidth: true
            }
            QQC2.Label {
                text: Math.round(trackSlider.value * 100) + " %"
                Layout.minimumWidth: Kirigami.Units.gridUnit * 3
                horizontalAlignment: Text.AlignRight
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Arc opacity:")
            Layout.fillWidth: true

            QQC2.Slider {
                id: arcSlider
                from: 0
                to: 1
                stepSize: 0.05
                Layout.fillWidth: true
            }
            QQC2.Label {
                text: Math.round(arcSlider.value * 100) + " %"
                Layout.minimumWidth: Kirigami.Units.gridUnit * 3
                horizontalAlignment: Text.AlignRight
            }
        }
    }
}
