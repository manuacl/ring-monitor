import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    // Magic property names: cfg_<key> is bound automatically by Plasma
    // to plasmoid.configuration.<key>.
    property alias cfg_textOpacity: textSlider.value
    property alias cfg_trackOpacity: trackSlider.value
    property alias cfg_arcOpacity: arcSlider.value

    Kirigami.FormLayout {
        anchors.fill: parent

        RowLayout {
            Kirigami.FormData.label: i18n("Opacité du texte :")
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
            Kirigami.FormData.label: i18n("Opacité du fond des jauges :")
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
            Kirigami.FormData.label: i18n("Opacité des jauges :")
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
