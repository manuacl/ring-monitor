import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Config controls for the ring text: font family, weight and size scale.
// Rendered by core/Ring.qml (see docs/components.md § Ring → Font).
//
// Extracted from AppearanceBody rather than written inline: that file is
// at the 500-line cap. Same contract as BackgroundSettings — values come
// in as properties, the controls write them back, and the host
// (AppearanceBody → the Plasma cfg_* aliases or the standalone dialog's
// bridge map) persists them.

ColumnLayout {
    id: fontSettings

    // "" = follow the system font (Ring falls back to the application font).
    property string fontFamily: ""
    // Qt font weight of the big centre values; 300 = Font.Light, the historic look.
    property int fontWeight: 300
    property int fontScalePercent: 100
    // Installed families; a property (not read inline) so tests can inject a
    // deterministic list instead of depending on the fonts of the test box.
    property var availableFamilies: Qt.fontFamilies()

    // Parallel arrays (a flat string array survives qmlformat inline, an
    // object model would balloon — see the 500-line note in CLAUDE.md).
    readonly property var _weightLabels: [qsTr("Thin"), qsTr("Light"), qsTr("Regular"), qsTr("Medium"), qsTr("Semibold"), qsTr("Bold")]
    readonly property var _weightValues: [100, 300, 400, 500, 600, 700]
    // Index 0 = "" (system font); the rest are the installed families.
    readonly property var _families: [qsTr("System default")].concat(availableFamilies)

    spacing: Kirigami.Units.smallSpacing

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        QQC2.Label {
            text: qsTr("Family:")
        }

        QQC2.ComboBox {
            objectName: "fontFamilyCombo"
            Layout.fillWidth: true
            model: fontSettings._families
            // A stored family that isn't installed on this machine shows
            // "System default" WITHOUT writing the store — only onActivated
            // writes, so the name survives (same rule as the Screen combo).
            currentIndex: Math.max(0, fontSettings._families.indexOf(fontSettings.fontFamily))
            onActivated: index => fontSettings.fontFamily = index > 0 ? fontSettings._families[index] : ""
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        QQC2.Label {
            text: qsTr("Value weight:")
        }

        QQC2.ComboBox {
            objectName: "fontWeightCombo"
            Layout.fillWidth: true
            model: fontSettings._weightLabels
            // Unknown stored weight (hand-edited config) → the default (Light).
            currentIndex: {
                const i = fontSettings._weightValues.indexOf(fontSettings.fontWeight);
                return i >= 0 ? i : fontSettings._weightValues.indexOf(300);
            }
            onActivated: index => fontSettings.fontWeight = fontSettings._weightValues[index]
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        QQC2.Label {
            text: qsTr("Size:")
        }

        QQC2.Slider {
            objectName: "fontScaleSlider"
            from: 50
            to: 150
            stepSize: 5
            snapMode: QQC2.Slider.SnapAlways
            value: fontSettings.fontScalePercent
            onMoved: fontSettings.fontScalePercent = value
            Layout.fillWidth: true
        }
        QQC2.Label {
            text: fontSettings.fontScalePercent + " %"
            Layout.minimumWidth: Kirigami.Units.gridUnit * 3
            horizontalAlignment: Text.AlignRight
        }
    }
}
