import QtQuick
import org.kde.kcmutils as KCM
import "core" as Core

// Plasma-side wrapper for the Appearance config page. All of the
// rendering lives in AppearanceBody.qml — this file's only job is to
// bridge Plasma's cfg_* magic property convention to the body's plain
// properties via `property alias` declarations.
//
// HACK: KDE bug 484541 — Plasma sets every cfg_<key> on every page,
// and Plasma 6 also generates cfg_<key>Default for the "Reset" feature.
// Placeholders for keys handled on other pages keep the journal quiet.
// See docs/config-dialog.md.

KCM.SimpleKCM {
    id: page

    // ── Bidirectional bridge: cfg_<key> ↔ body.<property> ────────────
    property alias cfg_orientation: body.orientation
    property alias cfg_textOpacity: body.textOpacity
    property alias cfg_trackOpacity: body.trackOpacity
    property alias cfg_arcOpacity: body.arcOpacity
    property alias cfg_colorTheme: body.colorTheme
    property alias cfg_colorMode: body.colorMode
    property alias cfg_customColorLight: body.customColorLight
    property alias cfg_customColorDark: body.customColorDark

    // KDE bug 484541 placeholders — keys handled on other pages and the
    // *Default variants Plasma auto-generates for "Reset to defaults".
    property var cfg_metricOrder
    property var cfg_metricOrderDefault
    property var cfg_enabledMetrics
    property var cfg_enabledMetricsDefault
    property var cfg_showCpuCores
    property var cfg_showCpuCoresDefault
    property var cfg_orientationDefault
    property var cfg_textOpacityDefault
    property var cfg_trackOpacityDefault
    property var cfg_arcOpacityDefault
    property var cfg_colorThemeDefault
    property var cfg_colorModeDefault
    property var cfg_customColorLightDefault
    property var cfg_customColorDarkDefault

    Core.AppearanceBody {
        id: body
    }
}
