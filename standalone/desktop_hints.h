#pragma once

// Compositor integration for the standalone binary — Conky-style
// desktop widget behaviour on Linux. Two entry points:
//
//   forceXWaylandUnderWayland()     — pre-QGuiApplication env-var
//                                     injection. No mainstream Wayland
//                                     compositor exposes layer-shell
//                                     via a Qt-native surface today
//                                     (mutter refuses, KWin's module
//                                     is unstable), so we fall back
//                                     to XWayland uniformly and rely
//                                     on EWMH hints — same trade-off
//                                     Conky takes.
//   applyDesktopWindowHints(window) — **PRE-MAP** EWMH hint setter
//                                     (sticky / below / skip-taskbar /
//                                     skip-pager). See the explicit
//                                     contract on the declaration
//                                     below before calling it.
//
// X11 / XWayland is the only fully-implemented path for now. Native
// Wayland (KWin / sway / Hyprland) via `layer-shell-qt` lands in a
// follow-up PR. See `docs/plasma-isolation/plan.md` "Window model"
// table and `contents/ui/platforms/standalone/CLAUDE.md` for the
// roadmap.

class QWindow;

namespace ringmonitor {

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
