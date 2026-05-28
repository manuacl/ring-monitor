# Visual components

## Body components — wrapper/body split

Three QML files in `contents/ui/core/` pair up with their Plasma wrapper at the top level of `contents/ui/`:

| Body (`core/`) | Wrapper (top level) | Role |
|---|---|---|
| `core/MainContent.qml` | `main.qml` | full widget (rings strip) |
| `core/AppearanceBody.qml` | `configAppearance.qml` | Appearance config page |
| `core/MetricsBody.qml` | `configMetrics.qml` | Metrics config page |

The body owns the rendering, the internal state, and the user
interaction. It imports zero `org.kde.plasma.*` and uses `qsTr()` for
i18n. It exposes plain QML properties for state, and receives
platform adapters (`theme`, `configStore`, `metrics`) as `var` props
where it needs runtime data.

The wrapper is **thin** (~40 lines). Its only job is the Plasma seam:
declare a `PlasmoidItem` / `KCM.SimpleKCM` root, instantiate the
platform adapters, and bridge Plasma's `cfg_<key>` magic properties
to the body's plain properties via `property alias` declarations.
The alias is bidirectional — Plasma writes `cfg_X = value` and the
body sees `body.X = value`; the body writes `body.X = value` and
the wrapper exposes `cfg_X = value` back to Plasma's config store.

For the Metrics page, `MetricsBody` additionally owns:
- a `ListModel` for the displayed metric order
- `loadOrder()` / `commitOrder()` to sync that model with
  `metricOrderCsv` (the bridged property)
- `isEnabled(id)` / `setEnabled(id, on)` for the CSV-encoded
  enabled-list manipulation (delegates to `MetricsCatalog`)
- the i18n `metricDescriptions` dictionary
- an `availableMetrics` input (the backend's live capability list,
  `null` = unknown → everything enable-able) and `isMetricAvailable(id)`,
  which drives each `MetricRow.available` to grey out metrics with no
  data source. The Plasma wrapper sources it from a `MetricsBackend`
  instantiated inside `configMetrics.qml` (the KCM page has no live
  backend of its own); the standalone `SettingsDialog` takes it injected
  from `Main.qml`'s running backend.

**No Plasma writes happen inside the body** — the body only ever
writes to its own properties; the alias propagates the change to
the wrapper's `cfg_*`, which Plasma's `SimpleKCM` flushes to KConfig
on Apply.

Smoke-tested by `tests/qml/tst_AppearanceBody.qml` and
`tests/qml/tst_MetricsBody.qml` — both load cleanly under
qmltestrunner since they only import Kirigami + QtQuick.Controls
(not the Plasma-only modules).

`AppearanceBody` also exposes three sizing properties consumed by
the standalone window auto-size (Plasma reads them too but the
panel container may ignore them):

- `ringSize` (Int, px) — per-ring side length. Slider range 80-800.
- `ringSpacingPercent` (Int, 0-25) — gap between rings as a
  percentage of `ringSize`. 7% reproduces the historic 12px default
  at the original `ringSize=180`. The slider that drives this
  property is hidden by default — the body exposes
  `ringSpacingVisible` (default `false`) which the standalone
  `SettingsDialog` flips to `true`. The Plasma wrapper leaves it
  default AND hardcodes `configStore.ringSpacingPercent` to `0`
  (overriding the schema default), because on the Plasma desktop
  containment the frame is user-dragged-fixed: a non-zero spacing
  eats into the available area and rings shrink to compensate, so
  the slider would be a visual no-op. Same opt-in pattern as
  `AboutBody.autostartAvailable`.
- `windowMargin` (Int, 0-200 px) — inset between the rings and the
  closest screen edge. Used by the standalone window to offset
  itself from the top-right anchor; the Plasma panel ignores it.
  The slider that drives this property is hidden by default — the
  body exposes `windowMarginVisible` (default `false`) which the
  standalone `SettingsDialog` flips to `true`. The Plasma wrapper
  leaves it default AND hardcodes `configStore.windowMargin` to `0`
  (the value is never read on the Plasma side, the hardcode makes
  the "unused on Plasma" intent explicit). Same opt-in pattern as
  `AboutBody.autostartAvailable`.

