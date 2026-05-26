import QtQuick
import QtQuick.Window
import "../../core" as Core

// Standalone root window — counterpart to the PlasmoidItem in
// contents/ui/main.qml. Frameless, transparent, sized to the rings'
// implicit content size.
//
// Scope at this stage (PR F1): the three platform adapters
// (ConfigStore via Qt.labs.settings, Theme + ThemedIcon as Kirigami
// passthroughs) are in place, so Core.MainContent renders the
// actual rings here — replacing the smoke-test layout that PR D / E
// shipped. The SettingsDialog opener (right-click menu or keyboard
// shortcut) lands in PR F2.
//
// Compositor-specific behaviour (always-on-bottom, EWMH hints,
// click-through input region) sits in `standalone/desktop_hints.cpp`
// — see PR C.

Window {
    id: root

    title: "ring-monitor"
    // Track MainContent's implicit size so the window grows / shrinks
    // with the enabled-metrics list. A small fixed padding so the
    // rings don't kiss the window edges.
    width: content.implicitWidth + 24
    height: content.implicitHeight + 24
    visible: true

    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnBottomHint
    color: "transparent"

    // ── Platform adapters ───────────────────────────────────────────
    // IDs are *Adapter-suffixed to avoid shadowing the same-named
    // properties on MainContent (same name-resolution trap as in
    // contents/ui/main.qml — Plasma side). Documented in
    // ../../core/CLAUDE.md § "Don't reuse a property name as an id".
    Theme {
        id: themeAdapter
    }

    ConfigStore {
        id: configStoreAdapter
    }

    MetricsBackend {
        id: metricsAdapter
    }

    Core.UpdateChecker {
        id: updateCheckerAdapter
        configStore: configStoreAdapter
    }

    // ── Portable body ───────────────────────────────────────────────
    Core.MainContent {
        id: content
        anchors.centerIn: parent
        theme: themeAdapter
        configStore: configStoreAdapter
        metrics: metricsAdapter
        updateChecker: updateCheckerAdapter
        // No-op until PR F2 ships the SettingsDialog + a way to open
        // it. The badge will fire this when the user has a pending
        // update notification — for now we silently ignore.
        // TODO(PR F2): open the SettingsDialog here.
        onConfigureRequested: {}
    }
}
