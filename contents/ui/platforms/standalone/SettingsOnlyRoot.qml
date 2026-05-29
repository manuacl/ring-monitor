import QtQuick
import RingMonitor.Standalone
import "../../core" as Core

// Recovery-mode QML root — loaded by `standalone/main.cpp` when the
// binary is launched with `--open-settings` (alias `--settings`).
// The flag is the user-facing recovery path for compositors that
// swallow right-click on the wallpaper-layer widget window; see
// `standalone/CLAUDE.md` § "Window type is `_NET_WM_WINDOW_TYPE_NORMAL`
// + `_NET_WM_STATE_BELOW`".
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
//
// Why `Item` and not an invisible `Window`: a top-level `Window`
// with `visible: false` becomes the implicit transient parent of
// any `Window` child instantiated inside it. On X11 / XWayland Qt
// treats nested Windows as transient-for the parent, and the WM
// won't map a transient child while its parent is unmapped — the
// SettingsDialog never appears on screen. Using a non-Window root
// avoids the transient relationship entirely; SettingsDialog
// becomes a stand-alone top-level Window owned by the QML object
// graph but not by any parent surface. Verified live: with
// `Window { visible: false }` as root, `xwininfo -tree -root` shows
// zero ring-monitor windows after `--open-settings`; with `Item`,
// the dialog maps as expected.

Item {
    id: root

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
