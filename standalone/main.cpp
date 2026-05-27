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
    // Argv parse before QGuiApplication: we want the recovery flag
    // available even if the GUI init fails.
    //
    // --open-settings: skip the main rings window entirely and open
    // just the Settings dialog. Recovery path for the case where
    // `_NET_WM_WINDOW_TYPE_DESKTOP` swallows right-click on the user's
    // compositor (KWin regression, mutter quirk) — without this flag
    // the user would have to `pkill ring-monitor-standalone` and
    // re-edit ~/.config/dev.manuacl/ring-monitor.conf by hand.
    //
    // Implementation note: this opens a NEW process with only the
    // settings dialog. Config writes go through QSettings to the same
    // ~/.config file the running widget reads; the user kills + relaunches
    // the running widget to apply (Qt.labs.settings doesn't watch).
    // A live-reload path would need QFileSystemWatcher on the conf file
    // — out of scope for the minimal recovery.
    bool openSettings = false;
    for (int i = 1; i < argc; ++i) {
        const QString arg = QString::fromLocal8Bit(argv[i]);
        if (arg == QLatin1String("--open-settings") ||
            arg == QLatin1String("--settings")) {
            openSettings = true;
        }
    }

    // MUST run before QGuiApplication: Qt reads QT_QPA_PLATFORM at
    // app init, so any forced override has to land first. Skipped in
    // --open-settings mode: the settings dialog is a normal floating
    // window, not a wallpaper-layer widget, so the Conky-style EWMH
    // setup is irrelevant.
    if (!openSettings)
        ringmonitor::forceXWaylandUnderWayland();

    QGuiApplication app(argc, argv);

    // Standard Qt application identity. Qt.labs.settings uses these
    // to compute the config file path
    // (~/.config/dev.manuacl/ring-monitor.conf) when PR F lands.
    QGuiApplication::setOrganizationName("dev.manuacl");
    QGuiApplication::setApplicationName("ring-monitor");
    QGuiApplication::setApplicationVersion(QStringLiteral("0.5.0"));

    QQmlApplicationEngine engine;
    // Expose the flag to QML before loading so Main.qml can branch
    // on it during Component.onCompleted.
    engine.rootContext()->setContextProperty(
        QStringLiteral("settingsOnlyMode"), openSettings);
    engine.loadFromModule("RingMonitor.Standalone", "Main");

    // engine.rootObjects().isEmpty() is the canonical "QML failed to
    // load" check. Bail with non-zero so a wrapper script knows.
    if (engine.rootObjects().isEmpty())
        return 1;

    // The QML root is a `Window`, which maps to a QWindow at the C++
    // level. Apply the EWMH hints Qt can't express directly (sticky,
    // skip-taskbar, skip-pager). No-op off X11. Skipped in
    // --open-settings mode: the main window stays hidden in that case
    // and we don't want DESKTOP / BELOW hints on a window that won't
    // be shown.
    if (!openSettings) {
        if (auto *window = qobject_cast<QWindow *>(engine.rootObjects().first())) {
            ringmonitor::applyDesktopWindowHints(window);
        }
    }

    return app.exec();
}
