import QtQuick
import org.kde.kcmutils as KCM
import "platforms/plasma" as Platform
import "core" as Core

// Plasma-side wrapper for the About config page. Wires the shared
// ConfigStore (read + the recordUpdateCheck / acknowledgeVersion
// writers) into the portable AboutBody. Same wrapper-vs-body split
// pattern as the other config pages.
//
// HACK: KDE bug 484541 — Plasma sets every cfg_<key> on every page,
// and Plasma 6 also generates cfg_<key>Default for the "Reset"
// feature. We declare placeholders for the keys this page does NOT
// bridge to keep the journal quiet.

KCM.SimpleKCM {
    id: page

    // Bridged to body via signals so writes go through ConfigStore
    // (not Plasmoid.configuration directly) — keeps the standalone
    // build's substitution clean.
    property alias cfg_checkForUpdatesEnabled: checkForUpdatesProxy.value
    // The persisted fields below are written by UpdateChecker via
    // ConfigStore.recordUpdateCheck / acknowledgeVersion — never from
    // this page. We still alias them so KConfig accepts the cfg_*
    // assignments Plasma broadcasts on page open.
    property alias cfg_lastUpdateCheck: lastCheckProxy.value
    property alias cfg_latestKnownVersion: latestVersionProxy.value
    property alias cfg_acknowledgedVersion: acknowledgedProxy.value

    // KDE bug 484541 placeholders for keys handled on other pages.
    property var cfg_metricOrder
    property var cfg_metricOrderDefault
    property var cfg_enabledMetrics
    property var cfg_enabledMetricsDefault
    property var cfg_showCpuCores
    property var cfg_showCpuCoresDefault
    property var cfg_mergeCpuTemp
    property var cfg_mergeCpuTempDefault
    property var cfg_mergeGpuTemp
    property var cfg_mergeGpuTempDefault
    property var cfg_tempUnit
    property var cfg_tempUnitDefault
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
    property var cfg_checkForUpdatesEnabledDefault
    property var cfg_lastUpdateCheckDefault
    property var cfg_latestKnownVersionDefault
    property var cfg_acknowledgedVersionDefault

    // Internal "proxies" hold the cfg_* values so the body can read
    // the live state without each prop becoming a top-level alias.
    QtObject {
        id: checkForUpdatesProxy
        property bool value: true
    }
    QtObject {
        id: lastCheckProxy
        property double value: 0
    }
    QtObject {
        id: latestVersionProxy
        property string value: ""
    }
    QtObject {
        id: acknowledgedProxy
        property string value: ""
    }

    Platform.ConfigStore {
        id: configStoreAdapter
    }

    Core.UpdateChecker {
        id: updateChecker
        configStore: configStoreAdapter
    }

    Core.AboutBody {
        id: body
        localVersion: configStoreAdapter.localVersion
        remoteVersion: updateChecker.remoteVersion
        updateAvailable: updateChecker.updateAvailable
        checkForUpdatesEnabled: checkForUpdatesProxy.value

        onAcknowledgeClicked: updateChecker.acknowledge()
        onOpenStorePageClicked: updateChecker.openStorePage()
        onCheckForUpdatesToggled: on => checkForUpdatesProxy.value = on
    }
}
