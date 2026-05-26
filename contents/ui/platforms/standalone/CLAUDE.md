# `contents/ui/platforms/standalone/` — Standalone adapter layer

Counterpart to [`../plasma/`](../plasma/CLAUDE.md), backing the
**standalone Linux build** (no Plasma shell, no `libksysguard`, no
`KConfig`). The two adapter layers expose the **same property
surface** to `core/`, so the same QML body renders unchanged on
either host.

The standalone target and its design constraints live in
[`docs/plasma-isolation/plan.md`](../../../../docs/plasma-isolation/plan.md)
under "Standalone target — backend choice".

## Status

| Adapter | Purpose | Status |
|---|---|---|
| `Main.qml` | Frameless transparent `Window` root (counterpart to PlasmoidItem) | placeholder (PR B1) |
| `MetricsBackend.qml` | Direct reads from `/proc/stat`, `/proc/meminfo`, `statvfs(3)` | not yet (PR D, E) |
| `ConfigStore.qml` | `Qt.labs.settings` reader/writer | not yet (PR F) |
| `Theme.qml` | Kirigami theme tokens + Qt.styleHints light/dark | not yet (PR F) |
| `ThemedIcon.qml` | wraps `Kirigami.Icon` (same as Plasma adapter) | not yet (PR F) |

## Same-surface rule

When implementing an adapter here, the contract is:

1. **Match the Plasma adapter's public property + function surface
   byte-for-byte.** `core/` consumes adapters as opaque objects; it
   doesn't know which platform is wiring them. The text-level guards
   in `tests/*.test.mjs` (e.g. `config-store.test.mjs`,
   `metrics-backend.test.mjs`) currently target only the Plasma
   adapter — duplicate the assertion list when the standalone
   counterpart lands.
2. **The import is the only place `Qt.labs.settings` / Process /
   `Qt.labs.platform` / native window handle code is allowed.**
   Same isolation invariant `core/` enforces against `org.kde.*`.
3. **No `libksysguard` dependency, ever.** The whole point of the
   standalone build is zero KDE deps beyond Kirigami. Sensors come
   from `/proc`, `/sys/class/hwmon`, `/sys/class/drm`, and
   `nvidia-smi` subprocess.

## Compositor-specific window setup

The standalone window has to integrate into the desktop as a Conky-
style widget: always on the wallpaper layer, click-inert on left
button, right-click + hover captured. This is **per-compositor**
work that lives in either `Main.qml` (`flags:`, `screen` anchoring)
or a small C++ helper called from `standalone/main.cpp` (for native
protocol bits qt6 doesn't expose):

| Compositor | Mechanism |
|---|---|
| X11 (Xorg or XWayland) | `_NET_WM_WINDOW_TYPE_DESKTOP` + EWMH hints `sticky + below + skip_taskbar + skip_pager` |
| KWin-Wayland | `wlr-layer-shell-unstable-v1`, `layer: background`, anchor + margin |
| sway / Hyprland | same as KWin |
| GNOME-Wayland (mutter) | force XWayland via `QT_QPA_PLATFORM=xcb` env injection at startup, then EWMH hints |

PR C wires this up. Until then, `Main.qml` just sets
`Qt.FramelessWindowHint | Qt.WindowStaysOnBottomHint` — works on most
compositors as a degraded-but-visible baseline.

## Maximize what lives in `core/`

Same rule as everywhere in this repo, but the standalone seam is
where it bites hardest. Every line of logic duplicated between
`platforms/plasma/` and `platforms/standalone/` is a line that has
to be fixed twice. When extracting something from a Plasma adapter
for reuse here, push the pure part down into `core/*.js` first
(example: [`SensorPicking.js`](../../core/SensorPicking.js) was
extracted from the Plasma `MetricsBackend.qml` ahead of building
this layer).

The `core/` invariant (no `org.kde.*` except Kirigami) is the
mechanised floor — but the rule is broader. Even inside what's
*allowed* in `platforms/`, prefer to keep it small.

## See also

- [`../plasma/CLAUDE.md`](../plasma/CLAUDE.md) for the surface
  contract each standalone adapter must mirror.
- [`../../core/CLAUDE.md`](../../core/CLAUDE.md) for the portable
  layer that consumes both adapters.
- [`docs/plasma-isolation/plan.md`](../../../../docs/plasma-isolation/plan.md)
  for the full standalone roadmap (8-PR sequence A → H, backend
  choice, window model decisions).
