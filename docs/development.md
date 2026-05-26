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
cmake --build build
./build/ring-monitor-standalone
```

Headless smoke test (no display required — useful from CI later):

```bash
QT_QPA_PLATFORM=offscreen ./build/ring-monitor-standalone &
sleep 2 && kill %1
```

What you currently see: a 320×480 frameless transparent window
with a translucent blue rectangle. PR C added the X11 EWMH hints
(`_NET_WM_STATE_BELOW`, `SKIP_TASKBAR`, `SKIP_PAGER`, `STICKY`) so
the window behaves Conky-style — sits on the wallpaper, not in the
taskbar/pager, visible across workspaces. The actual metric
rendering arrives in PR D / E.

On Plasma-Wayland (and any Wayland session that doesn't yet have
native layer-shell support in our build), force XWayland to get the
Conky behaviour:

```bash
QT_QPA_PLATFORM=xcb ./build/ring-monitor-standalone
```

Under GNOME-Wayland the binary auto-detects mutter and force-sets
`QT_QPA_PLATFORM=xcb` itself (mutter doesn't implement
`wlr-layer-shell`, same fallback Conky uses there).

Verify the hints landed with `xprop`:

```bash
xprop -id "$(xdotool search --name 'ring-monitor' | head -1)" \
    _NET_WM_STATE _NET_WM_WINDOW_TYPE
# Expect: _NET_WM_WINDOW_TYPE_NORMAL (not OVERRIDE)
#         _NET_WM_STATE has BELOW, SKIP_TASKBAR, SKIP_PAGER
```

Build deps on Fedora/Bazzite: `qt6-qtbase-devel
qt6-qtdeclarative-devel kf6-kirigami cmake gcc-c++ libxcb-devel`.

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
