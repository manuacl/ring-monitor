# Visual components

## `Ring.qml`

A circular gauge: 270° arc starting at 135° (90° gap at the bottom).

### Public properties

| Property | Default | Description |
|---|---|---|
| `label` | `""` | text above the value (e.g. `"CPU"`) |
| `value` | `0` | current percentage (0–100) |
| `ringColor` | `"#3daee9"` | arc color — injected by the parent via the platform/Theme adapter |
| `textColor` | `"#eeeeee"` | value/label color — same injection |
| `unit` | `"%"` | string appended to the rendered value |
| `textOpacity` / `trackOpacity` / `arcOpacity` | `1.0` / `0.15` / `1.0` | per-layer opacity |
| `nestedValues` | `[]` | optional 0–100 array → concentric inner rings |

### Sizing

`size = Math.min(width, height)` drives all derived dimensions via
`RingGeometry.dimensionsFor(size)`. Below ~40 px the floors kick in
(`ringStroke ≥ 4`, `labelPx ≥ 8`, …) so the gauge stays legible.

### Animation

`displayValue` mirrors `value` through a `Behavior on displayValue`
(`NumberAnimation`, 400 ms, `OutCubic`). This means sudden value changes
are eased rather than snapped. Nested rings have their own `dv` with the
same easing.

### Tests

`tests/qml/tst_Ring.qml` covers the QML bindings (label text, value text
with rounding + custom unit, sweep angle at 0/50/100 %, dimensions,
nestedValues array). The pure math is covered by
`tests/ring-geometry.test.mjs`.

## `MetricRow.qml`

One row of the metrics list:

```
[≡] [☑ CPU]  Overall processor usage
        └─ <optional extraContent — indented sub-row>
[≡] [☐ RAM]  Physical memory used   (description dimmed because disabled)
```

### Public API

