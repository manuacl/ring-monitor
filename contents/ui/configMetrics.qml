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

    // KDE bug 484541 placeholders — keys handled on the Appearance page
    // and the *Default variants Plasma auto-generates for "Reset".
    property var cfg_orientation
    property var cfg_orientationDefault
    property var cfg_textOpacity
    property var cfg_textOpacityDefault
    property var cfg_trackOpacity
    property var cfg_trackOpacityDefault
    property var cfg_arcOpacity
    property var cfg_arcOpacityDefault
    property var cfg_metricOrderDefault
    property var cfg_enabledMetricsDefault
    property var cfg_showCpuCoresDefault

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
