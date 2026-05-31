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
// The ColorPicker control is platform-dependent (Plasma wraps
// KQuickControls.ColorButton, standalone wraps a plain Button +
// QtQuick.Dialogs.ColorDialog), so the body takes it as a Component
// the wrapper injects. Keeps `core/` free of any `org.kde.*` import
// except Kirigami — the platform isolation invariant documented in
// `core/CLAUDE.md`.
//
// i18n strings use qsTr() rather than Plasma's i18n() — Qt's
// translation framework works in both the Plasma applet runtime and
// a future standalone build, while i18n() requires KF6 runtime. See
// docs/plasma-isolation/plan.md.

Kirigami.FormLayout {
    id: body

    // Adapter input (injected by wrapper). Surface contract: any QML
    // item with a writable `color` property and an `accepted` signal
    // fired when the user confirms a new colour. Both
    // `platforms/plasma/ColorPicker.qml` and
    // `platforms/standalone/ColorPicker.qml` honour this.
    property Component colorPickerComponent

    // The window-placement controls (anchor corner + per-axis margins)
    // are only consumed by the standalone Window anchoring code
    // (platforms/standalone/Main.qml). Inside a Plasma panel the slot
    // position is set by plasmashell, so they are dead UI there — hide
    // by default, and let the standalone SettingsDialog flip them on.
    // Same pattern as AboutBody's `autostartAvailable`.
    property bool windowPlacementVisible: false

    // Hidden by default (standalone SettingsDialog flips it on), same gate
    // as windowPlacementVisible: the slider is a near-no-op on Plasma where
    // the fixed frame dominates the layout. Full rationale: docs/components.md
    // § AppearanceBody.
    property bool ringSpacingVisible: false

    // Hidden by default (standalone SettingsDialog flips it on). `ringSize`
    // drives the rings' implicit size, but on the Plasma desktop containment
    // the user sizes the widget by dragging the frame — which overrides the
    // implicit size — so the slider looks like it does nothing once placed.
    // Unlike ringSpacing/window-placement, the value stays bound (not hardcoded)
    // on Plasma: it's a legitimate implicit size, just frame-overridden, not
    // an actively-wrong value. Standalone (frameless auto-sized window) is the
    // host where the slider has visible effect.
    property bool ringSizeVisible: false

    // ── Bridged via aliases in the wrapper (cfg_orientation ↔ body.orientation, etc.) ──
    property string orientation: "horizontal"
    property int ringSize: 180
    property int ringSpacingPercent: 7
    property string windowAnchorCorner: "top-right"
    property int windowMarginX: 0
    property int windowMarginY: 0
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

    // The four standalone-window anchor corner values, parallel to the
    // combo's qsTr() label list below — keep both in the same order. Must
    // stay a subset of platforms/standalone/WindowPlacement.js `CORNERS`
    // (a flat string array so qmlformat keeps it inline; an object {value,
    // text} model would expand past the 500-line cap).
    readonly property var _cornerValues: ["top-left", "top-right", "bottom-left", "bottom-right"]

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

    // Ring size — the per-ring side in pixels. The standalone window
    // is frameless and transparent, so the user only ever sees the
    // rings themselves; the container auto-sizes around them
    // (`ringSize × count + spacings` along the stack axis). On Plasma
    // the panel container may stretch / shrink the widget regardless
    // of this setting. Range 80-800 in 20px steps.
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

    // Ring spacing — gap between rings as a percent of ringSize. 0%
    // makes the rings touch; the historic visual default (12px at
    // ringSize=180) corresponds to 7%. Stepping at 1% keeps the
    // slider feel of a "fine" adjustment vs the bigger ringSize one.
    // Whole row hidden via `ringSpacingVisible` on Plasma (the
    // standalone SettingsDialog flips it on) — see the docblock above.
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

    // Window placement — anchor corner + per-axis inset from that
    // corner's edges. Standalone-only (Plasma slot position is
    // plasmashell's job), so hidden via `windowPlacementVisible`.
    // Margin semantics: platforms/standalone/WindowPlacement.js.
    RowLayout {
        Kirigami.FormData.label: qsTr("Anchor corner:")
        Layout.fillWidth: true
        visible: body.windowPlacementVisible

        QQC2.ComboBox {
            id: anchorCornerCombo
            Layout.fillWidth: true
            // Labels parallel body._cornerValues — same order.
            model: [qsTr("Top left"), qsTr("Top right"), qsTr("Bottom left"), qsTr("Bottom right")]
            currentIndex: Math.max(0, body._cornerValues.indexOf(body.windowAnchorCorner))
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
        // Drive the swatch via a Binding element, NOT an imperative
        // `item.color = Qt.binding(...)`: the ColorPicker self-assigns
        // `color = selectedColor` on accept, which clobbers an imperative
        // binding. See core/CLAUDE.md § Component-side gotchas.
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

    // ── Test hooks ──────────────────────────────────────────────────
    readonly property alias _ringSizeSlider: ringSizeSlider
    readonly property alias _ringSpacingSlider: ringSpacingSlider
    readonly property alias _anchorCornerCombo: anchorCornerCombo
    readonly property alias _windowMarginXSlider: windowMarginXSlider
    readonly property alias _windowMarginYSlider: windowMarginYSlider
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
