import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "ColorThemes.js" as ColorThemes

// Body of the Appearance config page. Owns the form layout, the
// RadioButtons, and the three opacity sliders.
//
// Bidirectional state is exposed as plain QML properties; the wrapper
// (configAppearance.qml) bridges them to Plasma's cfg_* magic via
// `property alias` declarations. The body never touches Plasmoid
// configuration directly.
//
// The platform-dependent ColorPicker arrives as an injected Component,
// and the strings go through qsTr() rather than Plasma's i18n(): both
// keep this file free of any `org.kde.*` import except Kirigami. See
// core/CLAUDE.md and docs/plasma-isolation/plan.md.

Kirigami.FormLayout {
    id: body

    // Adapter input (injected by wrapper). Surface contract: any QML
    // item with a writable `color` property and an `accepted` signal
    // fired when the user confirms a new colour. Both
    // `platforms/plasma/ColorPicker.qml` and
    // `platforms/standalone/ColorPicker.qml` honour this.
    property Component colorPickerComponent

    // Standalone-only controls (plasmashell owns the Plasma slot
    // position): docs/components.md § AppearanceBody.
    property bool windowPlacementVisible: false

    // Hidden by default (standalone SettingsDialog flips it on), same gate
    // as windowPlacementVisible: the slider is a near-no-op on Plasma where
    // the fixed frame dominates the layout. Full rationale: docs/components.md
    // § AppearanceBody.
    property bool ringSpacingVisible: false

    // Hidden by default (standalone SettingsDialog flips it on). The slider
    // is inert on Plasma (dragged frame overrides implicit size). Full rationale:
    // docs/components.md § AppearanceBody.
    property bool ringSizeVisible: false

    // ── Bridged via aliases in the wrapper (cfg_orientation ↔ body.orientation, etc.) ──
    property string orientation: "horizontal"
    property int ringSize: 180
    property int ringSpacingPercent: 7
    property string windowAnchorCorner: "top-right"
    property int windowMarginX: 0
    property int windowMarginY: 0
    property string windowScreen: ""
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
    // Background halo (#170). The values live on BackgroundSettings
    // below; aliased here so both hosts bridge them like every other key.
    property alias backgroundEnabled: backgroundSettings.backgroundEnabled
    property alias backgroundColor: backgroundSettings.backgroundColor
    property alias backgroundOpacity: backgroundSettings.backgroundOpacity
    property alias backgroundSpread: backgroundSettings.backgroundSpread
    property alias backgroundEdgeSoftness: backgroundSettings.backgroundEdgeSoftness

    // Built once at load time — the labels go through qsTr() so xgettext
    // picks them up, while ColorThemes.js stays free of i18n machinery.
    readonly property var _themeModel: ColorThemes.THEMES.map(function (t) {
        return {
            value: t.id,
            text: qsTr(t.label)
        };
    })

    // Corner values parallel the combo labels below — same order; subset of WindowPlacement.js CORNERS.
    readonly property var _cornerValues: ["top-left", "top-right", "bottom-left", "bottom-right"]
    // Re-evaluates on hot-plug. Qt.application.screens is a QQmlListProperty — array-like, not a JS Array.
    readonly property var _screenNames: {
        var screens = Qt.application.screens;
        var out = [];
        for (var i = 0; i < screens.length; i++)
            out.push(screens[i].name);
        return out;
    }

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

    // Ring size — per-ring side in pixels; range 80–800 in 20px steps.
    // docs/components.md § AppearanceBody for rationale.
    RowLayout {
        Kirigami.FormData.label: qsTr("Ring size:")
        Layout.fillWidth: true
        visible: body.ringSizeVisible

        QQC2.Slider {
            id: ringSizeSlider
            from: 80
            to: 800
            stepSize: 20
            snapMode: QQC2.Slider.SnapAlways
            value: body.ringSize
            onMoved: body.ringSize = value
            Layout.fillWidth: true
        }
        QQC2.Label {
            text: body.ringSize + " px"
            Layout.minimumWidth: Kirigami.Units.gridUnit * 3
            horizontalAlignment: Text.AlignRight
        }
    }

    // Ring spacing — gap between rings as a percent of ringSize (0–25 %).
    RowLayout {
        Kirigami.FormData.label: qsTr("Ring spacing:")
        Layout.fillWidth: true
        visible: body.ringSpacingVisible

        QQC2.Slider {
            id: ringSpacingSlider
            from: 0
            to: 25
            stepSize: 1
            snapMode: QQC2.Slider.SnapAlways
            value: body.ringSpacingPercent
            onMoved: body.ringSpacingPercent = value
            Layout.fillWidth: true
        }
        QQC2.Label {
            text: body.ringSpacingPercent + " %"
            Layout.minimumWidth: Kirigami.Units.gridUnit * 3
            horizontalAlignment: Text.AlignRight
        }
    }

    // Margin semantics: platforms/standalone/WindowPlacement.js.
    RowLayout {
        Kirigami.FormData.label: qsTr("Anchor corner:")
        Layout.fillWidth: true
        visible: body.windowPlacementVisible

        QQC2.ComboBox {
            id: anchorCornerCombo
            Layout.fillWidth: true
            // Labels parallel body._cornerValues — same order.
            // Unknown value → top-right fallback (matches WindowPlacement.js).
            model: [qsTr("Top left"), qsTr("Top right"), qsTr("Bottom left"), qsTr("Bottom right")]
            currentIndex: {
                const i = body._cornerValues.indexOf(body.windowAnchorCorner);
                return i >= 0 ? i : body._cornerValues.indexOf("top-right");
            }
            onActivated: body.windowAnchorCorner = body._cornerValues[currentIndex]
        }
    }

    RowLayout {
        Kirigami.FormData.label: qsTr("Horizontal margin:")
        Layout.fillWidth: true
        visible: body.windowPlacementVisible

        QQC2.Slider {
            id: windowMarginXSlider
            from: 0
            to: 200
            stepSize: 10
            snapMode: QQC2.Slider.SnapAlways
            value: body.windowMarginX
            onMoved: body.windowMarginX = value
            Layout.fillWidth: true
        }
        QQC2.Label {
            text: body.windowMarginX + " px"
            Layout.minimumWidth: Kirigami.Units.gridUnit * 3
            horizontalAlignment: Text.AlignRight
        }
    }

    RowLayout {
        Kirigami.FormData.label: qsTr("Vertical margin:")
        Layout.fillWidth: true
        visible: body.windowPlacementVisible

        QQC2.Slider {
            id: windowMarginYSlider
            from: 0
            to: 200
            stepSize: 10
            snapMode: QQC2.Slider.SnapAlways
            value: body.windowMarginY
            onMoved: body.windowMarginY = value
            Layout.fillWidth: true
        }
        QQC2.Label {
            text: body.windowMarginY + " px"
            Layout.minimumWidth: Kirigami.Units.gridUnit * 3
            horizontalAlignment: Text.AlignRight
        }
    }

    RowLayout {
        Kirigami.FormData.label: qsTr("Screen:")
        Layout.fillWidth: true
        visible: body.windowPlacementVisible

        QQC2.ComboBox {
            id: screenCombo
            Layout.fillWidth: true
            // Index 0 = "" (follow the window's current screen). A stored name
            // for a disconnected monitor yields index 0 WITHOUT writing the
            // store — only onActivated writes, so the name survives an unplug.
            model: [qsTr("Current screen")].concat(body._screenNames)
            currentIndex: body._screenNames.indexOf(body.windowScreen) + 1
            // Signal param + bounds: a same-frame hot-unplug can shrink
            // _screenNames under the activated index — fall back to "".
            onActivated: index => body.windowScreen = (index > 0 && index <= body._screenNames.length) ? body._screenNames[index - 1] : ""
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

    // Why the explicit light/dark overrides exist next to "follow
    // system": docs/logic-modules.md § ColorThemes.js.
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

        Loader {
            id: lightColorButton
            sourceComponent: body.colorPickerComponent
            onLoaded: {
                if (!item)
                    return;
                item.accepted.connect(function () {
                    body.customColorLight = item.color;
                });
            }
        }
        // Binding element, not an imperative `item.color = Qt.binding(…)`:
        // the ColorPicker self-assigns on accept and would clobber it.
        // See core/CLAUDE.md § Component-side gotchas.
        Binding {
            target: lightColorButton.item
            property: "color"
            value: body.customColorLight
            when: lightColorButton.item !== null
            restoreMode: Binding.RestoreBindingOrValue
        }
    }

    RowLayout {
        Kirigami.FormData.label: qsTr("Dark color:")
        visible: body.colorTheme === "custom"

        Loader {
            id: darkColorButton
            sourceComponent: body.colorPickerComponent
            onLoaded: {
                if (!item)
                    return;
                item.accepted.connect(function () {
                    body.customColorDark = item.color;
                });
            }
        }
        Binding {
            target: darkColorButton.item
            property: "color"
            value: body.customColorDark
            when: darkColorButton.item !== null
            restoreMode: Binding.RestoreBindingOrValue
        }
    }

    Item {
        Kirigami.FormData.isSection: true
    }

    // "system" default vs "custom" pair rationale: docs/components.md § AppearanceBody.
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

        Loader {
            id: lightTextColorButton
            sourceComponent: body.colorPickerComponent
            onLoaded: {
                if (!item)
                    return;
                item.accepted.connect(function () {
                    body.customTextColorLight = item.color;
                });
            }
        }
        Binding {
            target: lightTextColorButton.item
            property: "color"
            value: body.customTextColorLight
            when: lightTextColorButton.item !== null
            restoreMode: Binding.RestoreBindingOrValue
        }
    }

    RowLayout {
        Kirigami.FormData.label: qsTr("Dark text color:")
        visible: body.textColorMode === "custom"

        Loader {
            id: darkTextColorButton
            sourceComponent: body.colorPickerComponent
            onLoaded: {
                if (!item)
                    return;
                item.accepted.connect(function () {
                    body.customTextColorDark = item.color;
                });
            }
        }
        Binding {
            target: darkTextColorButton.item
            property: "color"
            value: body.customTextColorDark
            when: darkTextColorButton.item !== null
            restoreMode: Binding.RestoreBindingOrValue
        }
    }

    Item {
        Kirigami.FormData.isSection: true
    }

    BackgroundSettings {
        id: backgroundSettings
        Kirigami.FormData.label: qsTr("Background:")
        Kirigami.FormData.labelAlignment: Qt.AlignTop
        Layout.fillWidth: true
        colorPickerComponent: body.colorPickerComponent
    }

    // ── Test hooks ──────────────────────────────────────────────────
    readonly property alias _ringSizeSlider: ringSizeSlider
    readonly property alias _ringSpacingSlider: ringSpacingSlider
    readonly property alias _anchorCornerCombo: anchorCornerCombo
    readonly property alias _windowMarginXSlider: windowMarginXSlider
    readonly property alias _windowMarginYSlider: windowMarginYSlider
    readonly property alias _screenCombo: screenCombo
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
