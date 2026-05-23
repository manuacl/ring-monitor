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
Bazzite, then reboot). On Fedora the binaries are named with a `-qt6`
suffix (`qmllint-qt6`, `qmlformat-qt6`); the bare names also exist in
`/usr/lib64/qt6/bin/`.

| Tool | Equivalent | Notes |
|---|---|---|
| `qmllint-qt6` | ESLint | configured via `.qmllint.ini` (`UnqualifiedAccess=info` to silence Plasma `i18n` / Kirigami false positives) |
| `qmlformat-qt6` | Prettier | opinionated, in-place formatter, default settings |
| `qmlls` | LSP server | autocomplete/diagnostics for editors |
| `qmltestrunner` | Jest-ish | QML-side unit tests (we don't use it — we test pure JS via Node) |

## Pre-commit hook

`.githooks/pre-commit` runs `qmlformat --inplace` then `qmllint` on staged
`.qml` files. It's checked into the repo but git won't pick it up
automatically — enable it once per clone:

```bash
git config core.hooksPath .githooks
```

After that, every `git commit` reformats QML changes in place (re-staging
them) and aborts the commit if `qmllint` reports any warning or error.
`Info`-level findings (the i18n / Kirigami false positives) are
non-blocking.

To bypass the hook in an emergency: `git commit --no-verify`.

## Installing the widget elsewhere

If the symlink isn't an option:

```bash
kpackagetool6 -t Plasma/Applet -i .   # first install
kpackagetool6 -t Plasma/Applet -u .   # upgrade
```
