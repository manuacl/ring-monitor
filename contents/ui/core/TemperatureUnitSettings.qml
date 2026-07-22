import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

RowLayout {
    id: root

    required property string tempUnit

    signal tempUnitEdited(string value)

    spacing: Kirigami.Units.smallSpacing

    QQC2.Label {
        text: qsTr("Temperature unit:")
    }

    QQC2.RadioButton {
        id: tempUnitAuto
        text: qsTr("Auto")
        checked: root.tempUnit === "auto"
        onClicked: root.tempUnitEdited("auto")
    }

    QQC2.RadioButton {
        id: tempUnitCelsius
        text: qsTr("°C")
        checked: root.tempUnit === "celsius"
        onClicked: root.tempUnitEdited("celsius")
    }

    QQC2.RadioButton {
        id: tempUnitFahrenheit
        text: qsTr("°F")
        checked: root.tempUnit === "fahrenheit"
        onClicked: root.tempUnitEdited("fahrenheit")
    }

    Item {
        Layout.fillWidth: true
    }
}
