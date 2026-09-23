import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "BackgroundStyle.js" as BackgroundStyle

// Config controls for the optional widget background (issue #170):
// on/off, colour, opacity and the edge the plate fades out toward.
// Rendered by core/WidgetBackground.qml.
//
// Extracted from AppearanceBody rather than written inline: that file
// was already at the 500-line cap. Stateless in the same sense as the
// rest of the config bodies — values come in as properties, the
// controls write them back, and the host (AppearanceBody → the Plasma
// cfg_* aliases or the standalone dialog's bridge map) persists them.
//
// The colour picker is platform-specific, so it arrives as a Component
// the parent injects — same contract as AppearanceBody's own pickers
// (a writable `color` plus an `accepted` signal).

ColumnLayout {
    id: backgroundSettings

    property bool backgroundEnabled: false
    property color backgroundColor: "#000000"
    property real backgroundOpacity: 0.5
    property int backgroundSpread: 0
    property int backgroundEdgeSoftness: 0
    property Component colorPickerComponent

    spacing: Kirigami.Units.smallSpacing

    QQC2.CheckBox {
        objectName: "backgroundEnabledCheck"
        text: qsTr("Draw a background behind the rings")
        checked: backgroundSettings.backgroundEnabled
        onToggled: backgroundSettings.backgroundEnabled = checked
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        visible: backgroundSettings.backgroundEnabled

        QQC2.Label {
            text: qsTr("Color:")
        }

        Loader {
            id: backgroundColorButton
            objectName: "backgroundColorButton"
            sourceComponent: backgroundSettings.colorPickerComponent
            onLoaded: {
                if (!item)
                    return;
                item.accepted.connect(function () {
                    backgroundSettings.backgroundColor = item.color;
                });
            }
        }
        // Binding element, not an imperative `item.color = Qt.binding(…)`:
        // the ColorPicker self-assigns on accept and would clobber it.
        // See core/CLAUDE.md § Component-side gotchas.
        Binding {
            target: backgroundColorButton.item
            property: "color"
            value: backgroundSettings.backgroundColor
            when: backgroundColorButton.item !== null
            restoreMode: Binding.RestoreBindingOrValue
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        visible: backgroundSettings.backgroundEnabled

        QQC2.Label {
            text: qsTr("Opacity:")
        }

        QQC2.Slider {
            objectName: "backgroundOpacitySlider"
            from: 0
            to: 1
            stepSize: 0.05
            value: backgroundSettings.backgroundOpacity
            onMoved: backgroundSettings.backgroundOpacity = value
            Layout.fillWidth: true
        }
        QQC2.Label {
            text: Math.round(backgroundSettings.backgroundOpacity * 100) + " %"
            Layout.minimumWidth: Kirigami.Units.gridUnit * 3
            horizontalAlignment: Text.AlignRight
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        visible: backgroundSettings.backgroundEnabled

        QQC2.Label {
            text: qsTr("Soft edges:")
        }

        QQC2.Slider {
            objectName: "backgroundEdgeSoftnessSlider"
            from: 0
            to: BackgroundStyle.MAX_FEATHER_PERCENT
            stepSize: 1
            snapMode: QQC2.Slider.SnapAlways
            value: backgroundSettings.backgroundEdgeSoftness
            onMoved: backgroundSettings.backgroundEdgeSoftness = value
            Layout.fillWidth: true
        }
        QQC2.Label {
            text: backgroundSettings.backgroundEdgeSoftness + " %"
            Layout.minimumWidth: Kirigami.Units.gridUnit * 3
            horizontalAlignment: Text.AlignRight
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        visible: backgroundSettings.backgroundEnabled

        QQC2.Label {
            text: qsTr("Halo size:")
        }

        QQC2.Slider {
            objectName: "backgroundSpreadSlider"
            from: 0
            to: BackgroundStyle.MAX_SPREAD_PERCENT
            stepSize: 1
            snapMode: QQC2.Slider.SnapAlways
            value: backgroundSettings.backgroundSpread
            onMoved: backgroundSettings.backgroundSpread = value
            Layout.fillWidth: true
        }
        QQC2.Label {
            text: backgroundSettings.backgroundSpread + " %"
            Layout.minimumWidth: Kirigami.Units.gridUnit * 3
            horizontalAlignment: Text.AlignRight
        }
    }
}
