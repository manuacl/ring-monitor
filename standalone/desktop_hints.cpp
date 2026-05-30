#include "desktop_hints.h"

#include <QByteArray>
#include <QDebug>
#include <QGuiApplication>
#include <QStandardPaths>
#include <QWindow>
#include <QtGui/qguiapplication_platform.h>

#include <xcb/xcb.h>

#include <cstdlib>

namespace ringmonitor {

WindowStrategy decideWindowStrategy(bool openSettings)
{
    // Recovery dialog is a normal managed window — no Conky hints, no
    // layer surface.
    if (openSettings)
        return WindowStrategy::Floating;

    const QByteArray session = qgetenv("XDG_SESSION_TYPE").toLower();
    if (session != "wayland")
        return WindowStrategy::X11Ewmh; // real X11 (or unset → assume X11)

#ifdef HAVE_LAYER_SHELL_QT
    // GNOME/mutter has refused to implement wlr-layer-shell
    // (gitlab.gnome.org/GNOME/mutter#973), so on a Wayland-GNOME
    // session the native layer surface would silently degrade to a
    // plain xdg-toplevel. Keep GNOME on the XWayland fallback (EWMH
    // hints) and take the native path everywhere else under Wayland —
    // KWin, sway, Hyprland, and the rest of wlroots all implement it.
    // Heuristic, not a runtime registry probe: cheap, and a wlroots
    // compositor that mis-reports XDG_CURRENT_DESKTOP only falls back
    // to XWayland (degraded, not broken).
    const QByteArray desktop = qgetenv("XDG_CURRENT_DESKTOP").toUpper();
    if (!desktop.contains("GNOME"))
        return WindowStrategy::WaylandLayerShell;
#endif

    return WindowStrategy::X11Ewmh; // Wayland-GNOME, or no layer-shell-qt
}

bool layerShellActive()
{
    return decideWindowStrategy(/*openSettings=*/false) ==
           WindowStrategy::WaylandLayerShell;
}

void forceXWaylandUnderWayland()
{
    // Reads at startup (before QGuiApplication) so Qt picks up the
    // platform plugin override.
    const QByteArray session = qgetenv("XDG_SESSION_TYPE").toLower();
    const bool isWayland = session == "wayland";
    const bool userOverride = !qgetenv("QT_QPA_PLATFORM").isEmpty();
    if (!isWayland || userOverride)
        return;

    // Probe XWayland on $PATH before forcing xcb: if the user removed
    // `xorg-x11-server-Xwayland` (or runs a minimal Sway/Hyprland
    // install without it), `QT_QPA_PLATFORM=xcb` makes Qt's xcb
    // plugin fail to load → `QGuiApplication` aborts with "Could not
    // load the Qt platform plugin xcb" and the binary never starts.
    // Fall back to native Wayland in that case — the EWMH hints in
    // `applyDesktopWindowHints` will no-op (the X11 native interface
    // returns nullptr off X11) but the app still runs.
    //
    // QStandardPaths::findExecutable walks $PATH so it catches
    // Xwayland whether it lives in /usr/bin (Debian/Fedora default)
    // or /usr/libexec (some Arch builds, NixOS profiles).
    if (QStandardPaths::findExecutable(QStringLiteral("Xwayland")).isEmpty()) {
        // Single warning so the no-Xwayland failure mode (floating
        // window, no EWMH hints) is greppable in the journal / stderr.
        qWarning(
            "ring-monitor: Xwayland not found on $PATH — staying on "
            "native Wayland. The Conky-style EWMH hints "
            "(_NET_WM_WINDOW_TYPE_NORMAL, _NET_WM_STATE_BELOW, "
            "STICKY, SKIP_TASKBAR, SKIP_PAGER) require X11 and will "
            "no-op. Install the Xwayland package for the full "
            "wallpaper-layer behaviour.");
        return;
    }

    // No mainstream Wayland compositor exposes wlr-layer-shell as an
    // ergonomic Qt-native surface today: mutter refuses to implement
    // it (gitlab.gnome.org/GNOME/mutter#973) and KWin does
    // (layer-shell-qt) but the Qt module is unstable / not installed
    // by default. XWayland, by contrast, lets us send
    // `_NET_WM_STATE_BELOW + STICKY + SKIP_*` and gets us the
    // Conky-on-the-wallpaper look on every Wayland compositor we
    // care about (KWin, mutter). Best-effort, with known glitches
    // (Activities mode, desktop click pass-through), same as the
    // trade-off Conky users accept on Wayland.
    qputenv("QT_QPA_PLATFORM", "xcb");
}

namespace {

xcb_atom_t internAtom(xcb_connection_t *conn, const char *name)
{
    const xcb_intern_atom_cookie_t cookie =
        xcb_intern_atom(conn, 0, static_cast<uint16_t>(qstrlen(name)), name);
    xcb_intern_atom_reply_t *reply =
        xcb_intern_atom_reply(conn, cookie, nullptr);
    if (!reply)
        return XCB_ATOM_NONE;
    const xcb_atom_t atom = reply->atom;
    std::free(reply);
    return atom;
}

}  // namespace

void applyDesktopWindowHints(QWindow *window)
{
    if (!window)
        return;

    // Pre-map contract — see header docblock. `isExposed()` returns
    // true only after the WM has delivered MapNotify; before
    // `app.exec()` runs it's reliably false. Debug-only so a release
    // build still produces (incorrectly) a property write rather
    // than crashing the widget.
    Q_ASSERT(!window->isExposed());

    // Native interface returns nullptr off X11. Wayland-native
    // integration (layer-shell-qt) is a separate code path in a
    // follow-up PR. Emit a warning so the no-op is debuggable: this
    // branch is reached when `forceXWaylandUnderWayland` decided not
    // to force xcb (no Xwayland on $PATH, or user override pointing
    // to wayland), or when running directly on Wayland without a
    // Wayland session env var.
    auto *x11 = qGuiApp->nativeInterface<QNativeInterface::QX11Application>();
    if (!x11) {
        qWarning(
            "ring-monitor: X11 native interface unavailable — running "
            "on native Wayland (or a non-X11 platform). EWMH hints "
            "(_NET_WM_WINDOW_TYPE_NORMAL, _NET_WM_STATE_BELOW, "
            "STICKY, SKIP_TASKBAR, SKIP_PAGER) will not be set; the "
            "window will appear as a normal floating Qt window.");
        return;
    }

    xcb_connection_t *conn = x11->connection();
    if (!conn)
        return;

    const auto winid = static_cast<xcb_window_t>(window->winId());
    if (winid == 0)
        return;

    const xcb_atom_t net_wm_state = internAtom(conn, "_NET_WM_STATE");
    const xcb_atom_t state_sticky = internAtom(conn, "_NET_WM_STATE_STICKY");
    const xcb_atom_t state_skip_taskbar =
        internAtom(conn, "_NET_WM_STATE_SKIP_TASKBAR");
    const xcb_atom_t state_skip_pager =
        internAtom(conn, "_NET_WM_STATE_SKIP_PAGER");
    const xcb_atom_t state_below = internAtom(conn, "_NET_WM_STATE_BELOW");
    const xcb_atom_t net_wm_window_type =
        internAtom(conn, "_NET_WM_WINDOW_TYPE");
    const xcb_atom_t window_type_normal =
        internAtom(conn, "_NET_WM_WINDOW_TYPE_NORMAL");

    if (net_wm_state == XCB_ATOM_NONE || state_sticky == XCB_ATOM_NONE ||
        state_skip_taskbar == XCB_ATOM_NONE ||
        state_skip_pager == XCB_ATOM_NONE || state_below == XCB_ATOM_NONE ||
        net_wm_window_type == XCB_ATOM_NONE ||
        window_type_normal == XCB_ATOM_NONE)
        return;

    // Qt sets `_KDE_NET_WM_WINDOW_TYPE_OVERRIDE` as a side effect of
    // `Qt::FramelessWindowHint`. KWin then treats the window as
    // override-redirect — partially unmanaged — which strips standard
    // window-management behaviour (notably honouring `_NET_WM_STATE`).
    // We must REPLACE the type to clear that override; the value we set
    // is NORMAL, paired with the BELOW state below to pin us just above
    // the wallpaper.
    //
    // SCENARIO: why NORMAL and not DESKTOP. DESKTOP put the window in
    // plasmashell's *own* containment layer, where it collided with the
    // wallpaper containment: a left-click on the desktop raised the
    // opaque wallpaper over us and the widget vanished (process alive,
    // window occluded — not a crash). NORMAL + BELOW lives one layer
    // above the wallpaper, so it survives a desktop click on every EWMH
    // stacking WM we target (KWin, mutter, xfwm4). Trade-off: DESKTOP
    // also made KWin skip the focus/placement gravity heuristic that
    // shifts a window on resize (QTBUG-57608); under NORMAL that path is
    // back in play, but the slider-driven repositioning is already
    // compensated atomically by `window_anchor.h`'s `setGeometry()`, so
    // it stays masked. The WM reads this property during MapRequest —
    // works pre-map (when this runs from `main.cpp`, ahead of
    // `app.exec()`).
    xcb_change_property(conn, XCB_PROP_MODE_REPLACE, winid,
                        net_wm_window_type, XCB_ATOM_ATOM, 32, 1,
                        &window_type_normal);

    // _NET_WM_STATE: declared as a PROPERTY before the window maps,
    // not via a ClientMessage. EWMH §"_NET_WM_STATE" assigns the
    // ClientMessage protocol (`_NET_WM_STATE_ADD` etc.) to mutating
    // the state list of a **mapped** window at runtime — but our
    // caller in `main.cpp` runs synchronously between
    // `engine.loadFromModule` and `app.exec()`, so the QML
    // `visible: true` show() request hasn't yet been processed by the
    // event loop and `MapWindow` has not been issued to the X server.
    // KWin (and mutter through XWayland) silently drop ClientMessages
    // targeting unmapped windows, which left STICKY / SKIP_TASKBAR /
    // SKIP_PAGER intermittent in `xprop` after launch. Writing the
    // property with the full state list is the spec-compliant pre-map
    // declaration — the WM reads it during MapRequest and treats
    // absent / empty as "no states".
    //
    // BELOW is included explicitly even though Qt adds it via
    // `Qt::WindowStaysOnBottomHint`: Qt's own add arrives post-map
    // through a ClientMessage, but our REPLACE here would otherwise
    // clobber any pre-existing list. Being explicit is cheaper than
    // racing Qt's xcb-plugin initialisation order. STICKY caveat is
    // unchanged: on a default Plasma-Wayland session (single virtual
    // desktop) STICKY may not appear in `xprop`, but the hint is
    // still correct (and works on real X11 sessions with multiple
    // workspaces).
    const xcb_atom_t states[] = {state_sticky, state_skip_taskbar,
                                 state_skip_pager, state_below};
    xcb_change_property(conn, XCB_PROP_MODE_REPLACE, winid, net_wm_state,
                        XCB_ATOM_ATOM, 32,
                        sizeof(states) / sizeof(states[0]), states);

    xcb_flush(conn);
}

}  // namespace ringmonitor
