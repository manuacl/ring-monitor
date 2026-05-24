---
name: refresh-widget
description: Reload the ring-monitor Plasma widget after a code change — clears qmlcaches, restarts plasmashell, then greps the journal for QML/ringmon errors. Use when the user says "actualise l'app", "reload widget", "refresh ring-monitor", or after modifying contents/ui/*.qml, contents/config/main.xml, or metadata.json.
user-invocable: true
---

# Refresh ring-monitor widget

Rafraîchit l'instance du widget installée dans le panneau Plasma de l'utilisateur après une modif locale. Le code source vit dans `~/projects/ring-monitor/`, monté dans Plasma via le symlink `~/.local/share/plasma/plasmoids/dev.manuacl.ringmonitor → ~/projects/ring-monitor` (voir `docs/development.md` § Layout).

## Quand l'utiliser

- L'utilisateur dit "actualise l'app", "reload", "refresh ring-monitor", "raffraîchis le widget", "rebuild".
- Tu viens de modifier un fichier sous `contents/ui/*.qml`, `contents/config/main.xml`, ou `metadata.json` et tu veux confirmer le rendu.

## Quand NE PAS l'utiliser

- Erreur de parsing QML qui empêche le widget de charger → préfère le mode debug isolé documenté dans `docs/development.md` § "Standalone preview" :
  ```bash
  setsid -f plasmawindowed dev.manuacl.ringmonitor < /dev/null > /tmp/plasmawindowed.log 2>&1
  ```
  puis lire `/tmp/plasmawindowed.log`. La fenêtre standalone montre les erreurs sans nécessiter de restart plasmashell.
- Premier setup (symlink absent) → utiliser `kpackagetool6 -t Plasma/Applet -i .` une fois, pas ce skill.

## Procédure

Avertir l'utilisateur d'abord : **l'écran flashe pendant le restart, et sur Wayland le lockscreen peut brièvement apparaître (re-unlock nécessaire)**.

Puis exécuter en un seul appel Bash :

```bash
rm -rf ~/.cache/plasmashell/qmlcache \
       ~/.cache/kcmshell6/qmlcache \
       ~/.cache/plasmawindowed/qmlcache && \
systemctl --user restart plasma-plasmashell.service && \
sleep 5
```

Puis vérifier le journal en un second appel :

```bash
journalctl --user --since "10 sec ago" 2>/dev/null | grep -iE "ringmon|qml" | grep -v breezerc | head -30
```

## Rapport attendu

- **Journal vide** → "Widget rechargé, journal propre."
- **Lignes d'erreur QML** → citer les 3-5 premières lignes pertinentes ; pointer le fichier/numéro de ligne si l'erreur en mentionne un. Ne pas tenter de fixer automatiquement — laisser l'utilisateur décider.
- **`breezerc` floode parfois malgré le grep -v** : si le filtre laisse passer des lignes manifestement sans rapport, les ignorer.

## Pourquoi cette procédure

`systemctl --user restart plasma-plasmashell.service` est la commande robuste sur Bazzite Wayland Plasma 6 (50+ utilisations validées en session de dev). `kquitapp6 plasmashell && kstart plasmashell` n'est pas fiable sur cet environnement.

Les trois qmlcaches couvrent les trois containers Plasma qui peuvent loader des fichiers du plasmoid : `plasmashell` (widget dans le panneau), `kcmshell6` (dialogue de config via System Settings), `plasmawindowed` (debug standalone). Vider les trois en bloc coûte ~0 (les caches se reconstruisent à la volée) et évite la classe de bugs "modif config dialog invisible" documentée dans `CLAUDE.md` § Common pitfalls.

Détails dans `docs/development.md` § "When edits show up", "Restarting plasmashell", "Reading the journal".
