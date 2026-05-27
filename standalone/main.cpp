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
#include <QWindow>

int main(int argc, char *argv[])
{
    // MUST run before QGuiApplication: Qt reads QT_QPA_PLATFORM at
    // app init, so any forced override has to land first.
    ringmonitor::forceXWaylandUnderWayland();

    QGuiApplication app(argc, argv);

    // Standard Qt application identity. Qt.labs.settings uses these
    // to compute the config file path
    // (~/.config/dev.manuacl/ring-monitor.conf) when PR F lands.
    QGuiApplication::setOrganizationName("dev.manuacl");
    QGuiApplication::setApplicationName("ring-monitor");
    QGuiApplication::setApplicationVersion(QStringLiteral("0.5.0"));

    QQmlApplicationEngine engine;
    engine.loadFromModule("RingMonitor.Standalone", "Main");

    // engine.rootObjects().isEmpty() is the canonical "QML failed to
    // load" check. Bail with non-zero so a wrapper script knows.
    if (engine.rootObjects().isEmpty())
        return 1;

    // The QML root is a `Window`, which maps to a QWindow at the C++
    // level. Apply the EWMH hints Qt can't express directly (sticky,
    // skip-taskbar, skip-pager). No-op off X11.
    if (auto *window = qobject_cast<QWindow *>(engine.rootObjects().first())) {
        ringmonitor::applyDesktopWindowHints(window);
    }

    return app.exec();
}
