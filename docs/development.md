# Development workflow

## Layout

```
~/projects/ring-monitor/                 — source of truth
~/.local/share/plasma/plasmoids/dev.manuacl.ringmonitor → ~/projects/ring-monitor   (symlink)
```

The symlink means edits in `~/projects/ring-monitor/contents/ui/*.qml`
are picked up by Plasma without copy-installing.

Set it up once:

```bash
mkdir -p ~/.local/share/plasma/plasmoids
ln -s ~/projects/ring-monitor ~/.local/share/plasma/plasmoids/dev.manuacl.ringmonitor
```

## When edits show up

| Change | Hot-reloaded? | What to do |
|---|---|---|
| QML file under `contents/ui/` | yes — restart `plasmawindowed` or reopen the config dialog | nothing for desktop instance; restart for `plasmawindowed` |
| `contents/config/main.xml` (schema) | no | `systemctl --user restart plasma-plasmashell.service` |
| `metadata.json` | no | restart plasmashell |
| `.js` logic file | yes | nothing |

## Standalone preview (Plasma host, debugging the widget body)

```bash
pkill -f "plasmawindowed.*ringmonitor"
plasmawindowed dev.manuacl.ringmonitor &
```

The Bash tool kills detached children, so to keep `plasmawindowed`
running:

```bash
setsid -f plasmawindowed dev.manuacl.ringmonitor < /dev/null > /tmp/plasmawindowed.log 2>&1
# or:
systemd-run --user --scope --collect plasmawindowed dev.manuacl.ringmonitor &
```

## Standalone build (separate binary, no Plasma host)

The standalone build produces a single executable that runs outside
plasmashell — it's the future cross-distro target documented in
[`plasma-isolation/plan.md`](plasma-isolation/plan.md).

```bash
cmake -B build
cmake --build build -j2   # bound the jobs — see the OOM note below
./build/ring-monitor-standalone
```

> **Bound the parallelism.** `qt_add_qml_module` emits one C++ TU per
> QML file (~40), so `cmake --build --parallel` with a bare `-j`
> (unbounded) can spawn dozens of `cc1plus` at once and OOM a
> memory-tight box. Pass an explicit `-jN` (e.g. `-j2` with a browser /
> IDE open). The release script `scripts/build-appimage.sh` does this
> for you (caps at `nproc`, honors `CMAKE_BUILD_PARALLEL_LEVEL`).

To produce a local **AppImage** end-to-end (configure → build → AppDir
→ linuxdeploy), run `scripts/build-appimage.sh` — the same script CI and
the release pipeline use (see [`releasing.md`](releasing.md)). It needs
a Qt ≥ 6.5 with `qmlimportscanner` on `PATH` plus `curl`.

Headless smoke test (no display required — confirms the QML root
loads, e.g. after relocating a module or editing `QML_FILES`):

```bash
QT_QPA_PLATFORM=offscreen timeout 4 ./build/ring-monitor-standalone
echo "exit=$?"
```

Read the exit code: **124** = `timeout` killed a still-running process
= the QML root loaded and the app stayed up (success). **1** = the app
returned early — `rootObjects().isEmpty()`, i.e. the QML root failed to
load (commonly a file missing from `QML_FILES`, see
[`../contents/ui/platforms/standalone/CLAUDE.md`](../contents/ui/platforms/standalone/CLAUDE.md)).
Note this bail is **silent** (no stderr), so the exit code is the
signal, not the log.

