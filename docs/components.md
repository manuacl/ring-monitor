# Visual components

## `Ring.qml`

A circular gauge: 270° arc starting at 135° (90° gap at the bottom).

### Public properties

| Property | Default | Description |
|---|---|---|
| `label` | `""` | text above the value (e.g. `"CPU"`) |
| `value` | `0` | current percentage (0–100) |
| `ringColor` | `Kirigami.Theme.highlightColor` | arc color |
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

### Why not `import Shapes 1.0`?

QtQuick 6 makes `Shape` available via the standard `import QtQuick.Shapes`
(no version). `PathAngleArc` is the right primitive for this shape — it
takes a start + sweep instead of cartesian endpoints, which maps directly
to the geometry helpers.

## `DraggableList.qml`

Generic vertical list with drag-to-reorder.

### Public API

| Property / signal | Description |
|---|---|
| `model` | any ListModel or JS array |
| `rowHeight` | row height in px |
| `rowSpacing` | gap between rows |
| `rowContent` | `Component` for the row's main content (loaded inside each delegate) |
| `showHandle` | toggle the move icon on the left |
| `reordered(int from, int to)` | emitted on drop when the order actually changed |

### Usage

```qml
DraggableList {
    model: orderModel
    rowHeight: Kirigami.Units.gridUnit * 2

    rowContent: Component {
        RowLayout {
            QQC2.CheckBox { text: model.metricId }
            QQC2.Label   { text: "..." }
        }
    }

    onReordered: function(from, to) {
        const next = Logic.applyMove(currentArr(), from, to)
        // sync your model + persist
    }
}
```

### Why we don't use `Drag` / `DropArea`

Original implementation used Qt's `Drag` + `DropArea`. Two bugs we could
not fix without replacing them wholesale:

1. **Stuck drop target.** After dropping at index N, subsequent drags
   would only "snap" to index N. Indices were reset to -1 in
   `onReleased` but the `DropArea.onEntered` signal didn't fire for the
   second drag's hover events.
2. **Return to origin invisible.** Dragging away then back over the
   source row didn't re-trigger `onEntered` for the source row's
   `DropArea`, so the "make-room" gap didn't visually return to the
   source position.

Both symptoms point to `DropArea`'s internal entry-state machine — which
is opaque from QML.

### Current approach: manual mouseY

A single `MouseArea` per row, anchored to the delegate `Item` (never
reparented). On `positionChanged`:

```qml
const p = mapToItem(root.contentItem, mouse.x, mouse.y);
root._draggedY = p.y;
root._dropTarget = Logic.computeDropTarget(p.y, _step, count);
```

Hit-testing is now `floor(mouseY / rowStep)`, fully covered by tests.
Visual reparenting of `rowBg` to the ListView still happens (via a
`ParentChange` in the `held` state), but it's decoupled from hit-testing.

### Three constraints inherited from the previous attempt

1. **Size the dragged Rectangle with explicit width/height + center
   anchors, NOT `anchors.fill: parent`.** `AnchorChanges` can only undo
   the four individual anchors, not the `fill` shorthand. With
   `anchors.fill: parent` + `AnchorChanges` undoing top/bottom/left/right,
   the Rectangle ends up 0×0.

2. **Handle MouseArea is a SIBLING of `rowBg`, not a child.** When
   `ParentChange` reparents `rowBg` during a drag, a child MouseArea
   would be carried along — its local coordinate frame shifts mid-drag,
   producing chaotic events.

3. **Translate applies to `rowBg`, not to the delegate `Item`.** The
   per-row "make-room" shift is a `Translate` transform on the visual
   only. The delegate `Item` stays at its model position so the handle
   MouseArea anchored to it never moves, and the cursor's y-coordinate
   maps unambiguously to model index.
