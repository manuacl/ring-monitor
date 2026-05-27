// Standalone entry point for ring-monitor.
//
// Counterpart to the Plasma host (contents/ui/main.qml + the
// plasmoid metadata in metadata.json). When this binary runs, it
// creates a QGuiApplication and loads the QML root from the
// RingMonitor.Standalone module — which qt_add_qml_module in
// CMakeLists.txt registered at build time.
//
// Compositor integration (Conky-style desktop widget — sticky,
// below, no taskbar, no pager) lives in `desktop_hints.{h,cpp}`.
// X11 / XWayland is the only path implemented today; native Wayland
// (layer-shell-qt) lands in a follow-up PR. See
// `docs/plasma-isolation/plan.md` "Window model" and
// `contents/ui/platforms/standalone/CLAUDE.md`.
//
// Metric rendering arrives with PR D / E.

#include "desktop_hints.h"

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QString>
#include <QWindow>

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
    // Recovery path for the case where `_NET_WM_WINDOW_TYPE_DESKTOP`
    // swallows right-click on the user's compositor (KWin regression,
    // mutter quirk) — without this flag the user would have to
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

    // MUST run before QGuiApplication: Qt reads QT_QPA_PLATFORM at
    // app init. Skipped in recovery mode — the settings dialog is a
    // normal floating window, not a wallpaper-layer widget.
    if (!openSettings)
        ringmonitor::forceXWaylandUnderWayland();

    QGuiApplication app(argc, argv);

    // Standard Qt application identity. Qt.labs.settings uses these
    // to compute the config file path
    // (~/.config/dev.manuacl/ring-monitor.conf).
    QGuiApplication::setOrganizationName("dev.manuacl");
    QGuiApplication::setApplicationName("ring-monitor");
    QGuiApplication::setApplicationVersion(QStringLiteral("0.5.0"));

    QQmlApplicationEngine engine;
    // Recovery mode loads a minimal QML root that only hosts the
    // SettingsDialog; normal mode loads the full widget. The two
    // roots are physically separate files (no `_settingsOnly` flag
    // threaded through Main.qml).
    const char *qmlRoot = openSettings ? "SettingsOnlyRoot" : "Main";
    engine.loadFromModule("RingMonitor.Standalone", qmlRoot);

    // engine.rootObjects().isEmpty() is the canonical "QML failed to
    // load" check. Bail with non-zero so a wrapper script knows.
    if (engine.rootObjects().isEmpty())
        return 1;

    // The QML root is a `Window`, which maps to a QWindow at the
    // C++ level. Apply the EWMH hints Qt can't express directly
    // (sticky, skip-taskbar, skip-pager). PRE-MAP only — must run
    // before app.exec(); see desktop_hints.h. No-op off X11. The
    // recovery root (SettingsOnlyRoot) doesn't need these hints:
    // its only window is the dialog itself, drawn as a normal
    // floating window.
    if (!openSettings) {
        if (auto *window = qobject_cast<QWindow *>(engine.rootObjects().first())) {
            ringmonitor::applyDesktopWindowHints(window);
        }
    }

    return app.exec();
}
