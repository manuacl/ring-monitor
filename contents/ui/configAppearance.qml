import QtQuick
import "core" as Core
import "platforms/plasma" as Platform

// Plasma-side wrapper for the Appearance config page. All of the
// rendering lives in AppearanceBody.qml — this file's only job is to
// bridge Plasma's cfg_* magic property convention to the body's plain
// properties via `property alias` declarations. The KDE-484541
// placeholders for keys handled on other pages come from the
// PlaceholderKCM base.

Platform.PlaceholderKCM {
    id: page

    // ── Bidirectional bridge: cfg_<key> ↔ body.<property> ────────────
    property alias cfg_orientation: body.orientation
    property alias cfg_ringSize: body.ringSize
    property alias cfg_ringSpacingPercent: body.ringSpacingPercent
    property alias cfg_windowAnchorCorner: body.windowAnchorCorner
    property alias cfg_windowMarginX: body.windowMarginX
    property alias cfg_windowMarginY: body.windowMarginY
    property alias cfg_textOpacity: body.textOpacity
    property alias cfg_trackOpacity: body.trackOpacity
    property alias cfg_arcOpacity: body.arcOpacity
    property alias cfg_colorTheme: body.colorTheme
    property alias cfg_colorMode: body.colorMode
    property alias cfg_customColorLight: body.customColorLight
    property alias cfg_customColorDark: body.customColorDark
    property alias cfg_textColorMode: body.textColorMode
    property alias cfg_customTextColorLight: body.customTextColorLight
    property alias cfg_customTextColorDark: body.customTextColorDark

    // ColorPicker is platform-specific (Plasma wraps KQuickControls.ColorButton,
    // standalone wraps a plain Button + QtQuick.Dialogs.ColorDialog).
    // AppearanceBody takes the wrapped widget as a Component prop so it
    // stays free of any Platform-namespaced import — see core/CLAUDE.md
    // § "Plasma isolation is the load-bearing invariant".
    Component {
        id: colorPickerComponent
        Platform.ColorPicker {}
    }

    Core.AppearanceBody {
        id: body
        colorPickerComponent: colorPickerComponent
    }
}
