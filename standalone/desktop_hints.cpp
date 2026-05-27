#include "desktop_hints.h"

#include <QByteArray>
#include <QGuiApplication>
#include <QStandardPaths>
#include <QWindow>
#include <QtGui/qguiapplication_platform.h>

#include <xcb/xcb.h>

#include <cstdlib>

namespace ringmonitor {

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
    if (QStandardPaths::findExecutable(QStringLiteral("Xwayland")).isEmpty())
        return;

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
        xcb_intern_atom(conn, 0, qstrlen(name), name);
    xcb_intern_atom_reply_t *reply =
        xcb_intern_atom_reply(conn, cookie, nullptr);
    if (!reply)
        return XCB_ATOM_NONE;
    const xcb_atom_t atom = reply->atom;
    std::free(reply);
    return atom;
}

// EWMH-spec'd way to change `_NET_WM_STATE` at runtime: send a
// ClientMessage to the root window with _NET_WM_STATE_ADD (=1) and up
// to two state atoms. We need three (sticky, skip_taskbar, skip_pager
// — `_NET_WM_STATE_BELOW` already set by Qt::WindowStaysOnBottomHint),
// so two messages are required.
void addStates(xcb_connection_t *conn,
               xcb_window_t winid,
               xcb_window_t root,
               xcb_atom_t net_wm_state,
               xcb_atom_t atom_a,
               xcb_atom_t atom_b)
{
    xcb_client_message_event_t event = {};
    event.response_type = XCB_CLIENT_MESSAGE;
    event.format = 32;
    event.window = winid;
    event.type = net_wm_state;
    event.data.data32[0] = 1;  // _NET_WM_STATE_ADD
    event.data.data32[1] = atom_a;
    event.data.data32[2] = atom_b;  // 0 if only one atom
    event.data.data32[3] = 1;  // source indication: normal application
    event.data.data32[4] = 0;

    xcb_send_event(conn,
                   /*propagate=*/false,
                   root,
                   XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT |
                       XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY,
                   reinterpret_cast<const char *>(&event));
}

}  // namespace

void applyDesktopWindowHints(QWindow *window)
{
    if (!window)
        return;

    // Native interface returns nullptr off X11. Wayland-native
    // integration (layer-shell-qt) is a separate code path in a
    // follow-up PR.
    auto *x11 = qGuiApp->nativeInterface<QNativeInterface::QX11Application>();
    if (!x11)
        return;

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
    const xcb_atom_t net_wm_window_type =
        internAtom(conn, "_NET_WM_WINDOW_TYPE");
    const xcb_atom_t window_type_desktop =
        internAtom(conn, "_NET_WM_WINDOW_TYPE_DESKTOP");

    if (net_wm_state == XCB_ATOM_NONE || state_sticky == XCB_ATOM_NONE ||
        state_skip_taskbar == XCB_ATOM_NONE ||
        state_skip_pager == XCB_ATOM_NONE ||
        net_wm_window_type == XCB_ATOM_NONE ||
        window_type_desktop == XCB_ATOM_NONE)
        return;

    const xcb_screen_t *screen =
        xcb_setup_roots_iterator(xcb_get_setup(conn)).data;
    if (!screen)
        return;

    // Qt sets `_KDE_NET_WM_WINDOW_TYPE_OVERRIDE` as a side effect of
    // `Qt::FramelessWindowHint`. KWin then treats the window as
    // override-redirect — partially unmanaged — which strips standard
    // window-management behaviour. Replace the type with DESKTOP so
    // KWin handles it as wallpaper-layer content: skips the focus /
    // placement heuristic that gravity-shifts windows on resize (the
    // root cause behind our slider-driven repositioning glitch — see
    // QTBUG-57608 + the `setGeometry()` helper in `window_anchor.h`)
    // and aligns us with the Conky / xfce4-panel convention for
    // "lives on the wallpaper" widgets.
    xcb_change_property(conn, XCB_PROP_MODE_REPLACE, winid,
                        net_wm_window_type, XCB_ATOM_ATOM, 32, 1,
                        &window_type_desktop);

    // One atom per ClientMessage is the most portable form (some WMs
    // only honour the first slot reliably).
    //
    // STICKY caveat: on KWin under Wayland (XWayland clients), the
    // "all workspaces" concept maps to KWin's virtual-desktop list,
    // which on a default Plasma-Wayland session is a single desktop
    // — so the STICKY property may not appear in `xprop` output
    // even when set. The hint is still correct (and works on real
    // X11 sessions with multiple workspaces) and harmless on Wayland.
    addStates(conn, winid, screen->root, net_wm_state, state_sticky, 0);
    addStates(conn, winid, screen->root, net_wm_state, state_skip_taskbar,
              0);
    addStates(conn, winid, screen->root, net_wm_state, state_skip_pager, 0);
    xcb_flush(conn);
}

}  // namespace ringmonitor
