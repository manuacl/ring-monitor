import QtQuick
import org.kde.plasma.plasmoid

// Platform adapter: read-only view onto Plasmoid.configuration.
// Exposes every persisted config key as a typed property so main.qml
// (and any future reader) consumes `configStore.X` instead of
// reaching into Plasmoid.configuration directly.
//
// Implemented as an Item (not a singleton): Plasmoid is a context
// property injected by the Plasma shell on the QML root scope, so it
// only resolves when accessed from inside the loaded PlasmoidItem
// tree. A singleton living outside that scope would see Plasmoid as
// undefined.
//
// Writes still go through the config pages' `cfg_*` magic — that's a
// separate Plasma-managed flow handled by SimpleKCM. This adapter is
// reads-only by design.
//
// A standalone build would ship a parallel ConfigStore.qml backed by
// Qt.labs.settings, exposing the same property surface.

Item {
    // ── Metrics group (see contents/config/main.xml) ────────────────
    readonly property string metricOrder: Plasmoid.configuration.metricOrder
    readonly property string enabledMetrics: Plasmoid.configuration.enabledMetrics
    readonly property bool showCpuCores: Plasmoid.configuration.showCpuCores
    readonly property bool mergeCpuTemp: Plasmoid.configuration.mergeCpuTemp
    readonly property bool mergeGpuTemp: Plasmoid.configuration.mergeGpuTemp

    // ── Appearance group ────────────────────────────────────────────
    readonly property string orientation: Plasmoid.configuration.orientation
    readonly property real textOpacity: Plasmoid.configuration.textOpacity
    readonly property real trackOpacity: Plasmoid.configuration.trackOpacity
    readonly property real arcOpacity: Plasmoid.configuration.arcOpacity
    readonly property string colorTheme: Plasmoid.configuration.colorTheme
    readonly property string colorMode: Plasmoid.configuration.colorMode
    readonly property color customColorLight: Plasmoid.configuration.customColorLight
    readonly property color customColorDark: Plasmoid.configuration.customColorDark
    readonly property string tempUnit: Plasmoid.configuration.tempUnit
}
