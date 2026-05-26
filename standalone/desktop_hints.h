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
//   applyDesktopWindowHints(window) — post-window-creation EWMH hint
//                                     setter (sticky / below /
//                                     skip-taskbar / skip-pager).
//
// X11 / XWayland is the only fully-implemented path for now. Native
// Wayland (KWin / sway / Hyprland) via `layer-shell-qt` lands in a
// follow-up PR. See `docs/plasma-isolation/plan.md` "Window model"
// table and `contents/ui/platforms/standalone/CLAUDE.md` for the
// roadmap.

class QWindow;

namespace ringmonitor {

void forceXWaylandUnderWayland();
void applyDesktopWindowHints(QWindow *window);

}  // namespace ringmonitor
