import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import "platform" as Platform

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
    Platform.Theme {
        id: theme
    }

    Platform.ConfigStore {
        id: configStore
    }

    Platform.MetricsBackend {
        id: metrics
    }

    // ── Portable body ───────────────────────────────────────────────
    fullRepresentation: MainContent {
        theme: theme
        configStore: configStore
        metrics: metrics
    }
}
