---
name: refresh-plasma-widget
description: Reload the ring-monitor Plasma widget after a code change — copies the source over a dedicated dev install (ring-monitor_dev), clears qmlcaches, restarts plasmashell, then greps the journal for QML/ringmon errors. Plasma-host workflow only (the standalone binary doesn't need this — just relaunch it). Use when the user says "actualise l'app", "reload widget", "refresh ring-monitor", or after modifying contents/ui/*.qml, contents/config/main.xml, or metadata.json.
user-invocable: true
---

# Refresh ring-monitor Plasma widget

Refreshes the dev instance of the widget after a local edit. The source is **copied** (not symlinked) into a dedicated Plasma install at `~/.local/share/plasma/plasmoids/ring-monitor_dev`, whose `metadata.json` is patched to use a distinct plugin Id (`ring-monitor_dev`) and a distinct name (`Ring Monitor (dev)`).

Why copy instead of symlink:

1. **Store coexistence.** The distinct plugin Id lets this dev install live alongside the stable version installed from the **KDE Store** (`dev.manuacl.ringmonitor`). You can test the Store install and the dev widget side by side in the same panel at any time, with no Id collision.
2. **Source protected.** The old symlink was dangerous: removing/uninstalling the widget made KDE follow the link and **delete the whole source folder** of the repo. A copy is disposable — dropping `ring-monitor_dev` only erases that copy, never the repo.

## When to use it

- The user says "actualise l'app", "reload", "refresh ring-monitor", "rafraîchis le widget", "rebuild".
- You just modified a file under `contents/ui/*.qml`, `contents/config/main.xml`, or `metadata.json` and want to confirm the render.

## When NOT to use it

- A QML parse error that stops the widget from loading → prefer the isolated debug mode documented in `docs/development.md` § "Standalone preview":
  ```bash
  setsid -f plasmawindowed dev.manuacl.ringmonitor < /dev/null > /tmp/plasmawindowed.log 2>&1
  ```
  then read `/tmp/plasmawindowed.log`. The standalone window shows the errors without a plasmashell restart.
- First time adding the widget to the panel → this skill installs/overwrites the `ring-monitor_dev` copy, but it is up to the user to then add *Ring Monitor (dev)* to the panel via "Add Widgets". The skill does not place the widget.

## Procedure

Warn the user first: **the screen flashes during the restart, and on Wayland the lockscreen may briefly appear (re-unlock needed)**.

Run from the repo root, in a single Bash call. It copies (overwriting) the source into the dev install, patches the copied `metadata.json` for a distinct Id + name, then clears the caches and restarts plasmashell:

```bash
DEST=~/.local/share/plasma/plasmoids/ring-monitor_dev && \
rsync -a --delete \
      --exclude='.git' --exclude='.claude' --exclude='tests' \
      --exclude='docs' --exclude='node_modules' \
      ./ "$DEST"/ && \
jq '.KPlugin.Id = "ring-monitor_dev" | .KPlugin.Name = "Ring Monitor (dev)"' \
   "$DEST/metadata.json" > "$DEST/metadata.json.tmp" && \
mv "$DEST/metadata.json.tmp" "$DEST/metadata.json" && \
rm -rf ~/.cache/plasmashell/qmlcache \
       ~/.cache/kcmshell6/qmlcache \
       ~/.cache/plasmawindowed/qmlcache && \
systemctl --user restart plasma-plasmashell.service && \
sleep 5
```

Then check the journal in a second call:

```bash
journalctl --user --since "10 sec ago" 2>/dev/null | grep -iE "ring-?mon|qml" | grep -v breezerc | head -30
```

## Expected report

- **Empty journal** → "Widget reloaded, journal clean."
- **QML error lines** → quote the first 3-5 relevant lines; point at the file/line number if the error mentions one. Don't try to fix automatically — let the user decide.
- **`breezerc` sometimes floods despite the `grep -v`**: if the filter lets through obviously unrelated lines, ignore them.

## Why this procedure

`rsync -a --delete` overwrites the dev install to match the source exactly (files removed on the source side disappear on the dest side — a symlink got this for free, an incremental copy doesn't). The `--exclude`s keep the package clean (no `.git`/`tests`/`docs` in the plasmoid). The `jq` patch on the **copied** `metadata.json` only (never the source) provides the distinct Id that enables coexistence with the Store version.

`systemctl --user restart plasma-plasmashell.service` is the robust command on Bazzite Wayland Plasma 6 (50+ validated uses in dev sessions). `kquitapp6 plasmashell && kstart plasmashell` is unreliable on this environment.

The three qmlcaches cover the three Plasma containers that can load plasmoid files: `plasmashell` (widget in the panel), `kcmshell6` (config dialog via System Settings), `plasmawindowed` (standalone debug). Clearing all three in one go costs ~0 (the caches rebuild on the fly) and avoids the "config dialog edit invisible" class of bugs documented in `CLAUDE.md` § Common pitfalls.

Details in `docs/development.md` § "When edits show up", "Restarting plasmashell", "Reading the journal".
