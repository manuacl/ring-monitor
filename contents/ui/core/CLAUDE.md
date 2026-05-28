# `contents/ui/core/` — portable QML layer

Everything in this directory is the **portable** body of the widget:
the views, the gauges, the reorderable list, and the pure JS logic
modules. It targets any Qt 6 desktop, not Plasma in particular.

The platform-specific shell lives in `../platforms/plasma/` (and a
future `../platforms/standalone/`) — both expose the **same property
surface** so the same `core/` files render unchanged on either.

## Plasma isolation is the load-bearing invariant

**No `org.kde.*` imports except `org.kde.kirigami`.** Kirigami is a KF6
framework that runs on any Qt 6 desktop, so a standalone build can
ship it as a runtime dep. Anything else under `org.kde.*`
(`kquickcontrols`, `plasma.*`, `kcmutils`, `ksysguard.*`,
`kcoreaddons`, `kio`, …) is host-bound and must live behind an
adapter in `../platforms/plasma/`.

Pattern to extend the seam:
- Need a Plasma-only QML control inside a `core/` view? Wrap it first
  in a new `../platforms/plasma/X.qml` adapter exposing the property
  surface `core/` will consume. Examples:
  - `ThemedIcon.qml` wraps `Kirigami.Icon` (just for the import seam).
  - `ColorPicker.qml` wraps `org.kde.kquickcontrols.ColorButton`.
  - `ConfigStore.qml` wraps `Plasmoid.configuration` reads.
  - `MetricsBackend.qml` wraps `org.kde.ksysguard.sensors`.

Then have `core/` import `"../platforms/plasma" as Platform` and use
`Platform.X`. Enforced by `finish-branch` via
`grep -rE 'import org\.kde\.' contents/ui/core/` filtered on the
Kirigami allowlist.

Full rationale and the file-by-file inventory:
[`docs/plasma-isolation/plan.md`](../../../docs/plasma-isolation/plan.md).

## Logic in dedicated `.js` files, views thin

Pure logic lives in dual-loadable `.js` modules (QML + Node — no
`pragma library` so the Node-side `module.exports` shim at the bottom
works). QML files consume them via `import "X.js" as X` and act as
thin views.

**Placement follows usage, not just purity** (the dead-code rule):

- **Shared by both platforms → `core/`.** A module imported by a
  `core/*.qml` view (or by both backends) belongs here. Current:
  - `MetricsCatalog.js` — metric ids, labels, sensor mapping, helpers.
  - `ColorThemes.js` — theme registry + color resolution.
  - `ReorderLogic.js` — drag-and-drop array transforms.
  - `RingGeometry.js` — sweep / radius / nested-ring layout math.
  - `UpdateCheck.js` — update-check version compare + TTL.
- **Used by only one platform → that platform's `../platforms/<p>/`
  directory, beside its adapter.** Keeping platform-specific logic in
  `core/` ships it as dead weight to the other artifact (the `.plasmoid`
  zip, or the standalone CMake-compiled module). So:
  - `../platforms/standalone/{ProcStatParser,MemInfoParser,CpuTempDiscovery}.js`
    — only the standalone `MetricsBackend` reads `/proc` + sysfs.
  - `../platforms/plasma/SensorPicking.js` — only the Plasma
    `MetricsBackend` picks among KSysGuard sensor candidates.

Always tested regardless of directory: every `.js` (here or under
`platforms/`) has a matching `tests/<kebab-case>.test.mjs`. See
[`tests/CLAUDE.md`](../../../tests/CLAUDE.md) for the naming and
patterns.

## Component-side gotchas

### `Ring.qml`: non-percent metrics decouple sweep input from display

`Ring.value` is always treated as 0-100 for the sweep angle math.
When the metric is a temperature (or any non-percent — future:
network rate, NVMe temp), the parent maps the raw reading to a
percent for `value` AND passes the raw value via `rawValue` (with the
matching `unit`, e.g. `"°C"`). The centre text reads
`Math.round(rawValue) + unit` when finite, falls back to
`value + unit` otherwise. Split mode applies the same dual-prop trick
via `splitValue` (0-100 for the sweep) and `splitRawValue` (raw for
the text). Don't cram a non-percent value into `value` directly —
the sweep math would be wrong.

### `Ring.qml`: `PathAngleArc.centerX` binds to the Shape's `width/2`

Give the `Shape` an `id` and reference it explicitly. The default
implicit binding through `parent` resolves to the wrong item in some
QML render scopes — the arc ends up drawn off-centre.

### `DraggableList.qml`: forward row data via `parent.rowModel`, not the scope chain

Inside a `Loader` that hosts a user-provided `Component`, declare
`property var rowModel: model` on the Loader; the loaded root reads
`parent.rowModel`. QML's implicit context-property propagation
through `Loader` is flaky across Qt versions / KCM containers — the
"empty labels" regression was caused by relying on bare `model.X`.
Regression-tested by `DraggableListForwarding.test_*` in
`tests/qml/tst_DraggableList.qml`.

### `DraggableList.qml`: no `pragma ComponentBehavior: Bound` on a ListView delegate file

It silently breaks the drag — the implicit `model`/`index` and
`MouseArea.drag.target` don't coexist with `required property var
model`. Apply the pragma only to delegate-free files (`main.qml`,
`Ring.qml` are OK).

### `DraggableList.qml`: nested lists are drag-scoped via `dragKey` (auto-unique by default)

An unkeyed `DropArea` accepts events from **any** drag source (Qt docs),
so two unscoped `DraggableList`s would cross-fire: nest the disk-partition
picker inside the metrics list and dragging an inner row floats fine but
never reorders — the outer list's `DropArea`s swallow the drop, the inner
`_dropTarget` never updates, the row snaps back. `DraggableList.dragKey`
(applied to every row's `Drag.keys` + each `DropArea.keys`) **defaults to a
unique-per-instance value**, so nesting is safe with no action. Only set
`dragKey` explicitly to deliberately make two lists share one drop scope.

### Don't reuse a property name as an `id` when passing it down

Pattern that bites — typically inside a `Component` template like
`fullRepresentation: X { ... }`:

```qml
Platform.Theme { id: theme }
MainContent { theme: theme }   // ← RHS resolves to MainContent.theme,
                                //   which is undefined at binding time
```

The RHS `theme` resolves to the new component's own `theme` property
(undefined at binding time) instead of the outer id. Errors land in
the journal, not in the QML compiler. Fix: suffix the outer id
(`themeAdapter`, `configStoreAdapter`, …). Same trap applies to any
parent → child id reuse inside templates.

## Where the platform adapters live

For Plasma-specific concerns (KSysGuard, KConfig, plasmashell quirks,
config-dialog gotchas): [`../platforms/plasma/CLAUDE.md`](../platforms/plasma/CLAUDE.md).

Cross-cutting rules (English-only, 500-line cap, no nested ternaries,
SOLID grid, QML↔React stack reminder): root
[`/CLAUDE.md`](../../../CLAUDE.md).
