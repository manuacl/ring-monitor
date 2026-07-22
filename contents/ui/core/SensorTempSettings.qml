import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    required property string sensorId
    required property string sensorLabel
    required property int minC
    required property int maxC

    signal sensorIdEdited(string value)
    signal sensorLabelEdited(string value)
    signal minCEdited(int value)
    signal maxCEdited(int value)

    spacing: Kirigami.Units.smallSpacing

    QQC2.Label {
        text: qsTr("KSystemStats sensor ID")
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }

    QQC2.TextField {
        Layout.fillWidth: true
        placeholderText: qsTr("Example: lmsensors/.../temp1")
        text: root.sensorId
        onTextEdited: root.sensorIdEdited(text)
    }

    Kirigami.InlineMessage {
        Layout.fillWidth: true
        type: Kirigami.MessageType.Information
        text: qsTr("Enter a valid KSystemStats temperature sensor ID. The SENSOR metric will become available automatically when the sensor is detected.")
        visible: true
    }

    QQC2.Label {
        text: qsTr("Ring label")
    }

    QQC2.TextField {
        Layout.fillWidth: true
        placeholderText: qsTr("SENSOR")
        text: root.sensorLabel
        maximumLength: 16
        onTextEdited: root.sensorLabelEdited(text)
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        QQC2.Label {
            text: qsTr("Minimum °C:")
        }

        QQC2.SpinBox {
            editable: true
            from: -273
            to: root.maxC - 1
            value: root.minC
            onValueModified: root.minCEdited(value)
        }

        QQC2.Label {
            text: qsTr("Maximum °C:")
        }

        QQC2.SpinBox {
            editable: true
            from: root.minC + 1
            to: 1000
            value: root.maxC
            onValueModified: root.maxCEdited(value)
        }

        Item {
            Layout.fillWidth: true
        }
    }
}