## `MainContent.qml` — implicit dimensions

`MainContent` is a `GridLayout` of N square rings (`Ring.qml`
delegates inside a `Repeater`). It's mounted on the Plasma host
(`contents/ui/main.qml`) as `fullRepresentation` **with no
`Layout.preferredWidth/Height` override**, so the panel allocation
is driven entirely by the layout's auto-computed `implicitWidth` /
`implicitHeight`. Sizing them wrong squashes every ring in the
panel slot — there is no auto-correction downstream.

The layout's implicits are derived from the **delegate** Layout
hints, not from an explicit binding on the GridLayout itself:
`QQuickLayout` ignores explicit `implicitWidth` / `implicitHeight`
on the layout and recomputes them from its children's
`Layout.preferredWidth` / `Layout.preferredHeight` on each polish
pass. The Ring delegate sets `Layout.preferredWidth: _ringSize` and
`Layout.preferredHeight: _ringSize`, which gives the expected
bounding box for `N` rings of side `ringSize` separated by a
`ringSpacing = round(ringSize × ringSpacingPercent / 100)` gap:

| `orientation`   | `implicitWidth`                            | `implicitHeight`                            |
|---|---|---|
| `"horizontal"`  | `N × ringSize + (N - 1) × ringSpacing`     | `ringSize`                                  |
| `"vertical"`    | `ringSize`                                 | `N × ringSize + (N - 1) × ringSpacing`      |

The standalone host (`platforms/standalone/Main.qml`) computes the
window size with the same formula on the `Window` side and uses
`anchors.fill: parent` on the embedded `MainContent`, so a regression
in the implicit-dimensions formula would not surface there — it only
hits the Plasma fullRepresentation path. Regression-guarded by
`tests/qml/tst_MainContent.qml`.

### The enabled-list derivation chain

`MainContent` derives the rendered ring list in three ordered steps so
the strip self-adapts to the host's real capabilities:

1. `_rawEnabledList` — `(enabledMetrics ∩ metricOrder)` in display order.
2. `_availableEnabledList` — `_rawEnabledList` filtered through
   `Catalog.filterByAvailable(..., metrics.availableMetrics)`, but **only
   once `metrics.loading` is false**. During warm-up the backend hasn't
   resolved every sensor, so the full configured strip keeps showing
   (with the 100% "warming up" sweep); on settle the metrics with no data
   source drop out. This runs **before** step 3 so split-mode never
   engages on an unavailable temperature metric.
3. `enabledList` — `_availableEnabledList` through `applyMergedTempMode`,
   which folds `cpuTemp`/`gpuTemp` into their base ring when merged.

The per-ring `_splitOn` reads `_availableEnabledList` (not the raw list)
for the same reason. A `null` `availableMetrics` (host predates the
surface, or hasn't reported) makes `filterByAvailable` a pass-through, so
nothing is hidden.

**Known warm-up skew (accepted tradeoff).** The gate uses `metrics.loading`,
which clears as soon as the *aggregate* sensors are ready (Plasma: cpu +
ram; standalone: the first `/proc/stat` sample). A metric whose own source
resolves slightly later — a per-GPU sensor reaching `Ready` a tick after
cpu/ram on Plasma, or the standalone CPU-temp hwmon path that resolves over
a bounded retry window — is briefly absent from `availableMetrics` at the
moment the gate clears, so its ring can drop then re-appear a tick or two
later (a short startup reflow). This is deliberate: `availableMetrics`
reports a metric only when there's *real* data behind it (`Sensor.Ready` /
a resolved path), and there is no clean signal that distinguishes
"still resolving" from "genuinely absent" — a non-existent ksysguard
sensor also sits in a non-`Ready` state indefinitely. Widening the gate to
"show until proven absent" would keep dead rings visible on hosts that lack
the metric, which is the exact problem this feature fixes. The sub-second
startup reflow is the lesser evil; per-partition disk values already hold
last-good across rebuilds via `_lastPartValue`, so the disk ring doesn't
flicker to 0 during it.

## `Ring.qml`

A circular gauge: 270° arc starting at 135° (90° gap at the bottom).

### Public properties

