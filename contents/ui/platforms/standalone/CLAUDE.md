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
| `SettingsOnlyRoot.qml` | Recovery-mode QML root loaded when the binary runs with `--open-settings`. Hosts only the `SettingsDialog` (no rings, no MetricsBackend). | **PR #37 follow-up ✓** |
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

`read()` is **allowlisted to `/proc/` and `/sys/` only**, with the
input first run through `QDir::cleanPath` so the allowlist applies
to the resolved path (i.e. `reader.read("/proc/../etc/passwd")` is
refused, not silently opened). Every other path returns the empty
string with a `qWarning("ProcReader::read refused …")` on stderr.

**Threat model context.** The widget runs as the local user — not
as root, not as a network service, not in a sandbox — so the
allowlist is **not** a privilege boundary: any file `reader.read(...)`
could return is also a file the user can `cat` directly from their
terminal. The allowlist exists to keep the QML side honest at dev
time: a typo'd path emits a greppable `qWarning` instead of
silently returning unrelated data. Same reasoning for the
`QDir::cleanPath` step — without it the header comment claiming
"only `/proc/` and `/sys/`" would be a lie. New sensors that need a
different prefix (e.g. `/var/run/...`) must extend the allowlist in
`proc_reader.cpp` and add a `tests/proc-reader.test.mjs` guard for
the new prefix.

`statvfs()` does NOT carry an allowlist (intentional asymmetry):
it's a filesystem-metadata syscall, and `df -h /any/path` from the
user's terminal returns the same numbers. If a future per-mount
selector lands, the input still goes through `realpath(3)` on the
QML side for display purposes (see the disk-metric section below)
rather than via a syscall-side allowlist.

### Disk metric: known limitations of `statvfs(3)`

`MetricsBackend.qml` calls `reader.statvfs(backend._diskMount)`
(default `"/"`) and renders the result through
`MemInfoParser.diskUsagePercent`. Two caveats inherent to `statvfs`
itself that we explicitly accept rather than work around:

1. **Symlinks are followed.** `statvfs("/data")` where `/data → /mnt/big`
   silently reports `/mnt/big`'s numbers. Users won't normally hit
   this with the `/` default; flagged for the future per-mount
   selector — the UI should resolve the path with `realpath(3)` and
   display the canonical form so what's queried matches what's shown.

2. **Bind mounts / btrfs subvols / overlayfs are not detected.** On
   Bazzite (our documented target) `/` is a btrfs subvol on an
   rpm-ostree composed tree; `statvfs` reports "size of the whole
   btrfs pool", not the per-subvol quota a user might expect. Same
   story for overlay roots (containers, OCI bundles) and `mount
   --bind` setups. Long-term fix is `statfs(2)` (note: different
   syscall) checking `f_type` to detect `BTRFS_SUPER_MAGIC`,
   `OVERLAYFS_SUPER_MAGIC`, `TMPFS_MAGIC`, and either warning or
   exposing a per-mount selector — out of scope for the MVP. If a
   user reports "disk ring shows wrong size on my btrfs", the cause
   is here.

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
| **Plasma-Wayland** | ✓ via auto-XWayland | `forceXWaylandUnderWayland` in `desktop_hints.cpp` force-sets `QT_QPA_PLATFORM=xcb` before `QGuiApplication`, gated on `QStandardPaths::findExecutable("Xwayland")` so the app falls back to native Wayland (no Conky hints) if XWayland is missing rather than crashing. STICKY + BELOW + SKIP_TASKBAR + SKIP_PAGER are all declared as a `_NET_WM_STATE` property pre-map (not via ClientMessage — see § below); STICKY may not surface in `xprop` on a single-virtual-desktop session but the hint is still set |
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

**Recovery path for users who hit the regression:** the binary
accepts a `--open-settings` (alias `--settings`) flag that loads a
minimal recovery QML root showing just the `SettingsDialog`:

```bash
pkill -f ring-monitor-standalone
ring-monitor-standalone --open-settings
```

Implementation: `standalone/main.cpp` parses argv before
`QGuiApplication` (the flag also gates `forceXWaylandUnderWayland`,
which must mutate `QT_QPA_PLATFORM` before Qt initialises) and uses
the parsed boolean to choose which QML root to load —
`SettingsOnlyRoot.qml` in recovery mode, `Main.qml` otherwise. The
recovery root hosts only `ConfigStore`, `Theme`, `UpdateChecker`,
and `SettingsDialog`; the rings widget (MetricsBackend Timer
polling `/proc`, MainContent's tree, Screen Connections,
WindowAnchor) is not constructed at all. Quit is wired to the
dialog's `onClosing` signal — intent-driven (not based on
`Window.visibility === Hidden`), so a future programmatic hide
(modal color picker, hide-and-reopen) doesn't accidentally kill the
recovery process. Config writes go through the same `QSettings`
file the running widget reads, so the user kills + relaunches the
running widget to apply (`Qt.labs.settings` doesn't watch — a
live-reload via `QFileSystemWatcher` is out of scope for the minimal
recovery).

