import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "ColorThemes.js" as ColorThemes
import "../platforms/plasma" as Platform

// Body of the Appearance config page. Owns the form layout, the
// RadioButtons, and the three opacity sliders.
//
// Bidirectional state is exposed as plain QML properties; the wrapper
// (configAppearance.qml) bridges them to Plasma's cfg_* magic via
// `property alias` declarations. The body never touches Plasmoid
// configuration directly.
//
// i18n strings use qsTr() rather than Plasma's i18n() — Qt's
// translation framework works in both the Plasma applet runtime and
// a future standalone build, while i18n() requires KF6 runtime. See
// docs/plasma-isolation/plan.md.

Kirigami.FormLayout {
    id: body

    // ── Bridged via aliases in the wrapper (cfg_orientation ↔ body.orientation, etc.) ──
    property string orientation: "horizontal"
    property real textOpacity: 1.0
    property real trackOpacity: 0.15
    property real arcOpacity: 1.0
    property string colorTheme: "system"
    property string colorMode: "auto"
    property color customColorLight: "#3daee9"
    property color customColorDark: "#3daee9"
    property string textColorMode: "system"
    property color customTextColorLight: "#232629"
    property color customTextColorDark: "#fcfcfc"

    // Built once at load time — the labels go through qsTr() so xgettext
    // picks them up, while ColorThemes.js stays free of i18n machinery.
    readonly property var _themeModel: ColorThemes.THEMES.map(function (t) {
        return {
            value: t.id,
            text: qsTr(t.label)
        };
    })

    RowLayout {
        Kirigami.FormData.label: qsTr("Orientation:")

        QQC2.RadioButton {
            text: qsTr("Horizontal")
            checked: body.orientation === "horizontal"
            onClicked: body.orientation = "horizontal"
        }
        QQC2.RadioButton {
            text: qsTr("Vertical")
            checked: body.orientation === "vertical"
            onClicked: body.orientation = "vertical"
        }
    }

    Item {
        Kirigami.FormData.isSection: true
    }

    RowLayout {
        Kirigami.FormData.label: qsTr("Text opacity:")
        Layout.fillWidth: true

        QQC2.Slider {
            id: textSlider
            from: 0
            to: 1
            stepSize: 0.05
            value: body.textOpacity
            onMoved: body.textOpacity = value
            Layout.fillWidth: true
        }
        QQC2.Label {
            text: Math.round(body.textOpacity * 100) + " %"
            Layout.minimumWidth: Kirigami.Units.gridUnit * 3
            horizontalAlignment: Text.AlignRight
        }
    }

    RowLayout {
        Kirigami.FormData.label: qsTr("Track opacity:")
        Layout.fillWidth: true

        QQC2.Slider {
            id: trackSlider
            from: 0
            to: 1
            stepSize: 0.05
            value: body.trackOpacity
            onMoved: body.trackOpacity = value
            Layout.fillWidth: true
        }
        QQC2.Label {
            text: Math.round(body.trackOpacity * 100) + " %"
            Layout.minimumWidth: Kirigami.Units.gridUnit * 3
            horizontalAlignment: Text.AlignRight
        }
    }

    RowLayout {
        Kirigami.FormData.label: qsTr("Arc opacity:")
        Layout.fillWidth: true

        QQC2.Slider {
            id: arcSlider
            from: 0
            to: 1
            stepSize: 0.05
            value: body.arcOpacity
            onMoved: body.arcOpacity = value
            Layout.fillWidth: true
        }
        QQC2.Label {
            text: Math.round(body.arcOpacity * 100) + " %"
            Layout.minimumWidth: Kirigami.Units.gridUnit * 3
            horizontalAlignment: Text.AlignRight
        }
    }

    Item {
        Kirigami.FormData.isSection: true
    }

    QQC2.ComboBox {
        id: themeCombo
        Kirigami.FormData.label: qsTr("Color theme:")
        model: body._themeModel
        valueRole: "value"
        textRole: "text"
        currentIndex: Math.max(0, ColorThemes.THEMES.findIndex(function (t) {
            return t.id === body.colorTheme;
        }))
        onActivated: body.colorTheme = currentValue
    }

    // Auto follows the system color scheme via Qt.styleHints
    // (Theme.qml subscribes to colorSchemeChanged). The explicit
    // Always light / Always dark overrides are the escape hatch for
    // setups where plasmashell does not propagate the scheme change
    // live to running panel widgets — Vapor and other custom Plasma
    // look-and-feel themes notably exhibit that behaviour.
    RowLayout {
        Kirigami.FormData.label: qsTr("Mode:")
        visible: body.colorTheme !== "system"

        QQC2.RadioButton {
            id: modeAuto
            text: qsTr("Follow system")
            checked: body.colorMode === "auto"
            onClicked: body.colorMode = "auto"
        }
        QQC2.RadioButton {
            id: modeLight
            text: qsTr("Always light")
            checked: body.colorMode === "light"
            onClicked: body.colorMode = "light"
        }
        QQC2.RadioButton {
            id: modeDark
            text: qsTr("Always dark")
            checked: body.colorMode === "dark"
            onClicked: body.colorMode = "dark"
        }
    }

    RowLayout {
        Kirigami.FormData.label: qsTr("Light color:")
        visible: body.colorTheme === "custom"

        Platform.ColorPicker {
            id: lightColorButton
            color: body.customColorLight
            onAccepted: body.customColorLight = color
        }
    }

    RowLayout {
        Kirigami.FormData.label: qsTr("Dark color:")
        visible: body.colorTheme === "custom"

        Platform.ColorPicker {
            id: darkColorButton
            color: body.customColorDark
            onAccepted: body.customColorDark = color
        }
    }

    Item {
        Kirigami.FormData.isSection: true
    }

    // Text color: "system" follows Kirigami.Theme.textColor (the default
    // — pushes users toward the neutral gray that fits the "anneaux
    // modernes épurés" aesthetic). "custom" exposes a L/D pair gated by
    // the same colorMode (auto/light/dark) used by the ring color, so a
    // user on a transparent panel or in standalone mode can pin the
    // text to whatever reads best against their wallpaper.
    RowLayout {
        Kirigami.FormData.label: qsTr("Text color:")

        QQC2.RadioButton {
            id: textColorSystem
            text: qsTr("System")
            checked: body.textColorMode === "system"
            onClicked: body.textColorMode = "system"
        }
        QQC2.RadioButton {
            id: textColorCustom
            text: qsTr("Custom")
            checked: body.textColorMode === "custom"
            onClicked: body.textColorMode = "custom"
        }
    }

    RowLayout {
        Kirigami.FormData.label: qsTr("Light text color:")
        visible: body.textColorMode === "custom"

        Platform.ColorPicker {
            id: lightTextColorButton
            color: body.customTextColorLight
            onAccepted: body.customTextColorLight = color
        }
    }

    RowLayout {
        Kirigami.FormData.label: qsTr("Dark text color:")
        visible: body.textColorMode === "custom"

        Platform.ColorPicker {
            id: darkTextColorButton
            color: body.customTextColorDark
            onAccepted: body.customTextColorDark = color
        }
    }

    // ── Test hooks ──────────────────────────────────────────────────
    readonly property alias _textSlider: textSlider
    readonly property alias _trackSlider: trackSlider
    readonly property alias _arcSlider: arcSlider
    readonly property alias _themeCombo: themeCombo
    readonly property alias _modeAuto: modeAuto
    readonly property alias _modeLight: modeLight
    readonly property alias _modeDark: modeDark
    readonly property alias _lightColorButton: lightColorButton
    readonly property alias _darkColorButton: darkColorButton
    readonly property alias _textColorSystem: textColorSystem
    readonly property alias _textColorCustom: textColorCustom
    readonly property alias _lightTextColorButton: lightTextColorButton
    readonly property alias _darkTextColorButton: darkTextColorButton
}
