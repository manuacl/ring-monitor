---
name: refresh-plasma-widget
description: Reload the ring-monitor Plasma widget after a code change — copies the source over a dedicated dev install (ring-monitor_dev), clears qmlcaches, restarts plasmashell, then greps the journal for QML/ringmon errors. Plasma-host workflow only (the standalone binary doesn't need this — just relaunch it). Use when the user says "actualise l'app", "reload widget", "refresh ring-monitor", or after modifying contents/ui/*.qml, contents/config/main.xml, or metadata.json.
user-invocable: true
---

# Refresh ring-monitor Plasma widget

Rafraîchit l'instance de dev du widget après une modif locale. Le code source est **copié** (pas de symlink) dans une install Plasma dédiée `~/.local/share/plasma/plasmoids/ring-monitor_dev`, dont le `metadata.json` est patché pour utiliser un plugin Id distinct (`ring-monitor_dev`) et un nom distinct (`Ring Monitor (dev)`).

Pourquoi copier au lieu de symlinker :

1. **Coexistence Store.** Le plugin Id distinct laisse coexister cette install de dev avec la version stable installée depuis le **KDE Store** (`dev.manuacl.ringmonitor`). On peut donc à tout moment tester l'installation Store et le widget de dev côte à côte dans le même panneau, sans collision d'Id.
2. **Source protégée.** L'ancien symlink était dangereux : retirer/désinstaller le widget faisait suivre le lien à KDE et **supprimait tout le dossier source** du repo. Une copie est jetable — virer `ring-monitor_dev` n'efface qu'elle, jamais le repo.

## Quand l'utiliser

- L'utilisateur dit "actualise l'app", "reload", "refresh ring-monitor", "raffraîchis le widget", "rebuild".
- Tu viens de modifier un fichier sous `contents/ui/*.qml`, `contents/config/main.xml`, ou `metadata.json` et tu veux confirmer le rendu.

## Quand NE PAS l'utiliser

- Erreur de parsing QML qui empêche le widget de charger → préfère le mode debug isolé documenté dans `docs/development.md` § "Standalone preview" :
  ```bash
  setsid -f plasmawindowed dev.manuacl.ringmonitor < /dev/null > /tmp/plasmawindowed.log 2>&1
  ```
  puis lire `/tmp/plasmawindowed.log`. La fenêtre standalone montre les erreurs sans nécessiter de restart plasmashell.
- Premier ajout du widget au panneau → ce skill installe/écrase la copie `ring-monitor_dev`, mais c'est à l'utilisateur d'ajouter ensuite *Ring Monitor (dev)* au panneau via « Ajouter des widgets ». Le skill ne place pas le widget.

## Procédure

Avertir l'utilisateur d'abord : **l'écran flashe pendant le restart, et sur Wayland le lockscreen peut brièvement apparaître (re-unlock nécessaire)**.

Exécuter depuis la racine du repo, en un seul appel Bash. Copie (en écrasant) la source vers l'install de dev, patche le `metadata.json` copié pour un Id + un nom distincts, puis vide les caches et redémarre plasmashell :

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

Puis vérifier le journal en un second appel :

```bash
journalctl --user --since "10 sec ago" 2>/dev/null | grep -iE "ring-?mon|qml" | grep -v breezerc | head -30
```

## Rapport attendu

- **Journal vide** → "Widget rechargé, journal propre."
- **Lignes d'erreur QML** → citer les 3-5 premières lignes pertinentes ; pointer le fichier/numéro de ligne si l'erreur en mentionne un. Ne pas tenter de fixer automatiquement — laisser l'utilisateur décider.
- **`breezerc` floode parfois malgré le grep -v** : si le filtre laisse passer des lignes manifestement sans rapport, les ignorer.

## Pourquoi cette procédure

`rsync -a --delete` écrase l'install de dev à l'identique de la source (les fichiers supprimés côté source disparaissent côté dest — un symlink le faisait gratuitement, une copie incrémentale non). Les `--exclude` gardent le paquet propre (pas de `.git`/`tests`/`docs` dans le plasmoid). Le patch `jq` sur le `metadata.json` **copié uniquement** (jamais la source) donne l'Id distinct qui permet la coexistence avec la version Store.

`systemctl --user restart plasma-plasmashell.service` est la commande robuste sur Bazzite Wayland Plasma 6 (50+ utilisations validées en session de dev). `kquitapp6 plasmashell && kstart plasmashell` n'est pas fiable sur cet environnement.

Les trois qmlcaches couvrent les trois containers Plasma qui peuvent loader des fichiers du plasmoid : `plasmashell` (widget dans le panneau), `kcmshell6` (dialogue de config via System Settings), `plasmawindowed` (debug standalone). Vider les trois en bloc coûte ~0 (les caches se reconstruisent à la volée) et évite la classe de bugs "modif config dialog invisible" documentée dans `CLAUDE.md` § Common pitfalls.

Détails dans `docs/development.md` § "When edits show up", "Restarting plasmashell", "Reading the journal".