**Footgun when relaunching:** don't `pkill -f ring-monitor-standalone`
from the same shell line that then launches it — `pkill -f` matches
against full command lines and will match (and kill) your own launching
command, so the new instance never survives (you'll see exit `144`).
Kill the old instance by PID (`pkill` in its own separate command, or
`kill <pid>`), then launch in a fresh command. Also respect the
≥30 s spacing between relaunches (kwin soft-hang risk — see the
standalone `CLAUDE.md`).

What you currently see: a 320×480 frameless transparent window
with a translucent blue rectangle. PR C added the X11 EWMH hints
(`_NET_WM_STATE_BELOW`, `SKIP_TASKBAR`, `SKIP_PAGER`, `STICKY`) so
the window behaves Conky-style — sits on the wallpaper, not in the
taskbar/pager, visible across workspaces. The actual metric
rendering arrives in PR D / E.

`decideWindowStrategy` (in `standalone/desktop_hints.cpp`) picks the
window path. On a Wayland session, if the build has layer-shell-qt
compiled in (`HAVE_LAYER_SHELL_QT`) and the desktop isn't GNOME, it
takes the **native wlr-layer-shell** path (`wayland_layer_shell.cpp`,
PR C2) — a bottom-layer surface, no Alt+Tab, click pass-through.

Otherwise (GNOME-Wayland, or a build without layer-shell-qt) it
auto-forces XWayland: `forceXWaylandUnderWayland` probes for the
`Xwayland` executable on `$PATH` and, if found, sets
`QT_QPA_PLATFORM=xcb` before `QGuiApplication` constructs. No manual
`QT_QPA_PLATFORM` needed.

If `Xwayland` is also not installed (minimal Sway/Hyprland install, a
user who removed `xorg-x11-server-Xwayland`), the binary falls
back to native Wayland — the EWMH hints in `applyDesktopWindowHints`
no-op (the X11 native interface returns nullptr), so the window
shows up as an ordinary frameless `WindowStaysOnBottomHint` Qt
window without the Conky integration. Install the `Xwayland`
package, or build with layer-shell-qt for the native path.

**Testing the native layer-shell path locally.** It's only compiled
in when `find_package(LayerShellQt)` succeeds. On Bazzite that's an
rpm-ostree layer + reboot:

```bash
rpm-ostree install layer-shell-qt-devel       # then reboot (no kf6- prefix)
cmake -B build -S . -DCMAKE_BUILD_TYPE=Release # logs "native Wayland path ENABLED"
cmake --build build --parallel 2               # bounded — see the OOM note above
QT_QPA_PLATFORM=wayland ./build/ring-monitor-standalone
```

Under KWin/sway/Hyprland-Wayland, confirm: rings on the wallpaper layer
anchored top-right, **absent from Alt+Tab**, clicks pass through, survives
a desktop click, right-click still opens the menu, the margin slider moves
it live. The AppImage gets this path via `scripts/build-layer-shell-qt.sh`
(CI compiles layer-shell-qt from source into the Qt prefix, same as Kirigami).

Both no-op branches (Xwayland missing on $PATH, and X11 native
interface returning null) emit a `qWarning(…)` on stderr / the
journal. To diagnose a "why is my window floating" report:

```bash
ring-monitor-standalone 2>&1 | grep -i "ring-monitor:"
# or, when launched from .desktop:
journalctl --user -n 60 --since "1 min ago" | grep ring-monitor
```

Verify the hints landed with `xprop`:

```bash
xprop -id "$(xdotool search --name 'ring-monitor' | head -1)" \
    _NET_WM_STATE _NET_WM_WINDOW_TYPE
# Expect: _NET_WM_WINDOW_TYPE_NORMAL (not OVERRIDE, not DESKTOP)
#         _NET_WM_STATE has BELOW, SKIP_TASKBAR, SKIP_PAGER, STICKY
# (STICKY may be missing on a default Plasma-Wayland session — single
#  virtual desktop — but the hint is still set; multi-desktop X11
#  sessions show all four.)
```

Build deps on Fedora/Bazzite: `qt6-qtbase-devel
qt6-qtdeclarative-devel kf6-kirigami cmake gcc-c++ libxcb-devel`.

### Settings-only recovery launch

If a compositor swallows the right-click on the wallpaper-layer
window and the user can't reach Settings or Quit, they can launch the
binary in recovery mode:

```bash
pkill -f ring-monitor-standalone
ring-monitor-standalone --open-settings   # or --settings
```

The recovery process renders only the SettingsDialog (no rings, no
EWMH hints). Closing the dialog terminates the process. Config writes
land in the same `~/.config/dev.manuacl/ring-monitor.conf`, so the
user relaunches the widget without the flag once configuration is
done. See § "Recovery path" in
`contents/ui/platforms/standalone/CLAUDE.md` for the full rationale.

## Restarting plasmashell

```bash
systemctl --user restart plasma-plasmashell.service
sleep 5
```

The whole desktop UI flickers; the lock screen may briefly come up on
Wayland (you'll need to re-unlock).

## Reading the journal

```bash
journalctl --user -n 60 --since "30 sec ago" | grep -iE "ringmon|qml" | grep -v breezerc
```

`breezerc` floods the journal on every interaction — always grep it out.

## Tooling

These ship in `qt6-qtdeclarative-devel` (install via `rpm-ostree` on
Bazzite, then reboot):

| Tool | Equivalent | Notes |
|---|---|---|
| `qmllint` | ESLint | configurable via `.qmllint.ini` |
| `qmlformat` | Prettier | opinionated, in-place formatter |
| `qmlls` | LSP server | autocomplete/diagnostics for editors |
| `qmltestrunner` | Jest-ish | QML-side unit tests (we don't use it — we test pure JS via Node) |

## Installing the widget elsewhere

If the symlink isn't an option:

```bash
kpackagetool6 -t Plasma/Applet -i .   # first install
kpackagetool6 -t Plasma/Applet -u .   # upgrade
```
