// Standalone entry point for ring-monitor.
//
// Counterpart to the Plasma host (contents/ui/main.qml + the
// plasmoid metadata in metadata.json). When this binary runs, it
// creates a QGuiApplication and loads the QML root from the
// RingMonitor.Standalone module — which qt_add_qml_module in
// CMakeLists.txt registered at build time.
//
// Scope at this stage (PR B1): open an empty frameless transparent
// window. The compositor-specific flags (always-on-bottom,
// layer-shell on Wayland, EWMH hints on X11, click-through) land
// in PR C. Metric rendering arrives with PR D / E.

#include <QGuiApplication>
#include <QQmlApplicationEngine>

int main(int argc, char *argv[])
{
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

    return app.exec();
}
