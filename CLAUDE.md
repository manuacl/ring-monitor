# Ring Monitor

Plasma 6 widget for system monitoring with circular ring gauges.
Built from scratch as a learning project (user knows React, not QML — so
explanations should map back to React concepts when introducing new QML ones).

Target: KDE Plasma 6 Wayland on Bazzite.

## Stack

- **QML (Qt 6)** — declarative UI, React-like property bindings
- **PlasmoidItem** from `org.kde.plasma.plasmoid` — widget root
- **`org.kde.ksysguard.sensors`** — live system data via `Sensors.Sensor`
- **`org.kde.kirigami`** — KDE theming (`Kirigami.Theme.highlightColor` etc.)
- **QtQuick.Shapes** — `Shape` + `ShapePath` + `PathAngleArc` for ring rendering

## Structure

- `metadata.json` — KPlugin descriptor. Plugin id: `dev.manuacl.ringmonitor`
- `contents/ui/main.qml` — entry, lays out the rings + holds the Sensor instances
- `contents/ui/Ring.qml` — reusable circular gauge component (track + arc + label)

## Dev workflow

A symlink (already in place) makes edits live:

```
~/.local/share/plasma/plasmoids/dev.manuacl.ringmonitor → ~/projects/ring-monitor
```

Preview standalone:

```bash
pkill -f "plasmawindowed.*ringmonitor"
plasmawindowed dev.manuacl.ringmonitor &
```

For desktop use: clic droit bureau → Ajouter widgets → Ring Monitor.
Re-running plasmawindowed picks up file changes automatically.

If the symlink is removed and replaced by a copy install:

```bash
kpackagetool6 -t Plasma/Applet -i .   # install (first time)
kpackagetool6 -t Plasma/Applet -u .   # upgrade after edits
```

## Sensors reference

Plasma 6 exposes ksysguard sensors. Common IDs we use:

- `cpu/all/usage` — total CPU usage (0–100)
- `cpu/cpu0/usage` … `cpu/cpuN/usage` — per-core usage (user has 6 cores: i5-9600K)
- `memory/physical/usedPercent` — RAM used %
- `gpu/gpu0/usage` — GPU usage (NVIDIA via nvidia-smi exposed by ksysguard)
- `network/all/download` / `network/all/upload` — bytes/s
- `disk/all/read` / `disk/all/write` — bytes/s

Pattern in QML:

```qml
Sensors.Sensor { id: cpuSensor; sensorId: "cpu/all/usage" }
// Bind: cpuSensor.value
```

## Aesthetic guidelines

User-chosen direction: **"anneaux modernes épurés"** (clean modern rings).
Visual rules to respect:

- **Hierarchy**: primary metric bright/bold, secondary info subtle (lower opacity,
  thinner strokes). Don't compete for attention.
- **One color family per ring group**: use `Kirigami.Theme.highlightColor` as the
  anchor. Variants via opacity or HSL tweaks, NOT rainbow gradients (the Conky
  Ring Graph rainbow look was explicitly rejected as dated).
- **270° sweep starting at 135°** is the established arc shape. The 90° gap at
  the bottom is intentional (visual breathing room).
- **Rounded caps** on all arcs (`capStyle: ShapePath.RoundCap`).
- **Light font weight** for big numbers (`Font.Light`). Modern OS feel.
- **Smooth value transitions** via `Behavior on value { NumberAnimation ... }`.

## React → QML quick map for the user

| React                     | QML                                          |
|---------------------------|----------------------------------------------|
| Component                 | An `.qml` file with a root `Item`/etc.       |
| `useState`                | `property real foo: 0`                       |
| JSX expression `{x + 1}`  | Direct binding `width: parent.width / 2`     |
| onClick                   | `MouseArea { onClicked: ... }`               |
| `useEffect`               | `Component.onCompleted`, `onValueChanged`    |
| CSS flexbox               | `RowLayout` / `ColumnLayout`                 |
| Conditional render        | `visible: condition` or `Loader`             |

Bindings are automatic — when `cpuSensor.value` changes, anything depending on it
re-renders. No "setState" needed.

## Known gotchas

- `plasmawindowed` may exit silently on QML parse errors. Check journal:
  `journalctl --user -n 50 --since "30 sec ago" | grep -v breezerc | grep qml`
- Shape/ShapePath items use the Shape's coordinate space. Bind `PathAngleArc.centerX`
  to the **Shape's** `width/2`, not the Item's — give the Shape an `id` and reference it.
- `org.kde.ksysguard.sensors` won't error if a sensor ID doesn't exist; `value` will
  just stay at 0 (or NaN). Be defensive: `cpuSensor.value || 0`.
