import QtQuick
import QtQuick.Window
import RingMonitor.Standalone
import "../../core" as Core

// Recovery-mode QML root — loaded by `standalone/main.cpp` when the
// binary is launched with `--open-settings` (alias `--settings`).
// The flag is the user-facing recovery path for compositors that
// swallow right-click on `_NET_WM_WINDOW_TYPE_DESKTOP` windows; see
// `standalone/CLAUDE.md` § "_NET_WM_WINDOW_TYPE_DESKTOP can swallow
// right-click on some compositors".
//
// Why a separate root rather than a flag through `Main.qml`: the
// rings widget shouldn't be constructed invisibly just to be torn
// down on dialog close. The previous shape threaded a `_settingsOnly`
// boolean through eight sites (argv, two startup gates, a context
// property, a typeof-guarded QML alias, `visible:`, a branched
// `Component.onCompleted`, a Qt.quit Connections) and still built
// the full MetricsBackend + MainContent + Screen Connections
// invisibly — wasting `/proc` reads and `setGeometry` calls every
// time the user dragged a slider in the dialog. This root hosts
// only what SettingsDialog needs (ConfigStore + Theme +
// UpdateChecker), shows the dialog immediately, and quits when the
// dialog `closing` signal fires.
//
// Using `onClosing` (not `onVisibilityChanged === Hidden`) keeps
// the quit intent-driven: a future programmatic hide (modal color
// picker, hide-while-Apply-and-reopen) wouldn't kill the recovery
// process mid-edit.

Window {
    id: root

    // Invisible host. The dialog is a separate Window that draws
    // itself.
    title: "ring-monitor (settings recovery)"
    visible: false

    ConfigStore {
        id: configStoreAdapter
    }
    Theme {
        id: themeAdapter
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
        onClosing: Qt.quit()
    }

    Component.onCompleted: settingsDialog.show()
}