| Property | Default | Description |
|---|---|---|
| `label` | `""` | text above the value (e.g. `"CPU"`) |
| `value` | `0` | current percentage (0–100) |
| `ringColor` | `"#3daee9"` | arc color — injected by the parent via the platforms/plasma/Theme adapter |
| `textColor` | `"#eeeeee"` | value/label color — same injection |
| `unit` | `"%"` | string appended to the rendered value |
| `textOpacity` / `trackOpacity` / `arcOpacity` | `1.0` / `0.15` / `1.0` | per-layer opacity |
| `nestedValues` | `[]` | optional 0–100 array → thin concentric rings nested *inside* the main ring (CPU cores) |
| `equalValues` | `[]` | optional 0–100 array → equal-thickness concentric rings that *replace* the main arc, one per selected disk partition. When non-empty the main/split arcs hide and the centre shows `rawValue` (the parent passes the partition average). Distinct from `nestedValues`, which keeps the main ring. |
| `rawValue` | `NaN` | optional override for the centre text — when finite, the ring shows `Math.round(rawValue) + unit` instead of `value + unit`. Used by temperature rings where `value=tempToPercent(°C)` drives the sweep but the user reads the raw °C / °F. |
| `splitMode` | `false` | split the ring at the top into two half-arcs (see below) |
| `splitValue` | `0` | percentage (0–100) for the right half — usually a `tempToPercent(°C)` mapping |
| `splitRawValue` | `0` | raw value (e.g. °C) displayed in the right-side text |
| `splitUnit` | `"°"` | suffix appended to the right-side text |
| `showUpdateBadge` | `false` | when true, render a small coloured dot in the 90° bottom gap (just left of the label) that pulses slowly. Emits `updateBadgeClicked()` on click — the parent uses it to open the config dialog at the "New release" tab. Set by `MainContent` on the first ring only when `updateChecker.updateAvailable` is true. |

### Split mode

When `splitMode` is true the full 270° arc is hidden and two half-arcs
(135° each) render in its place, growing **bottom-up** from the edges
of the existing 90° gap and meeting at the top (12 h) when both inputs
hit 100%:

- **Left half** (`startAngle=135`, sweep `+131 × value/100`) — usage %.
- **Right half** (`startAngle=45`, sweep `−131 × splitValue/100`) —
  temperature, fed via `MetricsBackend.metricTempPercent(id)`.

The 131° (instead of the geometric 135°) bakes in an 8° symmetric gap
at the top (`SPLIT_GAP_ANGLE / 2` per side) so the two RoundCap
endpoints don't overlap when both halves reach the midpoint. Both
the active arcs and the static tracks use the same shortened sweep.

The center value text shrinks to 75% of `valuePx` and shifts ±18% of
the ring's size on either side of the geometric center; the new
`splitValueText` shows the raw °C reading with `splitUnit` suffix.
Cores rings (`nestedValues`) keep their full 270° sweep — they sit
below the value text and overlap is by design (the cores arcs render
at 0.55 opacity, the text on top stays readable).

The geometry constants and helpers (`LEFT_HALF_START`,
`RIGHT_HALF_START`, `HALF_SWEEP_ANGLE`, `leftHalfSweepFor`,
`rightHalfSweepFor`) live in `core/RingGeometry.js` and are unit-tested
in `tests/ring-geometry.test.mjs`.

### Equal mode (disk multi-partition)

When `equalValues` is non-empty the single main arc (and split halves)
hide, and N **equal-thickness** concentric rings render in their place —
one per selected filesystem, outermost at the main radius, each stepping
inward by `(stroke + gap)`. Up to `DISK_COMFORT_RING_COUNT` (5) rings use
the full `ringStroke`; past that the layout shrinks stroke + gap to keep
the stack inside the same envelope (`RingGeometry.equalRingLayout`). The
centre shows the partition **average** via `rawValue`.

