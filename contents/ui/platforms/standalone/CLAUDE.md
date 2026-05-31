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
| `MetricsBackend.qml` | Direct reads from `/proc/stat`, `/proc/meminfo`, `/proc/mounts` + `statvfs(3)`, hwmon/thermal sysfs, NVML | **PR D: CPU usage (`/proc/stat`) ✓** ; **PR E: RAM (`/proc/meminfo`) ✓** ; **CPU temp (hwmon / thermal-zone via `CpuTempDiscovery.js`) ✓** ; **NVIDIA GPU usage + temp (NVML via `NvmlReader`) ✓** ; **swap (`/proc/meminfo` `SwapTotal`/`SwapFree`, incl. zram) ✓** ; **disk: per-filesystem multi-partition rings (`/proc/mounts` + `statvfs` via `DiskDiscovery.js`, deduped by device, `$HOME` default) ✓ — replaced the broken `statvfs("/")` composefs hardcode** ; AMD/Intel GPU (sysfs) post-MVP |
| `ConfigStore.qml` | `Qt.labs.settings` reader/writer | **PR F1 ✓ — Settings root, defaults mirror `main.xml`** ; **PR F2 ✓ — SettingsDialog drives writes through this instance** |
| `SettingsDialog.qml` | Tabbed `Window` wrapping `core/MetricsBody` + `core/AppearanceBody` + `core/AboutBody`; opened via right-click on the widget or the update-available badge | **PR F2 ✓** |
| `Theme.qml` | Kirigami theme tokens + Qt.styleHints light/dark | **PR F1 ✓ — mirrors the Plasma adapter byte-for-byte** |
| `ThemedIcon.qml` | wraps `Kirigami.Icon` (same as Plasma adapter) | **PR F1 ✓ — one-liner mirror of the Plasma adapter** |
| `ColorPicker.qml` | wraps a plain `QQC2.AbstractButton` + `QtQuick.Dialogs.ColorDialog` (the Plasma adapter wraps `KQuickControls.ColorButton`, which is not a runtime dep of the standalone build) | **PR F2 ✓** |
| `Autostart` (C++ in `standalone/autostart.{h,cpp}`, registered via `QML_ELEMENT`) | Writes / removes `~/.config/autostart/dev.manuacl.ringmonitor.desktop` so the user can toggle "Start on login" from the Settings dialog. Plasma side uses plasmashell instead, so the toggle is hidden there (`AboutBody.autostartAvailable` gated). | **PR G ✓** |

## Platform-only pure logic lives here, not in `core/`

Besides the adapters, this directory holds the **standalone-only pure
logic**: `ProcStatParser.js` (`/proc/stat` → CPU %), `MemInfoParser.js`
(`/proc/meminfo` + disk %), `CpuTempDiscovery.js` (hwmon/thermal CPU-temp
sensor discovery). They're pure + Node-tested like any `core/*.js`, but
they sit here because only the standalone backend reads `/proc` + sysfs —
keeping them in `core/` would ship them as dead weight in the `.plasmoid`
package. (Mirror of `platforms/plasma/SensorPicking.js`.) Placement rule:
[`../../core/CLAUDE.md`](../../core/CLAUDE.md) § "Logic in dedicated
`.js` files".

## NVIDIA GPU via NVML (`dlopen`), not `nvidia-smi`

`NvmlReader` (`standalone/nvml_reader.{h,cpp}`, a `QML_ELEMENT` like
`ProcReader`) reads GPU usage + temperature from **NVML**
(`libnvidia-ml`) — the C library `nvidia-smi` itself wraps, and what
nvtop / btop / Conky / KDE's `ksystemstats` use. We deliberately do
**not** shell out to `nvidia-smi`: a per-poll process spawn is ~20 ms
(a dropped frame at 60 fps) and churns fork/exec; NVML calls are
microseconds, so `NvmlReader.sample()` runs synchronously in the 2 Hz
`_sample()` with no GUI-thread jank.

Load-bearing details:

- **`dlopen("libnvidia-ml.so.1")`** — the SONAME, which ships with the
  driver. **Not** linked at build time and **not** the bare `.so` dev
  symlink. So the binary builds with no NVIDIA toolkit and runs on
  AMD/Intel boxes: `dlopen` fails → `sample()` returns
  `available:false` → the GPU metric just stays 0. Never a hard
  dependency. Text-guarded by `tests/nvml-reader.test.mjs`.
