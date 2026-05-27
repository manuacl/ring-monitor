#pragma once

// Atomic-setGeometry helper exposed to QML. Works around a Qt 6
// XCB-plugin quirk: per-property setters (`setX`, `setWidth`, …) —
// which is what QML `Window { x: …; width: … }` bindings emit — each
// fire a separate `xcb_configure_window` with NorthWestGravity. KWin
// processes them sequentially and gravity-shifts the window between
// each request, so a slider-driven resize ends up off-anchor (top
// edge above y=0, content cut). `QWindow::setGeometry(QRect)` is the
// only entry point that produces ONE atomic ConfigureRequest with
// `X|Y|WIDTH|HEIGHT` mask + StaticGravity — KWin then honours the
// new top-right anchor in a single hop. See QTBUG-57608 and the Qt
// forum thread "setGeometry vs Resize+Move".
//
// Registered as a QML singleton so callers don't need to instantiate
// it. Used from Main.qml's `_anchor()` function, called via
// `Qt.callLater` so the geometry change lands in exactly one tick
// after width/height bindings settle.

#include <QObject>
#include <QtQmlIntegration/QtQmlIntegration>

class QWindow;

// Lives at global scope rather than `ringmonitor::` for the same
// reason ProcReader does — Qt's QML auto-registration codegen does
// not namespace-qualify the type.
class WindowAnchor : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit WindowAnchor(QObject *parent = nullptr);

    // Atomically resize-and-move `window` to (x, y, width, height) in
    // one ConfigureRequest. No-op if `window` is null. The QML caller
    // passes the root `Window { id: root }` directly — QQuickWindow
    // (which `Window` becomes at the C++ level) inherits QWindow, so
    // the cast succeeds.
    Q_INVOKABLE void setGeometry(QObject *window, int x, int y, int width, int height);
};
