import QtQuick
import Qt.labs.settings

// Standalone counterpart of platforms/plasma/ConfigStore.qml. Same
// public property surface (consumers in core/ don't change), backed
// by Qt.labs.settings → an INI file at
// ~/.config/dev.manuacl/ring-monitor.conf (the path is derived from
// QGuiApplication::setOrganizationName + setApplicationName, both
// set in standalone/main.cpp).
//
// Important divergence from the Plasma adapter: properties are NOT
// `readonly`. The Plasma side relies on the SimpleKCM cfg_* magic
// for writes, so the adapter is reads-only by design. The standalone
// build has no SimpleKCM — the SettingsDialog (PR F2) writes the
// same properties directly. Same Settings element is both the reader
// and the writer, so a write from the dialog is immediately visible
// to MainContent.
//
// Defaults below mirror contents/config/main.xml byte-for-byte. When
// adding a new key, update BOTH files OR the standalone build will
// silently use a different default than the Plasma build. The
// tests/standalone-config-store.test.mjs guard asserts the key list
// matches, but defaults are caught only by reading both files
// side-by-side — care needed.

Settings {
    id: store

    // ── Metrics group ───────────────────────────────────────────────
    property string metricOrder: "cpu,cpuTemp,ram,swap,gpu,gpuTemp,disk"
    property string enabledMetrics: "cpu,ram"
    // Selected disk partition ids (empty = the backend's default, i.e. the
    // $HOME-bearing filesystem on standalone).
    property string enabledPartitions: ""
    // All discovered partition ids in display order (first = outermost ring).
    // Empty = alphabetical by label.
    property string partitionOrder: ""
    // JSON UUID→label cache so a disconnected partition shows its last-known
    // name on the picker's stale row instead of a bare UUID.
    property string partitionLabels: ""
    property bool showCpuCores: true
    property bool mergeCpuTemp: false
    property bool mergeGpuTemp: false

    // ── Appearance group ────────────────────────────────────────────
    property string orientation: "horizontal"
    property int ringSize: 180
    property int ringSpacingPercent: 7
    property int windowMargin: 0
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
    property string tempUnit: "auto"

    // ── Update-check group ──────────────────────────────────────────
    property bool checkForUpdatesEnabled: true
    property double lastUpdateCheck: 0
    property string latestKnownVersion: ""
    property string acknowledgedVersion: ""

    // Local widget version. Reads QGuiApplication::applicationVersion,
    // which standalone/main.cpp sets from the `RING_MONITOR_VERSION`
    // compile definition that CMake parses out of metadata.json's
    // KPlugin.Version — the single source of truth the release
    // pipeline bumps. No manual sync, no drift.
    readonly property string localVersion: Qt.application.version

    // Mirror the Plasma adapter's writer functions for the update
    // flow. UpdateChecker calls these from its runtime path (not from
    // a config dialog), so they need to be available regardless of
    // whether the SettingsDialog is open. Writes go straight to the
    // Settings element above — Qt.labs.settings persists them on the
    // next event-loop pass.
    function recordUpdateCheck(version, timestampMs) {
        store.latestKnownVersion = version;
        store.lastUpdateCheck = timestampMs;
    }

    function acknowledgeVersion(version) {
        store.acknowledgedVersion = version;
    }
}
