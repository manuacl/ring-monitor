import QtQuick
import "platforms/plasma" as Platform
import "core" as Core

// Plasma-side wrapper for the About config page. Wires the shared
// ConfigStore (read + the recordUpdateCheck / acknowledgeVersion
// writers) into the portable AboutBody. Same wrapper-vs-body split
// pattern as the other config pages. The KDE-484541 placeholders for
// keys this page does NOT bridge come from the PlaceholderKCM base.

Platform.PlaceholderKCM {
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
        platform: "plasma"
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
