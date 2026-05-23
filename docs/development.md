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

## Standalone preview

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
