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

    // "Follow system" resolves via Qt.locale().measurementSystem in
    // MainContent (Imperial-US → °F, everything else → °C — see
    // Catalog.resolveTempMode).
    QQC2.RadioButton {
        id: tempUnitAuto
        objectName: "tempUnitAutoRadio"
        text: qsTr("Follow system")
        checked: root.tempUnit === "auto"
        onClicked: root.tempUnitEdited("auto")
    }

    QQC2.RadioButton {
        id: tempUnitCelsius
        objectName: "tempUnitCelsiusRadio"
        text: qsTr("Celsius")
        checked: root.tempUnit === "celsius"
        onClicked: root.tempUnitEdited("celsius")
    }

    QQC2.RadioButton {
        id: tempUnitFahrenheit
        objectName: "tempUnitFahrenheitRadio"
        text: qsTr("Fahrenheit")
        checked: root.tempUnit === "fahrenheit"
        onClicked: root.tempUnitEdited("fahrenheit")
    }

    Item {
        Layout.fillWidth: true
    }
}