The previous shape (now reverted) threaded a `_settingsOnly`
boolean through eight sites — argv parse, two startup gates, a
context property, a `typeof`-guarded QML alias, `visible:` binding,
a branched `Component.onCompleted`, a Qt.quit Connections — and
still constructed the full widget invisibly. The MetricsBackend
Timer kept polling, every slider drag in the dialog triggered a
`setGeometry` on the hidden window, and a stuck `statvfs` would
have blocked the GUI thread of the recovery process. Loading a
separate root is shorter, doesn't waste syscalls, and the
priority-driven quit is robust to future programmatic-hide
features.

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

### `_NET_WM_STATE` is set as a property, not via a ClientMessage

`applyDesktopWindowHints` in `standalone/desktop_hints.cpp` writes the
state list (`STICKY + SKIP_TASKBAR + SKIP_PAGER + BELOW`) using
`xcb_change_property` with `XCB_PROP_MODE_REPLACE`, **not** via
`xcb_send_event` ClientMessages. The reason is the call timing: the
function runs from `main.cpp` **between** `engine.loadFromModule` and
`app.exec()`, when the QML `visible: true` show() request has been
queued but the event loop hasn't started yet — the X server hasn't
seen `MapWindow` for our window. EWMH §"_NET_WM_STATE" assigns
ClientMessages to runtime mutation of **mapped** windows; KWin (and
mutter through XWayland) silently drop ClientMessages targeting
unmapped windows, which is why STICKY / SKIP_TASKBAR / SKIP_PAGER
used to show up flaky in `xprop` after launch.

Setting the property pre-map is the spec-compliant declaration path
— the WM reads it during `MapRequest` and treats absent or empty as
"no states". `_NET_WM_STATE_BELOW` is included explicitly: Qt's xcb
plugin would add it post-map via ClientMessage (driven by
`Qt::WindowStaysOnBottomHint`), but our `REPLACE` would otherwise
clobber any pre-existing list, so being explicit removes the race
with Qt's init order. Text-guarded by `tests/desktop-hints.test.mjs`.

The **pre-map** requirement is also load-bearing for any future
caller: `applyDesktopWindowHints` only updates the WM's state view
because the property write happens before `MapWindow` is issued.
Calling it post-map (e.g. on a theme switch, runtime "show on all
desktops" toggle, or re-anchor after a monitor hot-plug) silently
fails — the property updates, but KWin / mutter only re-read the
state list at map time, so `xprop` would show the right value while
the WM behaviour stays unchanged. The contract is spelled out
above the declaration in `standalone/desktop_hints.h` and asserted
in debug builds via `Q_ASSERT(!window->isExposed())`. A future
"re-apply on theme switch" path needs a sibling helper that uses
`xcb_send_event(ClientMessage)` instead.

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

### Centring a QML `Window` must happen ONCE on the first `onVisibleChanged`, not on `Component.onCompleted` and not on every show

Two-layered rule:

1. **Not `Component.onCompleted`** — the `Screen` attached property
   reads the screen the Window currently lives on, but a hidden
   Window has not been assigned a screen yet. At onCompleted the
   dialog hasn't been shown, so `Screen.*` defaults to the primary
   screen. Multi-monitor users opening the dialog from a widget on
   a secondary screen would otherwise see the dialog pop on primary.

2. **Not on every `onVisibleChanged`** — a dialog instance is
   typically constructed once and `show()` is called repeatedly
   across the app lifetime. An unguarded `onVisibleChanged: if
   (visible) recenter()` runs on every false→true transition,
   wiping any position the user dragged the dialog to on a previous
   open. Gate the recenter with a one-shot boolean (`_centered`)
   so it runs exactly ONCE on the first hidden→visible transition:
   that's when `Screen.*` is finally accurate, and after that Qt's
   QWindow already remembers the position across hide/show cycles
   — which matches every other window-managed dialog on the
   platform.

Always add the `Screen.virtualX/Y` offsets to the centring formula
— `Window.x` is virtual-desktop-absolute on X11, so a bare
`(Screen.width - dialog.width) / 2` lands on the leftmost screen
regardless of which screen Qt mapped the window to.

Canonical example: `SettingsDialog.qml::_recenterOnCurrentScreen()`
+ its `_centered` gate. The pattern applies to any new QML Window
that wants to centre itself on its actual destination screen and
respect the user's subsequent placement.

### `ScrollView` body widths use `ScrollView.availableWidth`, not `parent.parent.width`

Reaching the StackLayout (or other outer container) width from
inside a `ScrollView` by walking `parent.parent.width` traverses
the `Flickable` that `ScrollView` instantiates internally. Qt has
reorganised that internal hierarchy across 6.x point releases
(`Flickable` → `contentItem` → other levels of indirection across
6.4 / 6.5), and a future point release can quietly break the
binding without a qmllint warning.

The documented public input is `ScrollView.availableWidth`
(content width minus the vertical scrollbar). Give the ScrollView
an `id` and bind the child's width to `<id>.availableWidth`.

Canonical example: `SettingsDialog.qml` — three ScrollViews each
binding their body's width to their own `.availableWidth`.

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