- **NVML types are self-declared** in `nvml_reader.cpp` (opaque `void*`
  handle, `{uint gpu; uint memory}` util struct, `NVML_TEMPERATURE_GPU`
  = 0) — no `nvml.h` / CUDA header dependency. The btop/conky approach;
  the handful of signatures + the struct layout are stable NVML ABI.
- `nvmlInit_v2` is lazy (one-time ~150 ms driver handshake on the first
  `sample()`), the device-0 handle is cached, `nvmlShutdown` runs in the
  dtor. Each field (`nvmlDeviceGetUtilizationRates` /
  `nvmlDeviceGetTemperature`) is committed independently so one
  transient query failure doesn't drop the whole sample.
- Links `${CMAKE_DL_LIBS}` (libdl) — see `CMakeLists.txt`.

**Non-NVML GPUs go through `GpuDiscovery.js` (sysfs), only when NVML is
unavailable.** `MetricsBackend._sample()` gates the sysfs branch on
`!nvml.available`, so a proprietary-driver NVIDIA host never touches it. AMD
usage is `/sys/class/drm/card*/device/gpu_busy_percent` + amdgpu hwmon temp;
Intel is temp-only (i915 perf usage needs elevated perms). NVIDIA on the
open-source **nouveau** driver is also temp-only (issue #106): vendor `0x10de`
resolves to `vendor: "nouveau"`, `busyPath: null`, hwmon `temp1_input` — nouveau
has no sysfs usage counter (debugfs pstate is root-only). nouveau is the
**lowest-priority** vendor in `discoverGpu`, so a hybrid nouveau+AMD host still
picks the AMD card (usage + temp). The vendor-agnostic backend maps
`tempPath`-without-`busyPath` to `_gpuTempAvailable` without `_gpuAvailable`,
which is exactly the temp-only ring this needs.

## Poll cadence: 500 ms (2 Hz), matching Plasma

The `_sample()` `Timer` runs at **500 ms**, not 1 Hz. The Plasma
adapter doesn't set a rate — its `Sensors.Sensor` instances are pushed
by the ksysguard daemon, which polls at ~500 ms (measured on the dev
box with a `qml-qt6` probe subscribing to `cpu/all/usage`: steady
499–501 ms). A 1 Hz Timer here made the standalone rings step in
visibly coarser jumps than the Plasma widget for the same hardware.
500 ms also sits just above `core/Ring.qml`'s 400 ms value animation,
so each sweep finishes before the next sample — going below ~400 ms
would overlap easings. The `/proc/stat` CPU delta window shrinks to
0.5 s to match. Pinned by `tests/standalone-metrics-backend.test.mjs`
("polls on a Timer" → `interval: 500`).

## New QML/JS files must be added to `CMakeLists.txt` `QML_FILES`

The standalone binary compiles every `.qml` / `.js` into the
`RingMonitor.Standalone` module via an **explicit** `QML_FILES` list in
`qt_add_qml_module`. A new `core/*.js` or `core/*.qml` (or
`platforms/standalone/*.qml`) that isn't added to that list is not in
the module: any `import` of it fails, the QML root fails to load, and
the binary **exits `1` with no diagnostic** (silent
`rootObjects().isEmpty()` bail in `standalone/main.cpp`). The Plasma
build is unaffected (it loads from the filesystem / plasmoid package),
so this is a standalone-only trap. Guarded by
`tests/standalone-qml-module.test.mjs`.

A **C++ helper carrying `QML_ELEMENT`** (like `ProcReader` /
`NvmlReader`) is the `SOURCES` counterpart of the same rule: add its
`.cpp` + `.h` to `qt_add_qml_module(... SOURCES ...)`, **and** any
library it needs to `target_link_libraries` (e.g. `${CMAKE_DL_LIBS}`
for `NvmlReader`'s `dlopen`). Omit it and the type is never registered
— a QML file instantiating it (`NvmlReader { }`) fails to load with
the same silent `exit 1`, even though the `.cpp` itself compiles
without error. (This bit us once when a commit's `CMakeLists.txt`
edit was lost: the helper built in isolation but the QML element was
undefined at load time.)

## `qmllint` Info lines on the C++ `ProcReader` helper are benign

Running `qmllint-qt6` on `MetricsBackend.qml` emits, for every
`reader.read(...)` / `reader.statvfs(...)` / `reader.listDir(...)`
call:

```
Info: Member "read" not found on type "ProcReader" [missing-property]
```

This is **not** a failure. `ProcReader` is a C++ type registered via
`QML_ELEMENT`; its type metadata only exists inside the CMake build, so
the standalone `qmllint` invocation (run without that build context)
can't see the `Q_INVOKABLE` methods. The lines are severity `Info`, and
**qmllint still exits 0** — the pre-commit/CI/finish-branch gates gate
on the exit code, not the Info output. Don't try to silence or "fix"
them.

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
user's terminal returns the same numbers. The disk multi-partition
selector reads each selected filesystem via the **async** pair
(`requestStatvfs` / `cachedStatvfs` — see "Disk metric" below), not the
synchronous `statvfs()`, so an unresponsive mount can't freeze the GUI
thread.

`blockDeviceInfo()` and `canonicalHome()` are the same metadata-only,
allowlist-free shape as `statvfs` (they enumerate the `/dev/disk`
symlink farm and resolve `$HOME` — the same listing `ls -l
/dev/disk/by-label` / `readlink ~` give any user, no file contents).
They back the disk multi-partition discovery: `blockDeviceInfo()`
returns `{ "/dev/sdaN": { uuid, label } }` (UUID = the stable partition
id, label = the volume name shown in the picker), and `canonicalHome()`
resolves `/home/<user>` → `/var/home/<user>` so `DiskDiscovery` can
match `$HOME` against the real mountpoints for the default selection.

`listDir()` shares the `/proc` + `/sys` allowlist, but the **bare roots
`/proc` and `/sys` need an explicit exact-match** alongside the
`/proc/` / `/sys/` prefix tests: `QDir::cleanPath` strips the trailing
slash, so both `/proc` and `/proc/` arrive as `/proc` and would miss a
`startsWith("/proc/")` gate. Process enumeration for the CPU tooltip
(issue #69) lists the `/proc` root to find pid dirs — without the
exact-root clause `listDir("/proc")` silently returns `{}` (empty
tooltip, no error). Any future sensor enumerating a root (e.g. listing
`/sys` itself) needs the same exact-match + a `tests/proc-reader.test.mjs`
guard.

### Disk metric: per-filesystem discovery (multi-partition ring)

The disk ring is **one equal-thickness concentric ring per selected
mounted filesystem**, centre = their average. `MetricsBackend.qml`
discovers filesystems from `/proc/mounts` (via `ProcReader.read`),
deduplicates them by device through `DiskDiscovery.js`, and reads each
selected partition's usage **off the GUI thread** via the async
`reader.requestStatvfs(<mountpoint>)` / `reader.cachedStatvfs(...)` pair
(see "`statvfs` runs off the GUI thread" below) + `MemInfoParser.diskUsagePercent`
(df(1)'s formula). Selection persists as the `enabledPartitions` CSV;
empty = the `$HOME`-bearing filesystem.

Identity + labels: each partition's **id** is its fs UUID and its
**label** is the volume label, both resolved by
`ProcReader.blockDeviceInfo()` (walks `/dev/disk/by-uuid` +
`/dev/disk/by-label`, readlinks to the device). This mirrors ksysguard's
Plasma-side keying (UUID + volume name), so the two platforms label the
same filesystem identically (e.g. the root volume's label).

**Why dedup by device matters (the composefs trap, now fixed).** The old
`statvfs("/")` hardcode was *actively wrong* on every rpm-ostree host:
there `/` is a **composefs read-only overlay** (~47M, always
~100% full), while real storage is the btrfs root mounted at `/var`,
`/var/home`, `/etc`, `/sysroot`, … — **one device, five mountpoints**.
`DiskDiscovery.parseMounts` drops the overlay (its device field isn't a
`/dev` path, so the `/dev/` prefix test excludes composefs/tmpfs/fuse in
one rule), and `buildPartitions` collapses the five sda3 mounts into a
single root partition — exactly what ksysguard shows. `squashfs` is
additionally skipped (loop-mounted system images).

Remaining `statvfs` caveats we accept: it follows symlinks and reports
per-*filesystem* (not per-subvol/quota) numbers — `df /var/home` and
`df /var` return the same total because they're the same btrfs volume.
That's correct for "how full is the disk my files live on", which is the
question the ring answers.

**`statvfs` runs off the GUI thread (issue #48).** `statvfs(3)` blocks
uninterruptibly on an unresponsive mount (stale NFS/CIFS, hung autofs,
spun-down USB), so `partitionValue(id)` must NOT call the synchronous
`reader.statvfs()` — it would freeze the whole widget for the syscall's
duration. Instead it calls the async pair on `ProcReader`:
`requestStatvfs(mount)` kicks a background read on a **detached worker
thread** and `cachedStatvfs(mount)` returns the last-good value (empty →
0% until the first read lands). On completion the helper emits
`statvfsReady(mount)`; `MetricsBackend` bumps a dedicated `_partTick` so
the binding re-renders. A stuck mount then just holds its last-good ring
value while every other ring keeps updating. Three invariants make it
safe:
- **Detached, not pooled.** A `QThreadPool` dtor's `waitForDone()` would
  block *process exit* forever on a mount stuck in `statvfs`; a detached
  thread is reaped by the OS at exit instead, so quitting never hangs.
- **In-flight dedup** (`m_statvfsInFlight`): a mount already being read
  isn't re-launched, so a hung mount freezes exactly one thread, never a
  pile.
- **Throttle** (`kStatvfsMinIntervalMs`, below the 500 ms poll): keeps
  re-evaluating the QML binding every render from spinning the syscall,
  and breaks the `statvfsReady → _partTick → re-request` loop.

The local-disk common case is unaffected: `statvfs` on `/dev/sd*` /
`nvme*` returns in microseconds, so the worker finishes within a tick.

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
| **GNOME-Wayland (mutter)** | ✓ via auto-XWayland | Same path as Plasma-Wayland; mutter ships XWayland by default, so the probe always succeeds. mutter has no wlr-layer-shell, so it deliberately stays on the XWayland path even when layer-shell-qt is compiled in (`decideWindowStrategy` excludes `XDG_CURRENT_DESKTOP=*GNOME*`) |
| **KWin-Wayland / sway / Hyprland (wlroots-Wayland)** | ✓ native layer-shell (PR C2) when layer-shell-qt is bundled; else ✓ via auto-XWayland | `decideWindowStrategy` returns `WaylandLayerShell` → `wayland_layer_shell.cpp` makes the window a `wlr-layer-shell` **bottom-layer** surface (anchored to the configured corner, default top-right, `KeyboardInteractivityOnDemand`, exclusive zone 0). No Alt+Tab, no input capture, survives a desktop click — fixes all the XWayland warts below. When layer-shell-qt isn't compiled in (`HAVE_LAYER_SHELL_QT` undefined, e.g. a dev box without the lib) the same session falls back to the XWayland EWMH path |

PR C2 added the native `wlr-layer-shell` path via KDE's **layer-shell-qt**, an
**optional** build dep (`find_package(LayerShellQt QUIET)`). The AppImage CI
compiles it from source into the Qt prefix (`scripts/build-layer-shell-qt.sh`,
mirroring the Kirigami build, pinned to the **v6.0.x** tag = Qt 6.6 floor) and
bundles the wayland platform plugin + layer-shell shell-integration plugin
(`scripts/build-appimage.sh`). On the maintainer's box, getting the headers is an
`rpm-ostree install layer-shell-qt-devel` + reboot (note: Fedora's package has no
`kf6-` prefix); without them the build is X11/XWayland-only and byte-for-byte the
pre-C2 behaviour.

Four load-bearing decisions, the last three settled by **live testing** under
KWin-Wayland (none are surfaced by the offscreen CI smoke-test, so don't "tidy"
them away):

1. **Per-window opt-in, NOT the global `useLayerShell()`.** `wayland_layer_shell.cpp`
   calls `LayerShellQt::Window::get(window)` on the rings window only. The global
   `LayerShellQt::Shell::useLayerShell()` sets `QT_WAYLAND_SHELL_INTEGRATION`
   process-wide, which turned the **right-click menu's popup and the settings
   dialog into fullscreen, un-dismissable layer surfaces**. The per-window
   `setShellIntegration()` mechanism has existed since layer-shell-qt v6.0.0 (it's
   why `useLayerShell()` is deprecated since 6.6 / Qt 6.5) — so v6.0.x on the
   AppImage's Qt 6.6 supports it too. main.cpp must never call `useLayerShell()`.
2. **`bottom` layer, NOT `background`.** SCENARIO: on `background` a left-click on
   the desktop raised Plasma's wallpaper/desktop containment over the widget and it
   **vanished** — the exact occlusion the X11 `_NET_WM_WINDOW_TYPE_DESKTOP` had.
   `bottom` sits above the wallpaper/containment, below normal windows.
3. **`KeyboardInteractivityOnDemand`, NOT `None`.** SCENARIO: the context menu is an
   `xdg_popup`; the compositor only installs the popup grab (which sizes/positions
   it and lets click-away / Escape dismiss it) when the parent surface can take
   seat focus. `None` left the menu fullscreen + un-closeable. `OnDemand` takes
   focus only while interacting; the widget still never enters a switcher.
4. **Configure before show.** The layer-shell role is assigned at `wl_surface`
   creation, so `Main.qml` keeps the root `visible: !WaylandLayerShell.active`
   (hidden on the layer path) and `_anchor()` calls `WaylandLayerShell.configure(...)`
   then flips `visible = true`. Anchors + margins are live-settable, so the
   placement controls work at runtime (`configure` re-commits on every
   re-anchor). Positioning is anchors+margins, not `WindowAnchor.setGeometry`
   (an X11 QTBUG-57608 workaround, irrelevant on Wayland). The anchor corner
   is caller-chosen (`windowAnchorCorner`, issue #98); `Main.qml` resolves it
   to anchor edges + per-axis margins via `WindowPlacement.js`
   (`cornerToAnchorSpec`), the same module the X11 path uses for its origin.

The GNOME exclusion is an `XDG_CURRENT_DESKTOP` heuristic, not a runtime registry
probe — cheap, and a wlroots compositor that mis-reports it only degrades to
XWayland, never breaks.

### Window-integration changes need a live compositor test

The offscreen CI smoke-test (`QT_QPA_PLATFORM=offscreen`, exit 124 = pass)
**cannot** see compositor behaviour: layer-shell layer / keyboard-interactivity,
EWMH hints, popup sizing, and desktop-click survival are all invisible to it — it
exits green regardless. PR C2's two worst bugs (vanish-on-desktop-click from the
wrong layer, fullscreen un-closeable menu from the global `useLayerShell()`) both
passed the smoke-test and were caught **only** by running on a real KWin-Wayland
session. So: before merging any change to `desktop_hints.cpp`,
`wayland_layer_shell.cpp`, or `Main.qml`'s window flags / `visible` / `_anchor()`,
run the binary on a real compositor and verify the behaviour by eye (rings
placement, Alt+Tab absence, desktop-click survival, right-click menu, settings
dialog). CI green is necessary, not sufficient.

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

This wart is specific to the **XWayland / X11** path. The native
layer-shell path (PR C2) fixes it: a wlr-layer-shell bottom-layer
surface never participates in any switcher by design, so on
wlroots / KWin Wayland with layer-shell-qt bundled the widget is
already absent from Alt+Tab. The note remains for the XWayland
fallback (GNOME-Wayland, or a build without layer-shell-qt) — there
the user-side workaround still applies: KWin → Window Rules → match
window class `ring-monitor-standalone` with **"Skip switcher: Force
Yes"**.

### Window type is `_NET_WM_WINDOW_TYPE_NORMAL` + `_NET_WM_STATE_BELOW`

`applyDesktopWindowHints` rewrites the window type to `NORMAL` — it
must REPLACE the type, not omit it, to clear the
`_KDE_NET_WM_WINDOW_TYPE_OVERRIDE` Qt sets for `FramelessWindowHint`
windows (see the Alt+Tab note above). Paired with `_NET_WM_STATE_BELOW`
this pins the widget one layer **above** the wallpaper: a normally
managed, bottom-most window.

We moved here from `_NET_WM_WINDOW_TYPE_DESKTOP` (see the trade-off
record below). DESKTOP put the widget in plasmashell's own containment
layer, where a left-click on the desktop raised the opaque wallpaper
containment over it and the widget **vanished** (process alive, window
occluded — not a crash); it also had right-click forwarded to the
containment menu on some KWin point releases, hiding the only entry
point to Settings + Quit. NORMAL is a normally-managed window, so
right-click reaches the widget's own `MouseArea` reliably and the
widget survives a desktop click. The gravity-shift-on-resize that
DESKTOP used to mask is handled independently by `WindowAnchor`'s
atomic `setGeometry` (`standalone/window_anchor.h`, QTBUG-57608), so
the switch doesn't regress slider resize.

Scope: this X11/XWayland path is a durable fix for the committed
target — KWin, mutter, and xfwm4 are all EWMH stacking WMs that honour
`_NET_WM_STATE_BELOW`. Tiling and pure-Wayland-native are out of scope
(they need the wlr-layer-shell path, PR C2). See the
`project-standalone-target-des` and
`project-standalone-window-type-desktop-click` memories.

**Recovery path** (defensive net, kept from the DESKTOP era): the
binary accepts a `--open-settings` (alias `--settings`) flag that loads
a minimal recovery QML root showing just the `SettingsDialog`, in case
a compositor ever swallows the right-click:

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
recovery process.

`--open-settings` now reaches this separate-process root **only when no
widget is running**. When one is, the single-instance IPC (below) routes
the request to the live widget, which opens its IN-PROCESS dialog — so the
edit applies through the same `ConfigStore` the rings read, no kill+relaunch.
The separate root stays as the recovery fallback for a compositor that
swallows the right-click *and* no live widget to route to (config writes
there still need a manual relaunch, since `Qt.labs.settings` doesn't watch
the file).

### Single-instance guard + wake-up IPC (issues #103 / #104)

`standalone/single_instance.{h,cpp}` (a `QObject`, **not** a `QML_ELEMENT` —
instantiated in `main.cpp` and exposed to QML as the `SingleInstance` **context
property**, so the object QML connects to is the very one that called
`listen()`). Do **not** switch this to `qmlRegisterSingletonInstance` into the
`RingMonitor.Standalone` URI: registering a type into a module `qt_add_qml_module`
already owns clobbers its auto-registered C++ elements (`ProcReader` / `NvmlReader`
/ `WindowAnchor`), so the QML root fails to load with "ProcReader is not a type"
and the binary exits 1 (the offscreen smoke test catches it). Links `Qt6::Network`
(`QLocalServer`/`QLocalSocket`).

The first main-widget process owns a per-user `QLocalServer`. A later launch
connects as a client, writes one newline-terminated frame `"<intent> <version>\n"`,
and **acts only on the primary's explicit reply — never on a timeout**, so a
busy/wedged primary is never hijacked. The single `\n` is the frame delimiter:
reading up to it proves the whole line (intent AND version) arrived, so a split
delivery can't truncate the version (finding F1). Wire tokens
(`open-settings`/`show`/`defer`/`takeover`) are the shared
`SingleInstanceProtocol::` constants, defined once so a bare-literal typo can't
silently break the handshake. `main.cpp` runs the probe-then-act loop **before**
loading any QML root. The primary's verdict (`onNewConnection`):

- **`open-settings`** (any version) → `openSettingsRequested` → `Main.qml` shows
  its in-process `SettingsDialog`; replies `"defer"` → newcomer exits (#104).
- **`show`, same version** → `showRequested` (no-op: the widget is already
  visible); replies `"defer"` → newcomer exits. No pile-up (#103).
- **unknown / garbled intent** → replies `"defer"` (newcomer exits). An
  unrecognised message must **never** quit the widget.
- **`show`, different version** → replies `"takeover"` **first**, then
  `supersededRequested` (`Main.qml` → `Qt.quit`) + `m_server->close()`
  synchronously. The newcomer reads `"takeover"` and only then claims the socket.

Two load-bearing robustness rules (review-driven):

- **Claim is race-safe.** `tryListen()` calls `listen()` FIRST; only on
  `AddressInUseError` does it re-probe — a live owner ⇒ `Claim::Busy` (the
  caller re-probes and defers), a dead socket file ⇒ `removeServer` + retry. It
  must **never** `removeServer` unconditionally, or two simultaneous launches
  would each unlink the other's live socket and both become primary.
- **Reply before quit.** On supersede, `"takeover"` is written and flushed
  *before* `Qt.quit`, and `m_server->close()` runs synchronously so the socket
  frees deterministically before the newcomer's `tryListen()` (no late-dtor
  unlink race). Both ends read up to the `\n` frame delimiter (loop until it
  arrives) so a split delivery can't truncate the intent/version or the reply.

Version handling is **equality only, no ordering** (user decision): "the
AppImage you open is the one that runs" — any mismatch hands over, identical is
left running untouched. Text-guarded by `tests/single-instance.test.mjs`.

The **version-mismatch takeover** can't be exercised from the headless
CI/agent env (it reaps detached GUI processes), so it has a dedicated **live**
check: `scripts/test-single-instance.sh` (run on a real session). It probes the
four verdicts against a running primary via the raw socket, and with `--full`
builds a second `9.9.9-test` binary and asserts the real round-trip (old primary
exits, newcomer takes over the socket).

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

### Window type: click-through vs hide-on-desktop-click are a forced trade-off

On X11 / XWayland the two window types we can set trade one bug for
the other — **neither is fully correct**:

- `_NET_WM_WINDOW_TYPE_NORMAL` + `_NET_WM_STATE_BELOW` (**current**):
  **survives** the desktop click (stays visible), BUT it's a managed
  window that captures clicks over its area → the desktop underneath is
  no longer clickable there (icon selection, containment menu), and it
  shows in Alt+Tab (see the SKIP_* note above).
- `_NET_WM_WINDOW_TYPE_DESKTOP` (previous): clicks pass **through** to
  the wallpaper, BUT clicking the desktop raises Plasma's own desktop
  containment over our window → the widget vanishes behind the
  wallpaper (process alive, occluded).

We picked NORMAL: a widget that **stays visible** beats one that passes
clicks through but disappears on the first desktop click — the vanish
was a total UX loss, the lost click-through over a small ring area is
minor. The choice is durable for the committed target (KWin, mutter,
xfwm4 — all EWMH stacking WMs); see the `project-standalone-target-des`
memory.

The only path that gives **both** (visible on a desktop click AND
click pass-through) is a wlr-layer-shell surface — it doesn't
participate in window restacking and isn't a normal input target.
**PR C2 added that path** (`wayland_layer_shell.cpp`, on the `bottom`
layer — `background` reproduced the very vanish-on-desktop-click this
section is about), so on wlroots / KWin Wayland with layer-shell-qt
bundled neither trade-off applies. This X11/XWayland `NORMAL` analysis still governs the
XWayland fallback (GNOME-Wayland, or any build without layer-shell-qt):
there `NORMAL` remains the committed choice — don't flip-flop DESKTOP ↔
NORMAL to "fix" one symptom. Full live-test notes in the
`project-standalone-window-type-desktop-click` memory.

### Initial `_anchor()` must be deferred via `Qt.callLater`

`Main.qml` calls `_anchor()` from `Component.onCompleted` to issue
the first atomic `setGeometry` against the Window. **Wrap that first
call in `Qt.callLater`** — do not call `_anchor()` directly. The
synchronous boot order is:

1. `engine.loadFromModule` → `Component.onCompleted` fires
2. `applyDesktopWindowHints(window)` swaps the window-type to
   `_NET_WM_WINDOW_TYPE_NORMAL` (called from `main.cpp` right after
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

### Don't bind `QtDialogs.ColorDialog.selectedColor` to a source property

`ColorPicker.qml` wraps `QtQuick.Dialogs.ColorDialog` (the only
`QtDialogs` user — Plasma uses kquickcontrols). Do **not** write
`selectedColor: root.color`: the live binding re-pins the dialog's
selection to the source, so the user's pick is overwritten and
`onAccepted` re-reads the OLD colour → the colour silently never applies
(the swatch never updates). Seed it imperatively on each open instead:
`onClicked: { dialog.selectedColor = root.color; dialog.open() }`.
Guarded by `tests/qml/tst_ColorPicker.qml` (the "selectedColor not
live-bound to color" test fails on the binding).

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

### Sysfs availability flags must use a liveness model, not path non-emptiness

When a metric caches a sysfs path at startup (discovery), derive its
`_available` flag from **whether this tick's read succeeded**, not from
the cached path being non-empty. A path string never self-clears when a
device is removed (eGPU Thunderbolt unplug, `rmmod amdgpu`, driver
reload); only a failed read reveals the loss.

Pattern (canonical example: `_gpuAvailable` / `_gpuTempAvailable` in
`MetricsBackend.qml`):

```javascript
var valid = false;
if (backend._somePath) {
    var raw = reader.read(backend._somePath);
    if (isFinite(parse(raw))) {
        backend._someValue = parse(raw);
        valid = true;            // ← liveness flag, not path check
    }
}
backend._someAvailable = valid; // disappears in ≤1 tick on device removal
```

**Anti-pattern** (do not use): `backend._someAvailable = backend._somePath !== ""`
— the path stays non-empty forever after discovery, so the ring shows
stale frozen values after device removal. Caught in PR #82.

### Sysfs discovery retry gate: use the resolved output, not a detection sentinel

When re-trying sysfs discovery within a bounded window (e.g. a kernel
module that loads a few seconds after the widget autostarts), gate the
retry on **whether the resolved output is still empty** — not on a
"chip/card was detected" flag. A device can be found early without any
usable paths (Intel DRM node present before the i915 hwmon settles); a
detection flag would close the retry window before the path lands.

Canonical pattern (mirrors the CPU temp gate):

```
// CPU temp:  !backend._cpuTempPath && attempts < max
// GPU sysfs: (!backend._gpuBusyPath || !backend._gpuTempPath) && attempts < max
```

For a **multi-path** metric like the GPU (usage + temp), the gate is
`||`, not `&&`: keep retrying while **any** expected path is still empty.
`&&` would close the window the moment the *first* path resolved,
stranding the second for the whole session — the AMD case where
`gpu_busy_percent` exists at boot but the `amdgpu` hwmon registers a few
seconds later (issue #83). Single-path metrics (CPU temp) have only one
term, so the distinction doesn't arise there.

Retry stops once **all** expected paths resolve — not as soon as the
chip is identified, and not as soon as the first path lands. If no path
ever lands within the window, the retry stops at the cap and the metric
stays hidden (correct for a genuinely absent sensor). Caught in PR #82
(`!_gpuVendor` closed the gate before hwmon loaded on an Intel host with
a late-settling driver) and #83 (the `&&` two-path variant).

### Same surface, intentionally different *values* — don't "fix" these

The same-surface rule is about the property/function **shape**, not the
numbers. Because the two backends read genuinely different sources
(ksysguard vs `/proc`+sysfs+NVML), a few metrics legitimately read
different on the two builds for the same hardware. These were reviewed
and **left divergent on purpose** (2026-05-29) — each build shows the
number native to its ecosystem. Do not try to force them equal:

- **Disk usage %** — standalone uses `df`'s formula
  (`used/(used+avail)`, the reserved-for-root blocks are invisible),
  matching the `df` command. Plasma reads ksysguard's `usedPercent`,
  which counts the reservation — matching Dolphin and the rest of KDE.
  On a near-empty ext4 the gap is ~5%. ksysguard exposes no
  bavail/`available` leaf, so Plasma *can't* compute the `df` number
  anyway. Standalone targets non-KDE desktops where `df` is the neutral
  reference; Plasma matches its own ecosystem. See `MemInfoParser.diskUsagePercent`.
- **CPU temperature** — standalone reads the hwmon **package** sensor
  ("Package id 0" / `Tctl`), the BIOS/lm-sensors headline number.
  Plasma uses `cpu/all/averageTemperature` (the mean of the per-core
  sensors); ksysguard exposes **no package sensor** (only per-core +
  avg/max/min), so Plasma can't show the package value. ~4°C apart on
  this hardware. See `CpuTempDiscovery.js`.
- **GPU usage %** — both read NVML, but it's a volatile rolling-window
  counter; two independent 500 ms pollers sampling at different phases
  disagree transiently. This is sampling jitter, **not** a bug — the
  ring's value animation already smooths it.

## Compositor-specific window setup

The standalone window has to integrate into the desktop as a Conky-
style widget: always on the wallpaper layer, click-inert on left
button, right-click + hover captured. This is **per-compositor**
work that lives in either `Main.qml` (`flags:`, `screen` anchoring)
or a small C++ helper called from `standalone/main.cpp` (for native
protocol bits qt6 doesn't expose):

| Compositor | Mechanism |
|---|---|
| X11 (Xorg or XWayland) | `_NET_WM_WINDOW_TYPE_NORMAL` + EWMH hints `sticky + below + skip_taskbar + skip_pager` |
| KWin-Wayland | `wlr-layer-shell-unstable-v1`, `layer: background`, anchor + margin |
| sway / Hyprland | same as KWin |
| GNOME-Wayland (mutter) | force XWayland via `QT_QPA_PLATFORM=xcb` env injection at startup, then EWMH hints |

PR C wired up the X11/XWayland rows (`desktop_hints.cpp`); PR C2 wired
the KWin/sway/Hyprland rows natively (`wayland_layer_shell.cpp`, gated on
the optional layer-shell-qt). `decideWindowStrategy` (`desktop_hints.cpp`)
is the single dispatcher that maps the session to one of the three
mechanisms above. `Main.qml`'s `Qt.FramelessWindowHint |
Qt.WindowStaysOnBottomHint` flags remain as the cross-compositor baseline
underneath whichever path is selected.

## Maximize what lives in `core/`

Same rule as everywhere in this repo, but the standalone seam is
where it bites hardest. Every line of logic duplicated between
`platforms/plasma/` and `platforms/standalone/` is a line that has
to be fixed twice. When you find logic that BOTH platforms need,
push the pure part down into `core/*.js` so it's written and tested
once. Logic only one platform needs still goes into a pure,
Node-tested `.js` module — it just lives beside that platform's
adapter (e.g. [`SensorPicking.js`](../plasma/SensorPicking.js) is
plasma-only, so it sits in `platforms/plasma/`; the `/proc` parsers
+ `CpuTempDiscovery.js` here are standalone-only). The placement
rule: [`../../core/CLAUDE.md`](../../core/CLAUDE.md) § "Logic in
dedicated `.js` files".

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