| Property / signal | Description |
|---|---|
| `metricId` | the id (`"cpu"`, `"ram"`, …) — looked up in `MetricsCatalog.labelFor()` for the checkbox text |
| `enabled` | whether this metric is selected; drives the checkbox state + the row's dimmed/disabled look |
| `description` | secondary label to the right of the checkbox |
| `extraContent` | optional `Component` rendered indented below the main row (e.g. CPU's "show cores" toggle) |
| `unit` | layout unit (default `18`) — injected by the parent via `platform/Theme.unit` |
| `smallSpacing` | row spacing (default `4`) — injected by the parent via `platform/Theme.smallSpacing` |
| `toggled(bool on)` | emitted when the user clicks the checkbox |

### Disabled-state convention

When `enabled === false`:

1. **The master checkbox keeps full opacity** so the user can clearly
   see and re-enable it.
2. **The description label dims** (`opacity: 0.3` vs `0.55`).
3. **The `extraContent` Loader gets `enabled: row.enabled`.** QML
   cascades `enabled` to descendants — child controls (a sub-CheckBox)
   become non-interactive AND get the theme's disabled rendering. Don't
   render an "active" sub-option for a metric whose master toggle is
   off.

This convention applies to **all** rows that may carry `extraContent`,
not just CPU. New child-bearing metrics get it for free by setting
`extraContent`.

### Tests

`tests/qml/tst_MetricRow.qml` pins each rule:

- Label rendering per id (`CPU`, `RAM`, `SWAP`, `GPU`, `DISK`, unknown
  → uppercase fallback).
- Description passthrough, default empty.
- `_checked` mirrors `enabled`, click emits `toggled(true/false)`.
- Disabled dims description, **does not** dim the checkbox.
- `extraContent` null → Loader inactive/invisible; set → active +
  visible + implicitHeight grows.
- Disabled master → `extraLoader.enabled === false` → child CheckBox
  inherits `enabled === false`. Enabled master → child interactive.

## `DraggableList.qml`

Generic vertical list with drag-to-reorder, deferred commit.

### Public API

| Property / signal | Description |
|---|---|
| `model` | any `ListModel` or JS array |
| `rowHeight` | minimum row height (rows may grow if `rowContent` is taller) |
| `rowSpacing` | gap between rows |
| `rowContent` | `Component` for the row content; the loaded root reads `parent.rowModel` / `parent.rowIndex` (see below) |
| `showHandle` | toggle the move icon on the left |
| `highlightColor` | active-row border + tint (default `"#3daee9"`) — inject via `platform/Theme.highlightColor` |
| `backgroundColor` | dragged-row fill (default `"#1e1e1e"`) — inject via `platform/Theme.backgroundColor` |
| `smallSpacing` | inner row padding (default `4`) — inject via `platform/Theme.smallSpacing` |
| `iconSize` | drag handle icon size (default `16`) — inject via `platform/Theme.iconSize` |
| `reordered(int from, int to)` | emitted on drop when the order actually changed |

### Usage

```qml
DraggableList {
    model: orderModel
    rowHeight: theme.unit * 2

    // Theme tokens injected from the parent's platform/Theme instance.
    highlightColor: theme.highlightColor
    backgroundColor: theme.backgroundColor
    smallSpacing: theme.smallSpacing
    iconSize: theme.iconSize

    rowContent: Component {
        MetricRow {
            // DraggableList puts the row data on the Loader; read it
            // back via `parent`. See "Row data forwarding" below.
            readonly property string _metricId:
                parent && parent.rowModel ? parent.rowModel.metricId : ""

            metricId: _metricId
            enabled:  page.isEnabled(_metricId)
            // ...
        }
    }

    onReordered: function(from, to) {
        const next = Logic.applyMove(currentArr(), from, to)
        // sync your model + persist
    }
}
```

### How the drag works

Based on Qt 6's [Dynamic View Ordering tutorial](https://doc.qt.io/qt-6/qtquick-tutorials-dynamicview-dynamicview2-example.html).

- The handle is a `MouseArea` on the left strip. It uses Qt's native
  `drag.target: content` to make the row's `content` Rectangle follow
  the cursor along the Y axis — no manual `mapToItem`, no manual
  `_draggedY` bookkeeping. Qt's mouse grab + coordinate handling does
  the heavy lifting.
- `content.Drag.active: handleArea.drag.active` lights up Qt's
  drag-and-drop signalling. Each row carries a `DropArea` that records
  the hovered index in `_dropTarget` via `onEntered`. On release the
  `reordered` signal fires.
- `DropArea.onExited` resets `_dropTarget` to `_dragSource` whenever
  the cursor leaves a row. Without this the "drag away then back to
  origin" case would emit a (src, wrong) reorder — see the
  `SCENARIO_drag_away_then_back_to_origin_no_emit` test.
- Other rows shift visually via a `Translate` transform driven by
  `Logic.computeYShift()`. The shift magnitude is the **source row's**
  vertical extent (height + spacing), so variable-height rows work too
  (see MetricRow's `extraContent`).
- While dragging, `content` is reparented to `root.contentItem` via a
  `State` with `ParentChange` + `AnchorChanges` (the latter undoes
  the four anchors individually — `anchors.fill: undefined` is invalid
  in `AnchorChanges`).

### Row data forwarding (Loader → rowContent)

The `rowContent` Component lives in a different file from
`DraggableList.qml`. QML's implicit context-property propagation
through `Loader` is unreliable across Qt versions / KCM containers —
plain `model.X` inside the loaded item gives empty results. Workaround:
the `Loader` exposes `rowModel` and `rowIndex` as plain properties; the
loaded root reads them via `parent.rowModel` / `parent.rowIndex`.

This is the regression guard behind the
`DraggableListForwarding.test_rowContent_receives_metricId_via_parent_rowModel`
test.

### Drag tests

`tests/qml/tst_DraggableList.qml` exercises:

- Forwarding: `parent.rowModel.metricId` and `parent.rowIndex` arrive
  in the loaded rowContent.
- Drag down (row 0 → row 2), drag up (row 2 → row 0), drag to adjacent
  row — all emit `reordered(src, tgt)` with the right indices.
- No-op drag (no threshold cross) doesn't emit.
- **SCENARIO**: drag row 1 down to row 2 then walk back to row 1 and
  release → `_dropTarget` rewinds to 1 (via `DropArea.onExited`) and no
  reorder fires.

`tests/qml/tst_ReorderCycle.qml` chains a simulated drag with the
same `onReordered` handler `configMetrics` uses (`Logic.applyMove` →
`ListModel.clear + append`) and asserts the final list order.

### Gotchas (preserved across rewrites)

1. **`content`'s State must use individual anchors, not
   `anchors.fill`.** `AnchorChanges` can only undo each of the four
   anchors separately; `anchors.fill: undefined` triggers
   *"Cannot assign to non-existent property 'fill'"* and the whole
   delegate fails to load.
2. **Handle `MouseArea` is a SIBLING of `content`, not a child.**
   When `ParentChange` reparents `content` during a drag, a child
   `MouseArea` would be carried along — its local coordinate frame
   would shift mid-drag, producing chaotic events.
3. **Variable row heights need the per-frame source extent.** The
   `yShift` binding reads `root.itemAtIndex(_dragSource).height +
   rowSpacing` each frame, not a precomputed constant — without this,
   rows with `extraContent` (e.g. CPU's sub-toggle) would shift by the
   wrong amount.

## Platform adapters (`contents/ui/platform/`)

Thin Plasma-only adapters that the leaf components consume via
properties — keeps `Ring.qml`, `MetricRow.qml`, `DraggableList.qml`
free of `org.kde.*` imports. See
[`docs/plasma-isolation/plan.md`](plasma-isolation/plan.md) for the
broader context.

### `Theme.qml`

Item re-exposing Kirigami theme tokens under a stable surface:

| Property | Source |
|---|---|
| `textColor` | `Kirigami.Theme.textColor` |
| `highlightColor` | `Kirigami.Theme.highlightColor` |
| `backgroundColor` | `Kirigami.Theme.backgroundColor` |
| `unit` | `Kirigami.Units.gridUnit` |
| `smallSpacing` | `Kirigami.Units.smallSpacing` |
| `iconSize` | `Kirigami.Units.iconSizes.small` |

Instantiated once per top-level file (e.g. `main.qml`,
`configMetrics.qml`) with `id: theme`. Children read `theme.X` and
pass it to leaves as explicit properties — DIP, no scope-chain
trickery through Loaders.

Smoke-tested by `tests/qml/tst_Theme.qml`.

### `ThemedIcon.qml`

One-line wrap of `Kirigami.Icon`. Consumed by `DraggableList.qml` for
the drag handle icon. Standalone equivalent (future) will back this
with `Image { source: "image://theme/..." }`.

Smoke-tested by `tests/qml/tst_ThemedIcon.qml`.