This differs from `nestedValues` (CPU cores): cores are *thin* rings
nested inside a still-visible main ring; disk partitions are *full-stroke*
rings that **are** the gauge. Both render through the shared
[`ConcentricArc.qml`](#concentricarcqml) delegate.

### `ConcentricArc.qml`

One concentric track + active arc at a given `radius` / `stroke`, with the
same 400 ms OutCubic value smoothing as the main ring. Extracted from
`Ring.qml` so the two stacking modes share one renderer: the cores
`Repeater` passes the thin `nestedStroke` + reduced opacity factors
(`0.6` / `0.55`); the disk `Repeater` passes the full `ringStroke` + the
default `1.0` factors. Props: `radius`, `stroke`, `value` (0–100),
`ringColor`, `trackOpacity`, `arcOpacity`, `trackOpacityFactor`,
`arcOpacityFactor`. Covered by `tests/qml/tst_ConcentricArc.qml`.

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
| `available` | whether the host has a live data source for this metric (default `true`). A **separate axis** from `enabled`: when `false` the description dims and a "not detected" annotation appears. The checkbox is frozen only when the metric is **both unavailable and unchecked** (enabling it would render a dead 0% ring); an already-enabled metric that loses its source stays toggle-able so the stale selection can be unchecked. Fed by `MetricsBody.isMetricAvailable(id)`, which reads the backend's `availableMetrics`. |
| `description` | secondary label to the right of the checkbox |
| `extraContent` | optional `Component` rendered indented below the main row (e.g. CPU's "show cores" toggle) |
| `unit` | layout unit (default `18`) — injected by the parent via `platforms/plasma/Theme.unit` |
| `smallSpacing` | row spacing (default `4`) — injected by the parent via `platforms/plasma/Theme.smallSpacing` |
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

### Availability is a separate axis from enabled

`available` (default `true`) is independent of `enabled`/checked. The
checkbox binds `enabled: row.available || row.enabled` — interactive
whenever the metric has a data source OR is already checked. So it stays
toggle-able for an available metric (enable/disable freely) and for a
checked-but-now-unavailable one (uncheck a stale selection); only a metric
that is both unavailable and unchecked is frozen, since enabling it would
render a dead 0% ring. When `available === false` the description dims to
`0.3` (via the `_descriptionOpacity` helper, which avoids a nested ternary
across the two axes) and the `_unavailableLabel` ("not detected") shows. A
metric can flip back to available at runtime (a late-modprobed sensor),
re-enabling the row with no extra wiring.

### Tests

`tests/qml/tst_MetricRow.qml` pins each rule:

- Label rendering per id (`CPU`, `RAM`, `SWAP`, `GPU`, `DISKS`, unknown
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
| `dragKey` | drag-and-drop scope key (default `"row"`), applied to each row's `Drag.keys` and every `DropArea.keys`. **Required when one `DraggableList` is nested inside another's rows** (the disk-partition picker inside the metrics list, `dragKey: "diskPartition"`): an unkeyed `DropArea` accepts *any* drag source (Qt), so two unscoped lists cross-fire — the inner drag floats but never reorders because the outer list's `DropArea`s swallow the drop. |
| `highlightColor` | active-row border + tint (default `"#3daee9"`) — inject via `platforms/plasma/Theme.highlightColor` |
| `backgroundColor` | dragged-row fill (default `"#1e1e1e"`) — inject via `platforms/plasma/Theme.backgroundColor` |
| `smallSpacing` | inner row padding (default `4`) — inject via `platforms/plasma/Theme.smallSpacing` |
| `iconSize` | drag handle icon size (default `16`) — inject via `platforms/plasma/Theme.iconSize` |
| `reordered(int from, int to)` | emitted on drop when the order actually changed |

### Usage

```qml
DraggableList {
    model: orderModel
    rowHeight: theme.unit * 2

    // Theme tokens injected from the parent's platforms/plasma/Theme instance.
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

## Platform adapters (`contents/ui/platforms/plasma/`)

Thin Plasma-only adapters that `core/` components consume via
properties — keeps everything under `contents/ui/core/` free of
`org.kde.*` imports (the load-bearing invariant of the
plasma-isolation seam, enforced by the `finish-branch` skill). See
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
| `isDarkMode` | derived: `bool`, WCAG relative luminance of `backgroundColor` < 0.5 |

`isDarkMode` reacts to Plasma color-scheme switches because
`Kirigami.Theme.backgroundColor` itself reacts; consumers
(`MainContent.qml`'s `ringColor` binding via `ColorThemes.resolveColor`)
re-evaluate without a widget restart.

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

### `ColorPicker.qml`

Two-line wrap of `org.kde.kquickcontrols.ColorButton`. Consumed by
`AppearanceBody.qml` for the "Custom" theme's light + dark color
inputs. Forces `showAlphaChannel: false` (the rings handle alpha via
`arcOpacity`); otherwise a transparent pass-through, so the standard
`color` property and `accepted` signal of `ColorButton` are visible
on the wrapper directly.

This file is the **only** place `org.kde.kquickcontrols` is imported.
The standalone equivalent (future) will back this with a plain
`QQC2.Button` triggering a `QtQuick.Dialogs.ColorDialog`.

### `ConfigStore.qml`

Read-only view onto `Plasmoid.configuration`. Re-exposes every
persisted config key as a typed property so `main.qml` (and any
future reader) consumes `configStore.X` instead of reaching into
`Plasmoid.configuration` directly.

| Property | Type | Source key |
|---|---|---|
| `metricOrder` | `string` | `Plasmoid.configuration.metricOrder` |
| `enabledMetrics` | `string` | `Plasmoid.configuration.enabledMetrics` |
| `enabledPartitions` | `string` | `Plasmoid.configuration.enabledPartitions` (checked disk partitions; empty = aggregate ring on Plasma / `$HOME` FS on standalone) |
| `partitionOrder` | `string` | `Plasmoid.configuration.partitionOrder` (disk partition display order; first = outermost ring; empty = alphabetical) |
| `showCpuCores` | `bool` | `Plasmoid.configuration.showCpuCores` |
| `mergeCpuTemp` | `bool` | `Plasmoid.configuration.mergeCpuTemp` (hide `cpuTemp` ring, render it as the right half of the `cpu` ring) |
| `mergeGpuTemp` | `bool` | `Plasmoid.configuration.mergeGpuTemp` (same for the GPU pair) |
| `tempUnit` | `string` | `Plasmoid.configuration.tempUnit` (`auto` / `celsius` / `fahrenheit`) |
| `checkForUpdatesEnabled` | `bool` | `Plasmoid.configuration.checkForUpdatesEnabled` — opt-out flag for the periodic GitHub release check |
| `lastUpdateCheck` | `double` | `Plasmoid.configuration.lastUpdateCheck` — Unix ms of the last successful check; `0 = never`, drives the 24h cache TTL |
| `latestKnownVersion` | `string` | `Plasmoid.configuration.latestKnownVersion` — cached tag (e.g. `"v0.4.0"`) from the last fetch |
| `acknowledgedVersion` | `string` | `Plasmoid.configuration.acknowledgedVersion` — the version the user clicked "Got it" on; the badge stays hidden until a newer one appears |
| `localVersion` | `string` | `Plasmoid.metaData.version` — exposed here so `core/UpdateChecker.qml` can compare against the cached remote without importing Plasma |
| `orientation` | `string` | `Plasmoid.configuration.orientation` |
| `ringSize` | `int` | `Plasmoid.configuration.ringSize` — window WIDTH (px) in standalone; drives the autosize and the rings fill it 100% (vertical = N square rings stacked; horizontal = N square rings side-by-side, each `ringSize/N` wide). In Plasma the panel container may still stretch / shrink the widget regardless. Default 180, range 80-800. |
| `textOpacity` | `real` | `Plasmoid.configuration.textOpacity` |
| `trackOpacity` | `real` | `Plasmoid.configuration.trackOpacity` |
| `arcOpacity` | `real` | `Plasmoid.configuration.arcOpacity` |
| `colorTheme` | `string` | `Plasmoid.configuration.colorTheme` |
| `colorMode` | `string` | `Plasmoid.configuration.colorMode` |
| `customColorLight` | `color` | `Plasmoid.configuration.customColorLight` |
| `customColorDark` | `color` | `Plasmoid.configuration.customColorDark` |
| `textColorMode` | `string` | `Plasmoid.configuration.textColorMode` (`system` follows `Kirigami.Theme.textColor`; `custom` picks between the two below) |
| `customTextColorLight` | `color` | `Plasmoid.configuration.customTextColorLight` |
| `customTextColorDark` | `color` | `Plasmoid.configuration.customTextColorDark` |

**Implemented as an Item, not a singleton.** `Plasmoid` is a context
property injected by the Plasma shell on the QML root scope, so it
only resolves when accessed from inside the loaded `PlasmoidItem`
tree. A singleton living outside that scope would see `Plasmoid` as
undefined.

**Mostly reads-only by design.** SimpleKCM's `cfg_*` magic is still
the canonical write path for user-editable settings. The single
exception is the update-check group: the widget's runtime path (not
a config dialog) writes `latestKnownVersion` and `lastUpdateCheck`
on a successful GitHub fetch, and `acknowledgedVersion` on "Got it"
clicks. ConfigStore exposes two thin writer functions for that path:

| Function | What it persists |
|---|---|
| `recordUpdateCheck(version, timestampMs)` | the latest GitHub tag + the check timestamp; called by `core/UpdateChecker.qml` after a successful XHR |
| `acknowledgeVersion(version)` | the version the user dismissed via "Got it" in the About page |

Both write through `Plasmoid.configuration.X = …` directly — KConfig
flushes the file lazily, so the cached state survives widget
restarts. A standalone build's adapter would back these writers with
`Qt.labs.settings.setValue(...)` instead.

A standalone build will ship a parallel `ConfigStore.qml` backed by
`Qt.labs.settings`, exposing the same property surface.

Smoke-tested by `tests/config-store.test.mjs` — Node text-level
guard (asserts every persisted config key is declared, readonly,
and bound to the matching `Plasmoid.configuration.X` key). A
QML-runtime test isn't viable: `ConfigStore.qml` transitively
requires the Plasma desktop runtime (`org.kde.plasma.plasmoid`
QML module), which CI doesn't install — see the test file's
preamble for the rationale.

### `MetricsBackend.qml`

Wraps the KSysGuard sensor instances used by the Plasma build.
Mixes two patterns: **statically-bound `Sensors.Sensor` instances**
for universal ksysguard ids (`cpu/all/usage`, `memory/*/usedPercent`,
`disk/all/usedPercent`, `cpu/all/averageTemperature`, `gpu/all/usage`),
and **runtime discovery via `Sensors.SensorTreeModel` + `Instantiator`**
for the multi-arity ids that vary per machine (per-core CPU usage,
per-GPU temperature, per-GPU usage).

**Public surface** (the only thing `main.qml` consumes):

| Member | Description |
|---|---|
| `coreValues` (readonly property var) | array of per-core CPU usage values — length matches the discovered `cpu/cpu*/usage` count, with `\|\| 0` fallback for not-yet-ready sensors |
| `loading` (readonly property bool) | `true` until the universal aggregates (`cpuTotal`, `ramSensor`) have reached `Sensor.Ready` — drives the 100%-fill "warming up" animation in `MainContent` |
| `availableMetrics` (readonly property var) | catalog ids that currently have a live data source. Plasma: each metric whose `Sensor.status === Ready` (gpu/gpuTemp via the `_gpuUsageReady()` / `_gpuTempReady()` instantiator walks). Standalone: cpu/ram/disk always, cpuTemp once `_cpuTempPath` resolves, swap iff `SwapTotal > 0`, gpu/gpuTemp iff NVML reported available. Consumed by `MainContent` (drop dead rings) and `MetricsBody` (grey out the picker rows). |
| `metricValue(id)` (function) | latest value for one of the catalog metric ids — universal ids go through `Catalog.valueFromSensorMap`, `gpu` and `gpuTemp` are dispatched to the dynamic-discovery helpers below |
| `metricRawTemp(id)` (function) | latest raw °C reading for ids that expose a temperature sensor (`cpu` via static, `gpu` via discovery); `0` for others |
| `metricTempPercent(id)` (function) | same value mapped to 0–100 via `MetricsCatalog.tempToPercent` — drives the Ring's right-half split arc |
| `availablePartitions` (readonly property var) | `[{id, label}]` — discovered mounted filesystems for the disk multi-ring picker (Plasma: via the shared `DiskPartitions` adapter; standalone: via `/proc/mounts` + `DiskDiscovery`) |
| `defaultPartitionIds` (readonly property var) | partition ids to show when the user has selected none — `[]` on Plasma (falls back to the `disk/all` aggregate ring); the `$HOME`-bearing filesystem on standalone |
| `partitionValue(id)` (function) | latest 0–100 usage % for one discovered partition (Plasma: a live `disk/<uuid>/usedPercent` sensor; standalone: a **non-blocking** read of the last-good `statvfs` of the partition's representative mountpoint — see the async note below). Requesting an id also subscribes it to refreshes, so only the selected partitions are probed. |

The disk-partition discovery on Plasma lives in a separate reusable
adapter, `platforms/plasma/DiskPartitions.qml` (its own
`SensorTreeModel` walk → `[{id, label, sensorId}]`, id = the fs UUID,
label = the volume name), which `MetricsBackend` instantiates to drive
a per-partition `Sensor` `Instantiator`. The config dialog
(`configMetrics.qml`) instantiates a **whole `MetricsBackend`** of its
own — the KCM page runs in a separate context from the live widget, so
it can't read the running one — and feeds `MetricsBody.diskPartitions`
from `backend.availablePartitions` and `MetricsBody.availableMetrics`
from `backend.availableMetrics`. (The Plasma backend has no `Timer`; its
`Sensor`s are pushed by ksysguard, so this extra instance is a cheap,
short-lived probe for the duration of the config dialog.)

**Dynamic discovery** (the substantive change vs. the earlier
6-core-hardcoded model): on `Component.onCompleted` and on every
`sensorTree.rowsInserted`/`Removed`/`modelReset`, the backend walks
the tree, collects sensor ids, and feeds them to
`Catalog.classifyDiscoveredIds()` (pure, tested in
`tests/metrics-catalog.test.mjs`). The classified arrays
(`_coreUsageIds`, `_gpuTempIds`, `_gpuUsageIds`) drive three
`Instantiator`s that spawn the matching `Sensors.Sensor` instances.
For GPU temp and GPU usage, helper accessors (`_gpuTempValue`,
`_gpuUsageValue`) iterate the Instantiator children and return the
value of the first `Sensor.Ready` instance — GPU usage prefers the
aggregate `gpu/all/usage` when available and falls back to the first
discovered per-GPU sensor.

The "tick" pattern (`_coreTick`, `_gpuTempTick`, `_gpuUsageTick`) is
the standard QML workaround for binding to a dynamic collection of
properties: each instantiated `Sensor` bumps its tick `onValueChanged`,
and the `coreValues` / `_gpuXValue` readonly bindings declare the
tick as a dependency so they re-evaluate on every tick — yielding
the same animation pipeline as the previous static-binding model
without the hardcoded count assumption.

The standalone build ships a parallel
`platforms/standalone/MetricsBackend.qml` exposing the same public
surface, backed by direct kernel reads through the `ProcReader` /
`NvmlReader` C++ helpers instead of ksysguard: `/proc/stat` (CPU
usage + per-core), `/proc/meminfo` (RAM + swap — `SwapTotal`/`SwapFree`,
which covers zram on Bazzite),
`/sys/class/hwmon` + `/sys/class/thermal` (CPU temperature, via
`CpuTempDiscovery.js`), per-filesystem `statvfs` for the disk
multi-ring (`/proc/mounts` + `DiskDiscovery.js`, deduped by device,
the `$HOME` filesystem as the default), and NVML / `libnvidia-ml`
(NVIDIA GPU usage + temperature). It polls on a single `Timer` at 2 Hz (500 ms) to match
the ksysguard daemon's push cadence, where the Plasma adapter relies
on the daemon's own rate. AMD/Intel GPU (sysfs) is a follow-up. Layer detail:
[`../contents/ui/platforms/standalone/CLAUDE.md`](../contents/ui/platforms/standalone/CLAUDE.md).

The disk `statvfs` runs **off the GUI thread** (issue #48): `statvfs(3)`
blocks uninterruptibly on an unresponsive mount (stale NFS/CIFS, hung
autofs, spun-down USB), so `partitionValue(id)` calls the async
`ProcReader.requestStatvfs(mount)` (background read on a detached worker
thread) + `cachedStatvfs(mount)` (last-good, empty → 0% until the first
read lands) rather than the synchronous `statvfs()`. On completion the
helper emits `statvfsReady(mount)` and the backend bumps a dedicated
`_partTick` so the disk rings re-render. Requests are deduped while in
flight (one stuck thread per hung mount, never a pile) and throttled per
mount; the worker is detached rather than pooled so a mount stuck in the
syscall can't block process exit. A hung mount then just holds its
last-good ring value while every other ring keeps updating. The Plasma
adapter is unaffected (it reads cached ksysguard sensor values, which
never block).

Smoke-tested by `tests/metrics-backend.test.mjs` — same pattern as
`tests/config-store.test.mjs`. CI can't run a qmltestrunner test
that loads `org.kde.ksysguard.sensors`; the Node test inspects the
QML source and asserts the public surface + every catalog sensor +
the 6 per-core sensors are declared.

## Update-notification flow

A widget-side check against GitHub Releases drives a subtle "new
release" badge on the first ring and a dedicated config page that
surfaces the new version + install methods. Three files share the
flow: the pure semver / cache logic lives in
[`core/UpdateCheck.js`](logic-modules.md#updatecheckjs), the runtime
wiring in `core/UpdateChecker.qml`, the UI in `core/AboutBody.qml`
(rendered by the top-level wrapper `configAbout.qml`).

### `UpdateChecker.qml`

Portable runtime (pure QtQuick — no Plasma imports) that fires
`XMLHttpRequest` to `api.github.com/repos/manuacl/ring-monitor/releases/latest`
on Component completion, gates the call with a 24h TTL via
`UpdateCheck.shouldRecheck`, and persists the result through the
injected `configStore` (so a standalone build can back the same
public surface with a different write layer).

| Public surface | What it exposes |
|---|---|
| `localVersion` / `remoteVersion` / `acknowledgedVersion` (readonly) | mirrored from `configStore` — single source of truth |
| `updateAvailable` (readonly bool) | drives the badge and the AboutBody status block; computed via `UpdateCheck.shouldNotify` |
| `check()` (function) | force a network probe, bypassing the TTL gate |
| `acknowledge()` (function) | persists "Got it" — sets `acknowledgedVersion = remoteVersion` |
| `openStorePage()` (function) | `Qt.openUrlExternally` to the KDE Store entry (where the user-facing changelog lives) |
| `releasesApiUrl` / `storePageUrl` / `cacheTtlMs` (readonly) | overridable knobs (the standalone build could repoint the URLs) |

The XHR handler is intentionally silent on failure — a network blip
or a malformed JSON response leaves the cached state untouched and
the user sees nothing wrong. The next TTL cycle retries.

### `AboutBody.qml`

Portable Kirigami `FormLayout` rendering the "Release" / "New
release" config page. Four visible states drive the status block:

1. `checkForUpdatesEnabled === false` → "Update checks are disabled."
2. `remoteVersion === ""` (first run before the XHR lands) → "Checking for updates…"
3. `updateAvailable` → "Update available: vX.Y.Z" + `[Open KDE Store] [Got it]` buttons
4. otherwise → "You are running the latest version."

The wrapper [`configAbout.qml`](#configabout-qml-wrapper) declares the
ConfigCategory twice in `contents/config/config.qml` so the same body
appears at the top of the sidebar (named "New release") when there's
something to notify about, and at the bottom (named "Release") for
ambient discovery the rest of the time. Plasma 6 has no public
"open-at-category" API; the dynamic `visible` toggle on
`ConfigCategory` is the workaround.

Smoke-tested by `tests/qml/tst_AboutBody.qml` — exercises each of
the four states + the action signal wiring (`acknowledgeClicked`,
`openStorePageClicked`, `checkForUpdatesToggled`).

A fifth row, "Start automatically on login", is gated on
`autostartAvailable` (false on the Plasma side, true on standalone).
When visible, the checkbox state mirrors `autostartEnabled` and
emits `autostartToggled(on)` — the standalone wrapper wires that to
the `Autostart` C++ helper, which creates / removes
`~/.config/autostart/dev.manuacl.ringmonitor.desktop`. Plasma users
manage autostart from the panel layout, so the row stays hidden
there.
