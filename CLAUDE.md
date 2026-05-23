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

## Config dialog gotchas (Plasma 6)

The widget exposes config keys via `package/contents/config/main.xml`. Plasma 6 then
creates `cfg_<keyName>` properties on each config page so `property alias cfg_x: control.value`
binds the control to the persisted setting. Pitfalls:

- **KDE bug 484541** — Plasma tries to set EVERY `cfg_<key>` from main.xml on EVERY
  config page, not just the keys that page handles. If a page doesn't declare a
  property for a key, the journal logs "Setting initial properties failed: ... does
  not have a property called cfg_X". Plasma 6 ALSO auto-generates
  `cfg_<key>Default` for the "Reset to defaults" feature — placeholders are needed
  for those too. Workaround: in EVERY page, declare empty placeholders for every
  config key it doesn't handle, AND for the `Default` variant of every key
  (including its own):
  ```qml
  // HACK: suppress KDE bug 484541 warnings
  property var cfg_otherKey
  property var cfg_otherKeyDefault
  property var cfg_ownKeyDefault   // even own keys need a *Default placeholder
  ```
- **`AnchorChanges` does NOT support `anchors.fill`.** To "undo" an
  `anchors.fill: parent` in a State, you must undo each of the four anchors it
  implicitly sets:
  ```qml
  AnchorChanges {
      target: someItem
      anchors.top: undefined
      anchors.bottom: undefined
      anchors.left: undefined
      anchors.right: undefined
  }
  ```
  Writing `anchors.fill: undefined` triggers "Cannot assign to non-existent
  property 'fill'" and the whole QML file fails to load.
- **`KCM.SimpleKCM` does NOT accept `anchors.fill: parent` on its content child.**
  The child should size itself implicitly. Using `anchors.fill: parent` triggers
  "Created graphical object was not placed in the graphics scene" and the page
  renders blank. Use `Layout.fillWidth: true` on the layout child and let it size
  vertically by its content.
- After editing `main.xml`, you must **restart plasmashell** for the new keys to
  be picked up:
  `systemctl --user restart plasma-plasmashell.service`
  Editing QML alone is hot-reloaded by the symlink, but config schema changes are not.

## Drag-and-drop reorderable list

Encapsulated in `contents/ui/DraggableList.qml` — a generic `ListView` that
takes a `rowContent` Component and emits `reordered(from, to)` on drop.

Three design choices were forced by hard-won debugging:

1. **No `Drag` / `DropArea`.** The Qt drag system was too opaque. State
   leaked across drags (`dropTargetIndex` would stick to the previous drop's
   position) and hit-testing depended on `Drag.hotSpot` in ways that became
   impossible to reason about. We replaced it with a single MouseArea per
   row that tracks `mouseY` via `positionChanged` and arithmetically
   computes which row the cursor is over (`computeDropTarget`).

2. **Pure logic in `ReorderLogic.js`, unit-tested.** Three pure functions —
   `computeDropTarget(mouseY, rowStep, count)`, `computeYShift(rowIndex,
   src, tgt, step)`, and `applyMove(arr, from, to)` — capture every
   interesting case. Tests in `tests/reorder-logic.test.mjs` run via
   `node --test tests/`. When a regression shows up ("can't return to
   origin", "stuck on last drop position"), write the failing test first,
   then fix the function. The QML side just calls these helpers.

3. **`Translate` on the Rectangle only, not on the delegate Item.** The
   per-row "make-room" shift is a `Translate` transform applied to `rowBg`
   (the visual). The delegate `Item` (`row`) stays at its model position so
   the handle MouseArea — anchored to `row` — never moves. The cursor's
   y-coordinate maps unambiguously to model index via floor division.

Two additional constraints inherited from the earlier (broken) attempt:

- **Size the dragged Rectangle with explicit width/height + center anchors,
  NOT `anchors.fill: parent`.** `AnchorChanges` can only undo the four
  individual anchors, not the `fill` shorthand. With `anchors.fill: parent`,
  undoing the four individual anchors leaves the Rectangle at 0×0.
- **The drag-handle MouseArea is a SIBLING of `rowBg`, not a child.** When
  `ParentChange` reparents `rowBg` to the ListView during a drag, a child
  MouseArea would be carried along — its local coordinate frame shifts
  mid-drag, producing chaotic events.

### Using `DraggableList` from a config page

```qml
DraggableList {
    id: list
    model: orderModel              // ListModel
    rowHeight: Kirigami.Units.gridUnit * 2

    rowContent: Component {        // `index`, `model` available inside
        RowLayout {
            QQC2.CheckBox { text: model.metricId }
            QQC2.Label   { text: "..." }
        }
    }

    onReordered: function(from, to) {
        const next = Logic.applyMove(currentOrder(), from, to)
        orderModel.clear()
        for (let i = 0; i < next.length; i++) {
            orderModel.append({ metricId: next[i] })
        }
        commitOrder()   // persist as CSV in cfg_metricOrder
    }
}
```

### Running the tests

```bash
node --test tests/
```

All logic that the QML drag-and-drop relies on is covered. The QML/visual
side is intentionally thin glue.

## Orientation switch (Row vs Column)

To support both horizontal and vertical layouts with a single config toggle:

```qml
GridLayout {
    readonly property bool vertical: Plasmoid.configuration.orientation === "vertical"
    columns: vertical ? 1 : enabledList.length
    rowSpacing: 12
    columnSpacing: 12
    // delegates set Layout.fillWidth + Layout.fillHeight to expand into the cells
}
```

`GridLayout` handles both directions cleanly: `columns: 1` → vertical stack;
`columns: N` → single row of N items.

## Confirmed sensor IDs on this machine

User has i5-9600K (6 cores) + RTX 2070 + Ethernet `eno1` + disks sda/sdb/sdc/nvme0n1.
`busctl --user call org.kde.ksystemstats1 /org/kde/ksystemstats1 org.kde.ksystemstats1 allSensors`
confirmed these IDs (relevant subset):

- `cpu/all/usage`, `cpu/all/averageTemperature`, `cpu/all/coreCount`, `cpu/all/averageFrequency`
- `cpu/cpu0/usage` … `cpu/cpu5/usage` (per-core)
- `memory/physical/usedPercent`, `memory/swap/usedPercent`
- `gpu/all/usage`, `gpu/all/usedVram`, `gpu/all/totalVram`
- `gpu/gpu1/usage` ← note: NVIDIA shows up as `gpu1` (not `gpu0`) on this rig.
  Prefer `gpu/all/usage` for portability.
- `disk/all/usedPercent`, `disk/all/read`, `disk/all/write`
- `network/all/download`, `network/all/upload` (rates)
- `pressure/cpu/someTotal`, `pressure/memory/someTotal`, `pressure/io/someTotal`

To discover sensors on any machine:
```bash
busctl --user call org.kde.ksystemstats1 /org/kde/ksystemstats1 \
    org.kde.ksystemstats1 allSensors | tr "}" "\n" | grep -oE '"[a-z]+/[^"]+"' | sort -u
```

Non-percent sensors (rates, bytes, temperatures) need a `max` value before the
Ring component can render them as 0–100% — Ring currently assumes percent input.
