// Standalone entry point for ring-monitor.
//
// Counterpart to the Plasma host (contents/ui/main.qml + the
// plasmoid metadata in metadata.json). When this binary runs, it
// creates a QGuiApplication and loads the QML root from the
// RingMonitor.Standalone module — which qt_add_qml_module in
// CMakeLists.txt registered at build time.
//
// Compositor integration (Conky-style desktop widget — sticky,
// below, no taskbar, no pager) lives in `desktop_hints.{h,cpp}`, which
// also picks the window strategy (`decideWindowStrategy`): X11 / Wayland
// -GNOME use the EWMH-over-XWayland path; wlroots / KWin Wayland use a
// native wlr-layer-shell bottom-layer surface (standalone/wayland_layer_shell.*,
// only when layer-shell-qt is compiled in). See
// `docs/plasma-isolation/plan.md` "Window model" and
// `contents/ui/platforms/standalone/CLAUDE.md`.

#include "desktop_hints.h"

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QString>
#include <QWindow>

// Injected by CMake from metadata.json (KPlugin.Version) — the
// single source of truth the release pipeline bumps. The fallback
// only fires for a non-CMake build (none exists today); the
// `-dev` suffix makes such a build self-identify.
#ifndef RING_MONITOR_VERSION
#define RING_MONITOR_VERSION "0.0.0-dev"
#endif

int main(int argc, char *argv[])
{
    // Argv parse before QGuiApplication: --open-settings switches
    // the QML root that's loaded, which must be decided before
    // engine.loadFromModule. Argv parsing happens here (not via
    // QCommandLineParser) because the flag also gates
    // `forceXWaylandUnderWayland`, which mutates QT_QPA_PLATFORM
    // and must therefore run BEFORE QGuiApplication is constructed
    // (Qt reads QT_QPA_PLATFORM at app init); QCommandLineParser
    // requires a constructed QCoreApplication.
    //
    // --open-settings: load `SettingsOnlyRoot` instead of `Main`.
    // Recovery path for the case where the compositor swallows the
    // right-click on the wallpaper-layer widget window (some KWin /
    // mutter setups route desktop-area clicks to the containment) —
    // without this flag the user would have to
    // `pkill ring-monitor-standalone` and re-edit
    // ~/.config/dev.manuacl/ring-monitor.conf by hand.
    //
    // SettingsOnlyRoot.qml hosts only the dialog (ConfigStore +
    // Theme + UpdateChecker + SettingsDialog); the rings widget is
    // not constructed at all. See its file docblock for why this
    // shape beats threading a `_settingsOnly` flag through Main.qml.
    //
    // Implementation note: this opens a NEW process with only the
    // settings dialog. Config writes go through QSettings to the same
    // ~/.config file the running widget reads; the user kills +
    // relaunches the running widget to apply (Qt.labs.settings
    // doesn't watch). A live-reload path would need
    // QFileSystemWatcher on the conf file — out of scope.
    bool openSettings = false;
    for (int i = 1; i < argc; ++i) {
        const QString arg = QString::fromLocal8Bit(argv[i]);
        if (arg == QLatin1String("--open-settings") ||
            arg == QLatin1String("--settings")) {
            openSettings = true;
        }
    }

    // Pick the window strategy once. Only X11Ewmh needs pre-QGuiApplication
    // setup — the QT_QPA_PLATFORM=xcb force for Wayland-GNOME, which Qt
    // reads at platform init.
    //
    // WaylandLayerShell does NOT call the global LayerShellQt::Shell::
    // useLayerShell() on purpose: that sets QT_WAYLAND_SHELL_INTEGRATION
    // process-wide, turning EVERY window — including the right-click
    // context menu's popup and the settings dialog — into a full-output
    // layer surface (fullscreen, un-dismissable). Instead the layer role
    // is opted into PER WINDOW via LayerShellQt::Window::get() in
    // WaylandLayerShell::configure() (Main.qml's _anchor()), so only the
    // rings window is a layer surface and popups/dialogs stay normal
    // xdg-shell windows. Qt's Wayland plugin supports this per-window
    // selection since 6.5 (which is why useLayerShell() is deprecated).
    //
    // Floating (recovery) is a normal managed window — nothing to force.
    const ringmonitor::WindowStrategy strategy =
        ringmonitor::decideWindowStrategy(openSettings);
    if (strategy == ringmonitor::WindowStrategy::X11Ewmh)
        ringmonitor::forceXWaylandUnderWayland();

    QGuiApplication app(argc, argv);

    // Standard Qt application identity. Qt.labs.settings uses these
    // to compute the config file path
    // (~/.config/dev.manuacl/ring-monitor.conf).
    QGuiApplication::setOrganizationName("dev.manuacl");
    QGuiApplication::setApplicationName("ring-monitor");
    QGuiApplication::setApplicationVersion(QStringLiteral(RING_MONITOR_VERSION));
    // Tie the running app to its installed desktop entry. Under Wayland
    // this sets the surface app_id, so the compositor maps the window
    // to packaging/dev.manuacl.ringmonitor.desktop (correct icon +
    // taskbar grouping). No-op when the entry isn't installed (a
    // build-from-source run), so it's harmless outside the AppImage.
    QGuiApplication::setDesktopFileName("dev.manuacl.ringmonitor");

    QQmlApplicationEngine engine;
    // Two physically separate roots (no `_settingsOnly` flag threaded
    // through Main.qml): recovery mode hosts only the SettingsDialog.
    const char *qmlRoot = openSettings ? "SettingsOnlyRoot" : "Main";
    engine.loadFromModule("RingMonitor.Standalone", qmlRoot);

    // Bail non-zero so a wrapper script knows QML failed to load.
    if (engine.rootObjects().isEmpty())
        return 1;

    // Per-window integration for the chosen strategy. X11Ewmh applies
    // the EWMH hints Qt can't express directly (sticky, skip-taskbar,
    // skip-pager) — PRE-MAP only, before app.exec(); see desktop_hints.h.
    // WaylandLayerShell configures + shows its layer surface from
    // Main.qml's `_anchor()` (which owns the ring-derived size and
    // margins), so there's nothing to do here for it. Floating (recovery)
    // is a normal window and needs no hints.
    if (strategy == ringmonitor::WindowStrategy::X11Ewmh) {
        if (auto *window = qobject_cast<QWindow *>(engine.rootObjects().first())) {
            ringmonitor::applyDesktopWindowHints(window);
        }
    }

    return app.exec();
}
