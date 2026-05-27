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
| `Main.qml` | Frameless transparent `Window` root + Conky-style hints (X11 / XWayland) | PR B1 (placeholder) + PR C (X11 EWMH hints in `standalone/desktop_hints.cpp`) + **PR F1 ✓ — `Core.MainContent` renders the actual rings** |
| `MetricsBackend.qml` | Direct reads from `/proc/stat`, `/proc/meminfo`, `statvfs(3)` | **PR D: CPU usage (`/proc/stat`) ✓** ; **PR E: RAM (`/proc/meminfo`) + disk (`statvfs(/)`) ✓** ; GPU + temps post-MVP |
| `ConfigStore.qml` | `Qt.labs.settings` reader/writer | **PR F1 ✓ — Settings root, defaults mirror `main.xml`** ; **PR F2 ✓ — SettingsDialog drives writes through this instance** |
| `SettingsDialog.qml` | Tabbed `Window` wrapping `core/MetricsBody` + `core/AppearanceBody` + `core/AboutBody`; opened via right-click on the widget or the update-available badge | **PR F2 ✓** |
| `Theme.qml` | Kirigami theme tokens + Qt.styleHints light/dark | **PR F1 ✓ — mirrors the Plasma adapter byte-for-byte** |
| `ThemedIcon.qml` | wraps `Kirigami.Icon` (same as Plasma adapter) | **PR F1 ✓ — one-liner mirror of the Plasma adapter** |
| `ColorPicker.qml` | wraps a plain `QQC2.AbstractButton` + `QtQuick.Dialogs.ColorDialog` (the Plasma adapter wraps `KQuickControls.ColorButton`, which is not a runtime dep of the standalone build) | **PR F2 ✓** |
| `Autostart` (C++ in `standalone/autostart.{h,cpp}`, registered via `QML_ELEMENT`) | Writes / removes `~/.config/autostart/dev.manuacl.ringmonitor.desktop` so the user can toggle "Start on login" from the Settings dialog. Plasma side uses plasmashell instead, so the toggle is hidden there (`AboutBody.autostartAvailable` gated). | **PR G ✓** |

## File-reading helper

QML's `XMLHttpRequest` with `file://` is restricted in Qt 6.5+ —
the QML loading context has to itself live under `file://` for the
read to be allowed, and our QML loads from the compiled `qrc://`
resource. The `ProcReader` helper in `standalone/proc_reader.{h,cpp}`
sidesteps that with a `Q_INVOKABLE QString read(const QString &)`
exposed to QML via `QML_ELEMENT` (auto-registered through
`qt_add_qml_module(... SOURCES ...)`). Available in QML as
`import RingMonitor.Standalone; ProcReader { id: reader }`. The same
helper also wraps `statvfs(3)` via `Q_INVOKABLE QVariantMap statvfs(const QString &path)` —
QML can't issue syscalls and `statvfs` is the only one we need for
PR E (disk capacity). Returns `{ total, available }` in bytes; empty
map on failure.

The class lives at global scope (not in `ringmonitor::`) because
Qt 6's QML auto-registration generates code calling
`qmlRegisterTypesAndRevisions<ProcReader>(...)` without
namespace-qualifying the type. Namespaced classes need
`QML_FOREIGN_NAMESPACE` boilerplate to register cleanly; the
helper is a thin one-method utility, so the lower-friction
global-scope path is the right trade-off. See `standalone/proc_reader.h`
for the full rationale.

The matching include-path tweak (`target_include_directories(...
PRIVATE standalone)`) is required because the generated
registration file includes our headers via `<proc_reader.h>`
(angle brackets, system search path) rather than `"..."`.

## Compositor support matrix (current)

| Compositor | Status | How |
|---|---|---|
| **Plasma-X11**, XFCE, Cinnamon, MATE, LXQt | ✓ native | Qt::FramelessWindowHint + Qt::WindowStaysOnBottomHint + xcb EWMH hints (sticky, skip-taskbar, skip-pager); window type forced to `_NET_WM_WINDOW_TYPE_NORMAL` to undo Qt's `_KDE_NET_WM_WINDOW_TYPE_OVERRIDE` default |
| **Plasma-Wayland** | ✓ via auto-XWayland | `forceXWaylandUnderWayland` in `desktop_hints.cpp` force-sets `QT_QPA_PLATFORM=xcb` before `QGuiApplication`, gated on `QStandardPaths::findExecutable("Xwayland")` so the app falls back to native Wayland (no Conky hints) if XWayland is missing rather than crashing. STICKY may show as no-op in `xprop` on a single virtual desktop, but BELOW + SKIP_TASKBAR + SKIP_PAGER apply correctly |
| **GNOME-Wayland (mutter)** | ✓ via auto-XWayland | Same path as Plasma-Wayland; mutter ships XWayland by default, so the probe always succeeds |
| **sway / Hyprland (wlroots-Wayland)** | ✓ via auto-XWayland (if `xwayland` package installed) or degraded native otherwise | Same probe — if the user installed XWayland they get the Conky behaviour; minimal installs fall back to native Wayland with the EWMH hints no-op'd. Layer-shell-qt-based native integration lands in a future PR |
| **KWin-Wayland native** | ⚠ degraded — same as sway above | Layer-shell-qt path same as above |

