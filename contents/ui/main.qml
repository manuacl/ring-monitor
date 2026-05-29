import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import "platforms/plasma" as Platform
import "core" as Core

// Plasmoid host. Holds the platform adapters (the only place where
// org.kde.* APIs are touched at the top level) and instantiates the
// portable MainContent body inside fullRepresentation.
//
// All visible behaviour lives in MainContent.qml — this file is the
// Plasma-specific shell that a standalone build would replace with a
// frameless Window root. See docs/plasma-isolation/plan.md.

PlasmoidItem {
    id: root

    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    // ── Platform adapters ───────────────────────────────────────────
    // IDs are *Adapter-suffixed to avoid shadowing the same-named
    // properties on MainContent. Without the suffix, QML's name
    // resolution inside the `fullRepresentation` Component template
    // would bind `theme: theme` to MainContent.theme (= undefined)
    // rather than the outer id.
    Platform.Theme {
        id: themeAdapter
    }

    Platform.ConfigStore {
        id: configStoreAdapter
    }

    Platform.MetricsBackend {
        id: metricsAdapter
        // Track removable media (the findmnt poll behind auto-showing USB rings)
        // ONLY when the user has the disk ring enabled — a widget without a disk
        // ring spawns no subprocess at all (#59 review finding 1). We deliberately
        // do NOT also gate on Plasmoid.expanded: with preferredRepresentation =
        // fullRepresentation the rings are drawn inline on the desktop (this
        // widget's primary home), where `expanded` is the popup-open signal and
        // is not reliably true — ANDing it in would break auto-show there. A 2s
        // mount scan while a panel popup is collapsed is negligible and keeps the
        // removable set fresh for when it is reopened.
        removableTrackingActive: configStoreAdapter.enabledMetrics.split(",").indexOf("disk") >= 0
    }

    Core.UpdateChecker {
        id: updateCheckerAdapter
        configStore: configStoreAdapter
    }

    // ── Portable body ───────────────────────────────────────────────
    fullRepresentation: Core.MainContent {
        theme: themeAdapter
        configStore: configStoreAdapter
        metrics: metricsAdapter
        updateChecker: updateCheckerAdapter
        // The update-badge click lands users in the config dialog —
        // since Plasma 6 has no "open at category X" API, the
        // dynamic-visible trick in config.qml puts the About page
        // first whenever an update is unacknowledged.
        onConfigureRequested: Plasmoid.internalAction("configure").trigger()
    }
}
