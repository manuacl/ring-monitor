#pragma once

// Native wlr-layer-shell integration via KDE's layer-shell-qt, exposed
// to QML as a singleton (same registration shape as WindowAnchor /
// ProcReader). On a wlroots / KWin Wayland session this turns the
// standalone window into a `background` layer surface — which, unlike
// the XWayland-fallback NORMAL window, never enters Alt+Tab and doesn't
// capture input (the two documented warts the EWMH path can't shed).
//
// The whole class is **always compiled** so the QML singleton always
// registers and Main.qml loads regardless of build config; the
// layer-shell calls themselves are `#ifdef HAVE_LAYER_SHELL_QT` in the
// .cpp. Without the macro `active()` is false and `configure()` is a
// no-op, so the binary behaves exactly like the X11/XWayland-only build.
//
// Whether the layer path is taken is decided by
// `ringmonitor::decideWindowStrategy()` (standalone/desktop_hints.*) —
// this class only actuates it.

#include <QObject>
#include <QtQmlIntegration/QtQmlIntegration>

class QWindow;

// Global scope (not ringmonitor::) for the same reason as ProcReader /
// WindowAnchor: Qt's QML auto-registration codegen does not
// namespace-qualify the registered type.
class WaylandLayerShell : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    // True when this process runs as a layer-shell bottom-layer surface
    // (Wayland, non-GNOME, layer-shell-qt compiled in). Constant for the
    // process lifetime. Drives Main.qml's initial `visible` (the layer
    // path is shown from QML only after the surface is configured) and
    // which branch `_anchor()` takes.
    Q_PROPERTY(bool active READ active CONSTANT)

public:
    explicit WaylandLayerShell(QObject *parent = nullptr);

    bool active() const;

    // Configure `window` as a top-right-anchored bottom-layer surface
    // sized `width`×`height`, inset by `marginTop`/`marginRight`.
    // The compositor positions the surface from the anchors + margins,
    // so there is no x/y and no WindowAnchor atomic-setGeometry dance
    // (that's an X11 / QTBUG-57608 concern). Idempotent and live:
    // anchors / margins / size re-commit the existing surface, so
    // calling it on every re-anchor (e.g. a margin-slider drag) works.
    // No-op when `active()` is false. The FIRST call must run while the
    // window is still hidden — see the .cpp and Main.qml `_anchor()`.
    Q_INVOKABLE void configure(QObject *window, int marginTop, int marginRight,
                               int width, int height);
};
