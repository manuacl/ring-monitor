#include "wayland_layer_shell.h"

#include "desktop_hints.h"

#include <QWindow>

#ifdef HAVE_LAYER_SHELL_QT
#include <LayerShellQt/Window>
#include <QMargins>
#endif

WaylandLayerShell::WaylandLayerShell(QObject *parent)
    : QObject(parent)
{
}

bool WaylandLayerShell::active() const
{
    return ringmonitor::layerShellActive();
}

void WaylandLayerShell::configure(QObject *window, int marginTop, int marginRight,
                                  int width, int height)
{
#ifdef HAVE_LAYER_SHELL_QT
    if (!active())
        return;

    auto *w = qobject_cast<QWindow *>(window);
    if (!w)
        return;

    // Order matters: set the layer-shell role + props on the controller
    // BEFORE the size, and the FIRST call must happen while the window
    // is still hidden (Main.qml keeps `visible:false` on this path and
    // flips it true only after this returns). layer-shell-qt translates
    // these into the `get_layer_surface` request emitted when the
    // wl_surface is created on show(); calling get() after the surface
    // exists would be too late for the role.
    LayerShellQt::Window *layer = LayerShellQt::Window::get(w);
    if (!layer)
        return;

    layer->setScope(QStringLiteral("ring-monitor"));
    // SCENARIO: vanish-on-desktop-click. The `background` layer sits at
    // (or below) Plasma's wallpaper/desktop containment, so a left-click
    // on the desktop raised the containment over the widget and it
    // disappeared — the exact occlusion the X11 `_NET_WM_WINDOW_TYPE_DESKTOP`
    // type had (see desktop_hints.cpp). The `bottom` layer sits ABOVE the
    // wallpaper/containment and BELOW normal windows — the Conky-style slot:
    // the widget survives a desktop click yet never covers app windows.
    layer->setLayer(LayerShellQt::Window::LayerBottom);
    layer->setAnchors(LayerShellQt::Window::Anchors(
        LayerShellQt::Window::AnchorTop | LayerShellQt::Window::AnchorRight));
    // QMargins(left, top, right, bottom): anchored top-right, so only
    // the top + right insets are meaningful.
    layer->setMargins(QMargins(0, marginTop, marginRight, 0));
    // 0 = reserve no screen space / don't push other surfaces around —
    // a wallpaper widget, not a panel.
    layer->setExclusiveZone(0);
    // SCENARIO: fullscreen, un-closeable right-click menu. The context
    // menu is a Wayland xdg_popup; the compositor only installs the popup
    // grab — which constrains/positions it and lets click-away / Escape
    // dismiss it — when the parent surface can take seat focus. With
    // KeyboardInteractivityNone the grab never installed, so the menu
    // opened full-screen and couldn't be closed. OnDemand takes keyboard
    // focus only while the user actually interacts, so popups work yet the
    // widget still never enters a focus switcher (layer + bottom already
    // keep it out of Alt+Tab regardless).
    layer->setKeyboardInteractivity(
        LayerShellQt::Window::KeyboardInteractivityOnDemand);

    if (width > 0 && height > 0)
        w->resize(width, height);
#else
    Q_UNUSED(window);
    Q_UNUSED(marginTop);
    Q_UNUSED(marginRight);
    Q_UNUSED(width);
    Q_UNUSED(height);
#endif
}
