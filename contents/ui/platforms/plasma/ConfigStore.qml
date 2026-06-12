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
    // Selected disk partition ids (empty = aggregate disk/all ring on Plasma).
    readonly property string enabledPartitions: Plasmoid.configuration.enabledPartitions
    // All discovered partition ids in display order (first = outermost ring).
    readonly property string partitionOrder: Plasmoid.configuration.partitionOrder
    // JSON UUID→label cache for the disconnected-partition stale rows.
    readonly property string partitionLabels: Plasmoid.configuration.partitionLabels
    // Removable partitions the user opted out of auto-show (CSV of UUIDs).
    readonly property string partitionOptOut: Plasmoid.configuration.partitionOptOut
    // JSON partition-id→custom-color map (empty = no per-partition colors).
    readonly property string diskPartitionColors: Plasmoid.configuration.diskPartitionColors
    readonly property bool showCpuCores: Plasmoid.configuration.showCpuCores
    readonly property bool mergeCpuTemp: Plasmoid.configuration.mergeCpuTemp
    readonly property bool mergeGpuTemp: Plasmoid.configuration.mergeGpuTemp
    readonly property bool splitDiskIo: Plasmoid.configuration.splitDiskIo

    // ── Appearance group ────────────────────────────────────────────
    readonly property string orientation: Plasmoid.configuration.orientation
    readonly property int ringSize: Plasmoid.configuration.ringSize
    // Hardcoded 0 on Plasma — see AppearanceBody.qml's docblock on
    // `ringSpacingVisible`: a non-zero spacing eats into the user's
    // dragged frame area (rings shrink to compensate), so forcing 0
    // gives back the wasted pixels and the rings render edge-to-edge
    // in the frame. The slider is hidden on Plasma too, so the user
    // never sets a value through the UI; the schema default of 7
    // applies only to standalone. The Plasmoid.configuration entry is
    // intentionally ignored here.
    readonly property int ringSpacingPercent: 0
    // Hardcoded on Plasma — the window-placement keys are only consumed by
    // the standalone Window anchoring code (Main.qml::WindowAnchor.setGeometry
    // / WaylandLayerShell.configure). The Plasma slot position is plasmashell's
    // job, and the AppearanceBody controls are hidden on Plasma via
    // `windowPlacementVisible`. Hardcoding makes the "unused on Plasma" intent
    // explicit and prevents a stray Plasmoid.configuration value from leaking
    // into a future Plasma-side consumer.
    readonly property string windowAnchorCorner: "top-right"
    readonly property int windowMarginX: 0
    readonly property int windowMarginY: 0
    readonly property string windowScreen: ""
    readonly property real textOpacity: Plasmoid.configuration.textOpacity
    readonly property real trackOpacity: Plasmoid.configuration.trackOpacity
    readonly property real arcOpacity: Plasmoid.configuration.arcOpacity
    readonly property string colorTheme: Plasmoid.configuration.colorTheme
    readonly property string colorMode: Plasmoid.configuration.colorMode
    readonly property color customColorLight: Plasmoid.configuration.customColorLight
    readonly property color customColorDark: Plasmoid.configuration.customColorDark
    readonly property string textColorMode: Plasmoid.configuration.textColorMode
    readonly property color customTextColorLight: Plasmoid.configuration.customTextColorLight
    readonly property color customTextColorDark: Plasmoid.configuration.customTextColorDark
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
