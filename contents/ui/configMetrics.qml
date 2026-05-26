import QtQuick
import org.kde.kcmutils as KCM
import "platforms/plasma" as Platform
import "core" as Core

// Plasma-side wrapper for the Metrics config page. All of the
// rendering, the orderModel, and the toggle/reorder logic live in
// MetricsBody.qml — this file's only job is to bridge Plasma's cfg_*
// magic property convention to the body's plain properties via
// `property alias` declarations.
//
// HACK: KDE bug 484541 — Plasma sets every cfg_<key> on every page,
// and Plasma 6 also generates cfg_<key>Default for the "Reset" feature.
// Placeholders for keys handled on other pages keep the journal quiet.
// See docs/config-dialog.md.

KCM.SimpleKCM {
    id: page

    // ── Bidirectional bridge: cfg_<key> ↔ body.<property> ────────────
    property alias cfg_metricOrder: body.metricOrderCsv
    property alias cfg_enabledMetrics: body.enabledMetricsCsv
    property alias cfg_showCpuCores: body.showCpuCores
    property alias cfg_mergeCpuTemp: body.mergeCpuTemp
    property alias cfg_mergeGpuTemp: body.mergeGpuTemp
    property alias cfg_tempUnit: body.tempUnit

    // KDE bug 484541 placeholders — keys handled on the Appearance page
    // and the *Default variants Plasma auto-generates for "Reset".
    property var cfg_orientation
    property var cfg_orientationDefault
    property var cfg_ringSize
    property var cfg_ringSizeDefault
    property var cfg_ringSpacingPercent
    property var cfg_ringSpacingPercentDefault
    property var cfg_windowMargin
    property var cfg_windowMarginDefault
    property var cfg_textOpacity
    property var cfg_textOpacityDefault
    property var cfg_trackOpacity
    property var cfg_trackOpacityDefault
    property var cfg_arcOpacity
    property var cfg_arcOpacityDefault
    property var cfg_colorTheme
    property var cfg_colorThemeDefault
    property var cfg_colorMode
    property var cfg_colorModeDefault
    property var cfg_customColorLight
    property var cfg_customColorLightDefault
    property var cfg_customColorDark
    property var cfg_customColorDarkDefault
    property var cfg_textColorMode
    property var cfg_textColorModeDefault
    property var cfg_customTextColorLight
    property var cfg_customTextColorLightDefault
    property var cfg_customTextColorDark
    property var cfg_customTextColorDarkDefault
    property var cfg_tempUnitDefault
    property var cfg_metricOrderDefault
    property var cfg_enabledMetricsDefault
    property var cfg_showCpuCoresDefault
    property var cfg_mergeCpuTempDefault
    property var cfg_mergeGpuTempDefault

    // ID is *Adapter-suffixed to avoid shadowing MetricsBody's
    // `theme` property — same QML name-resolution trap as in main.qml.
    Platform.Theme {
        id: themeAdapter
    }

    Core.MetricsBody {
        id: body
        theme: themeAdapter
    }
}
