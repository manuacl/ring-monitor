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

    // ── Update-check group ──────────────────────────────────────────
    // Reads stay readonly like the rest of this adapter. Writes
    // (recordUpdateCheck / acknowledgeVersion) happen here too because
    // the update flow is the one path that needs to persist outside
    // the SimpleKCM cfg_* magic — it writes opportunistically from
    // the widget's runtime path, not from a config dialog.
    // Defensive defaults: when KConfig hasn't materialised a brand-new
    // schema key yet (first run after a release adding entries), the
    // raw read can be undefined. Coerce here so downstream bindings
    // (typed real / string) never get an `undefined` assignment, which
    // QML rejects with a "Unable to assign [undefined] to X" warning.
    readonly property bool checkForUpdatesEnabled: Plasmoid.configuration.checkForUpdatesEnabled !== false
    readonly property double lastUpdateCheck: Plasmoid.configuration.lastUpdateCheck || 0
    readonly property string latestKnownVersion: Plasmoid.configuration.latestKnownVersion || ""
    readonly property string acknowledgedVersion: Plasmoid.configuration.acknowledgedVersion || ""
    // Local widget version, exposed here so core/UpdateChecker.qml can
    // compare against the cached remote without importing Plasma.
    readonly property string localVersion: (Plasmoid.metaData && Plasmoid.metaData.version) || ""

    function recordUpdateCheck(version, timestampMs) {
        Plasmoid.configuration.latestKnownVersion = version;
        Plasmoid.configuration.lastUpdateCheck = timestampMs;
    }

    function acknowledgeVersion(version) {
        Plasmoid.configuration.acknowledgedVersion = version;
    }
}
