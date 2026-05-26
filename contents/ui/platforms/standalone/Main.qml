import QtQuick
import QtQuick.Window
import QtQuick.Controls as QQC2
import "../../core" as Core

// Standalone root window — counterpart to the PlasmoidItem in
// contents/ui/main.qml. Frameless, transparent, sized to the rings'
// implicit content size.
//
// Scope at this stage (PR F2): the three platform adapters
// (ConfigStore via Qt.labs.settings, Theme + ThemedIcon as Kirigami
// passthroughs) are in place, so Core.MainContent renders the actual
// rings. SettingsDialog wraps the same three core bodies the Plasma
// side reuses — opened via the right-click context menu or the
// update-available badge.
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

    SettingsDialog {
        id: settingsDialog
        configStore: configStoreAdapter
        theme: themeAdapter
        updateChecker: updateCheckerAdapter
    }

    // ── Right-click context menu ────────────────────────────────────
    //
    // MouseArea only captures right-click so left-click on the
    // (future) interactive parts of the rings stays free. The
    // popup() coordinates are local to the MouseArea, which fills
    // the window — Menu positions itself at the cursor.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: mouse => contextMenu.popup()
    }

    QQC2.Menu {
        id: contextMenu
        QQC2.MenuItem {
            text: qsTr("Settings…")
            onTriggered: settingsDialog.show()
        }
        QQC2.MenuSeparator {}
        QQC2.MenuItem {
            text: qsTr("Quit")
            onTriggered: Qt.quit()
        }
    }

    // ── Portable body ───────────────────────────────────────────────
    Core.MainContent {
        id: content
        anchors.centerIn: parent
        theme: themeAdapter
        configStore: configStoreAdapter
        metrics: metricsAdapter
        updateChecker: updateCheckerAdapter
        // The update-badge click opens the same dialog as the
        // right-click menu — discoverable nudge for users who haven't
        // found the right-click yet.
        onConfigureRequested: settingsDialog.show()
    }
}
