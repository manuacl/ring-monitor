#pragma once

// Compositor integration for the standalone binary — Conky-style
// desktop widget behaviour on Linux. Three window strategies, picked
// by `decideWindowStrategy()`:
//
//   X11Ewmh          — real X11, or Wayland forced onto XWayland.
//                      `forceXWaylandUnderWayland()` does the env-var
//                      force (pre-QGuiApplication); `applyDesktopWindowHints()`
//                      sets the PRE-MAP EWMH hints (sticky / below /
//                      skip-taskbar / skip-pager).
//   WaylandLayerShell — native wlr-layer-shell `bottom`-layer surface via
//                      `layer-shell-qt` (see standalone/wayland_layer_shell.*).
//                      Only on wlroots / KWin Wayland; the layer surface
//                      never enters Alt+Tab and doesn't capture input —
//                      fixing the two NORMAL-window warts of the XWayland
//                      fallback.
//   Floating         — recovery mode (`--open-settings`): a normal
//                      managed window, no hints, no layer-shell.
//
// GNOME/mutter refuses to implement wlr-layer-shell
// (gitlab.gnome.org/GNOME/mutter#973), so a Wayland-GNOME session keeps
// using X11Ewmh-via-XWayland. When `layer-shell-qt` isn't compiled in
// (HAVE_LAYER_SHELL_QT undefined) WaylandLayerShell is never selected,
// so the behaviour is identical to the X11/XWayland-only build.

class QWindow;

namespace ringmonitor {

enum class WindowStrategy {
    X11Ewmh,
    WaylandLayerShell,
    Floating,
};

// Single source of truth for which window strategy this process uses.
// Reads the session env (XDG_SESSION_TYPE / XDG_CURRENT_DESKTOP) and
// the HAVE_LAYER_SHELL_QT build flag; pure and idempotent (no env
// mutation), so main.cpp and the WaylandLayerShell QML singleton can
// both call it and agree. `openSettings` (recovery) always maps to
// Floating.
WindowStrategy decideWindowStrategy(bool openSettings);

// Convenience predicate for the normal (non-recovery) widget path —
// what the WaylandLayerShell QML singleton's `active` property reads.
bool layerShellActive();

void forceXWaylandUnderWayland();

// PRE-MAP EWMH hint setter. **Must be called after the QWindow is
// constructed but BEFORE `app.exec()` returns control to the event
// loop** — i.e. before the X server processes the QML `visible: true`
// show() request and issues `MapWindow`. The implementation writes
// `_NET_WM_STATE` as a property via `xcb_change_property(REPLACE)`,
// which the WM reads at `MapRequest`; it does NOT send the EWMH
// runtime-mutation ClientMessage (`_NET_WM_STATE_ADD`) that would be
// required to update a mapped window's state.
//
// Calling this post-map silently fails to update the WM's view: the
// property write succeeds, but KWin / mutter only re-read the state
// list at map time. STICKY / SKIP_TASKBAR / SKIP_PAGER would appear
// in `xprop` (the X property exists) yet not actually be honoured.
// In debug builds a `Q_ASSERT(!window->isExposed())` in the function
// body catches the misuse loudly; in release builds it no-ops the
// assert but still silently produces the wrong WM state.
//
// If a future caller needs to re-apply hints AFTER the window is
// mapped (theme switch, runtime "show on all desktops" toggle, …),
// add a sibling `mutateMappedWindowState(…)` that uses
// `xcb_send_event(ClientMessage)` instead — don't call this one.
void applyDesktopWindowHints(QWindow *window);

}  // namespace ringmonitor
