import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "MetricsCatalog.js" as Catalog

// The sensorTemp sub-option: sensor-ID and ring-label text fields plus
// min/max spinboxes. Stateless: takes the four values as required
// properties and emits a dedicated signal per edit.
//
// The bounds are STORED in °C (the sensor reports Celsius kernel-side,
// and the ring maps that range onto the sweep) but DISPLAYED/EDITED in
// the user's temperature unit — the labels and spinbox values follow
// `tempUnit`, resolved like the rings do (Catalog.resolveTempMode:
// "auto" → the system locale's measurement system).
ColumnLayout {
    id: root

    required property string sensorId
    required property string sensorLabel
    required property int minC
    required property int maxC
    // "auto" / "celsius" / "fahrenheit" — same value as the page's
    // TemperatureUnitSettings radios.
    property string tempUnit: "auto"

    signal sensorIdEdited(string value)
    signal sensorLabelEdited(string value)
    signal minCEdited(int value)
    signal maxCEdited(int value)

    readonly property string _mode: Catalog.resolveTempMode(root.tempUnit, Qt.locale().measurementSystem)
    readonly property string _unitSuffix: root._mode === "fahrenheit" ? "°F" : "°C"

    // int °C storage ↔ int display-unit spinbox values. The °F path
    // rounds, so some consecutive °F values collapse to the same °C
    // (one Up step can move the display by 2 °F) — inherent to the
    // integer storage, harmless for a display-range bound.
    function _toDisplay(celsius) {
        return root._mode === "fahrenheit" ? Math.round(celsius * 9 / 5 + 32) : celsius;
    }

    function _fromDisplay(value) {
        return root._mode === "fahrenheit" ? Math.round((value - 32) * 5 / 9) : value;
    }

    spacing: Kirigami.Units.smallSpacing

    QQC2.Label {
        text: qsTr("KSystemStats sensor ID")
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }

    QQC2.TextField {
        Layout.fillWidth: true
        objectName: "sensorIdField"
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
        objectName: "sensorLabelField"
        placeholderText: qsTr("SENSOR")
        text: root.sensorLabel
        maximumLength: 16
        onTextEdited: root.sensorLabelEdited(text)
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        QQC2.Label {
            objectName: "minCLabel"
            text: qsTr("Minimum %1:").arg(root._unitSuffix)
        }

        // Spinboxes work in the DISPLAY unit; the °C bounds cross-clamp
        // (min can never reach max and vice versa) before conversion so
        // the stored range stays non-degenerate.
        QQC2.SpinBox {
            objectName: "minCSpinBox"
            editable: true
            from: root._toDisplay(-50)
            to: root._toDisplay(root.maxC - 1)
            value: root._toDisplay(root.minC)
            onValueModified: root.minCEdited(root._fromDisplay(value))
        }

        QQC2.Label {
            objectName: "maxCLabel"
            text: qsTr("Maximum %1:").arg(root._unitSuffix)
        }

        QQC2.SpinBox {
            objectName: "maxCSpinBox"
            editable: true
            from: root._toDisplay(root.minC + 1)
            to: root._toDisplay(250)
            value: root._toDisplay(root.maxC)
            onValueModified: root.maxCEdited(root._fromDisplay(value))
        }

        Item {
            Layout.fillWidth: true
        }
    }
}
