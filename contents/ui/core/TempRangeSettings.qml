import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "MetricsCatalog.js" as Catalog

// Reusable min/max editor for a temperature ring's custom bounds
// (issue #164, section 5): shared by sensorTemp (via SensorTempSettings)
// and the cpuTemp/gpuTemp rows. Stateless: values come in as properties
// and every edit emits a dedicated signal.
//
// The bounds are STORED in °C (the ring maps that range onto the sweep)
// but DISPLAYED/EDITED in the user's temperature unit — the labels and
// spinbox values follow `tempUnit`, resolved like the rings do
// (Catalog.resolveTempMode: "auto" → the system locale's measurement
// system).
ColumnLayout {
    id: root

    required property int minC
    required property int maxC
    // "auto" / "celsius" / "fahrenheit" — same value as the page's
    // TemperatureUnitSettings radios.
    property string tempUnit: "auto"

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

    QQC2.Label {
        objectName: "boundsHintLabel"
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: 0.7
        font: Kirigami.Theme.smallFont
        text: qsTr("These bounds map the sensor range onto the ring's empty-to-full sweep — they are not an alarm threshold.")
    }
}