The "native Wayland layer-shell" path is deferred to a future PR
(scoped as PR C2 in [plan.md](../../../../docs/plasma-isolation/plan.md))
because installing `layer-shell-qt-devel` on the dev box requires an
`rpm-ostree install + reboot` cycle.

### Alt+Tab visibility under Plasma — known trade-off

Under Plasma-X11 / Plasma-Wayland-XWayland, the window appears in
the Alt+Tab task switcher even though `_NET_WM_STATE_SKIP_TASKBAR`
and `_NET_WM_STATE_SKIP_PAGER` are both set. This is a consequence
of the `_NET_WM_WINDOW_TYPE_NORMAL` choice in PR C: KWin's TabBox
respects window *type* more than the SKIP_* state hints, and the
alternative (`_KDE_NET_WM_WINDOW_TYPE_OVERRIDE`, which Qt sets by
default for `FramelessWindowHint` windows) tells KWin not to manage
the window at all — which strips input events and would break the
right-click context menu landing in PR G.

User-side workaround: KWin → Window Rules → add a rule matching the
window class `ring-monitor-standalone` with **"Skip switcher: Force
Yes"**. App-side, the fix is the native layer-shell path: a
wlr-layer-shell "background" layer surface never participates in
any switcher by design. That's covered by PR C2.

### `_NET_WM_WINDOW_TYPE_DESKTOP` can swallow right-click on some compositors

`applyDesktopWindowHints` rewrites the window type to `DESKTOP` so
KWin treats the window as wallpaper-layer content (atomic setGeometry,
no gravity-shift on resize — see `WindowAnchor`). The trade-off: on
some KWin point releases and Plasma containment configurations, a
`DESKTOP`-typed client has right-click forwarded to the **containment
menu** (wallpaper-level "Add widget…" / "Configure desktop…")
instead of the window's own `MouseArea`. The widget's only entry
point to Settings + Quit lives behind that right-click, so the
regression is total UX loss.

The current dev box keeps right-click delivered (verified live), but
this should be considered fragile across KWin versions and entirely
unknown on non-KDE compositors. The real fix is the native
wlr-layer-shell path (background layer surface, no window-type
involved) — scoped as PR C2 in
[`docs/plasma-isolation/plan.md`](../../../../docs/plasma-isolation/plan.md).
If right-click ever stops working post-upgrade, the diagnosis ladder
is: (1) try `_NET_WM_WINDOW_TYPE_NORMAL` (loses gravity-shift fix —
regression risk on slider resize); (2) try `_NET_WM_WINDOW_TYPE_DOCK`
(panel-style — different KWin handling); (3) accelerate PR C2.

### Initial `_anchor()` must be deferred via `Qt.callLater`

`Main.qml` calls `_anchor()` from `Component.onCompleted` to issue
the first atomic `setGeometry` against the Window. **Wrap that first
call in `Qt.callLater`** — do not call `_anchor()` directly. The
synchronous boot order is:

1. `engine.loadFromModule` → `Component.onCompleted` fires
2. `applyDesktopWindowHints(window)` swaps the window-type to
   `_NET_WM_WINDOW_TYPE_DESKTOP` (called from `main.cpp` right after
   `loadFromModule` returns)
3. `app.exec()` — the event loop starts and `Qt.callLater` fires

Calling `_anchor()` directly in step 1 issued the first configure
request against Qt's default frameless override-redirect window-type
— exactly the gravity-shift scenario the `WindowAnchor` pattern
exists to avoid. It surfaced as a brief jump on first show. Deferring
to step 3 lets the window-type land first.

### XWayland probe before forcing `QT_QPA_PLATFORM=xcb`

`forceXWaylandUnderWayland` in `standalone/desktop_hints.cpp` must
gate the `qputenv("QT_QPA_PLATFORM", "xcb")` on
`QStandardPaths::findExecutable("Xwayland")` returning a non-empty
path. Without the probe, a user running Plasma 6 Wayland who removed
`xorg-x11-server-Xwayland` (or any minimal Sway/Hyprland install
that ships without it) gets a hard crash at startup —
`QGuiApplication` aborts with "Could not load the Qt platform plugin
xcb" before any QML loads. Falling back to native Wayland makes the
Conky-on-the-wallpaper hints no-op (the X11 native interface returns
nullptr off X11), but the app still runs.

### Autostart `Exec=` line must shell-escape the path

`Autostart::buildDesktopFileContent` runs the current binary path
through `quoteExecArg` before splicing into the `Exec=` line.
Without that, an AppImage installed under a path containing spaces
(e.g. `~/Applications/Ring Monitor.AppImage`, common with
AppImageLauncher) breaks autostart silently — the XDG launcher
tokenises on whitespace and tries to exec the wrong binary. The
XDG-spec escape order is load-bearing: backslash is escaped before
`"`, `$`, and backtick (text-level-guarded by
`tests/autostart.test.mjs`).

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
