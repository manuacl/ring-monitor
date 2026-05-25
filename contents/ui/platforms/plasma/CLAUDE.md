# `contents/ui/platforms/plasma/` — Plasma adapter layer

Thin wrappers around the Plasma/KDE-host bits that `core/` is forbidden
to touch directly. Each file exposes a property surface (or function
surface) that `core/` consumes adapter-free. A future
`platforms/standalone/` directory will mirror this layout backing the
same surface with /proc reads or psutil.

## Adapter pattern

One file per Plasma seam. Keep each adapter **focused and surgical**:

- `Theme.qml` re-exposes Kirigami theme tokens + the Qt.styleHints
  live light/dark signal.
- `ConfigStore.qml` re-exposes `Plasmoid.configuration.*` reads (writes
  still go through the SimpleKCM `cfg_*` flow).
- `MetricsBackend.qml` wraps `org.kde.ksysguard.sensors` — universal
  aggregates as static `Sensors.Sensor` instances, multi-arity sensors
  via `SensorTreeModel` + `Instantiator`.
- `ThemedIcon.qml` wraps `Kirigami.Icon` (one-liner, just for the import
  seam).
- `ColorPicker.qml` wraps `org.kde.kquickcontrols.ColorButton`.

The contract:
1. The adapter is the **only** place its Plasma import is allowed.
2. The public surface (named properties / functions) is what `core/`
   consumes — internal Sensor instances, maps, ticks are
   implementation details and stay prefixed with `_` when test hooks.
3. The standalone counterpart (when it lands) must satisfy the same
   public surface with a different backend.

## KSysGuard sensor quirks

- **`Sensors.Sensor` does not error on a missing sensorId.** `.value`
  just stays at `undefined` / `NaN`, `.status` goes to `Error` or
  stays `Unknown`. Always `s.value || 0` at the read-site (or
  `Catalog.valueFromSensorMap` which encapsulates the defence).
- **`Sensors.Sensor.status` enum is the canonical "did it resolve?"
  signal.** Values: `Unknown`, `Loading`, `Ready`, `Error`, `Removed`.
  For probe-then-pick patterns (try several candidate ids, use the
  first that exists) and for "loading" warm-up animations, query
  `.status === Sensors.Sensor.Ready` rather than guessing from
  `.value`. Canonical use in `MetricsBackend.qml` (`loading`,
  `_gpuTempValue`, `_gpuUsageValue`).
- **Dynamic Sensor instances via `Instantiator` need a tick counter**
  for `readonly property var` bindings to react to inner `.value`
  changes. The natural `[obj0.value, obj1.value, …]` binding only
  tracks dependencies at the initial evaluation — model adds /
  removes re-evaluate, but `.value` changes inside an already-
  instantiated delegate do NOT. Workaround: each delegate bumps
  `backend._tick++` in `onValueChanged`, and the readonly property
  reads `backend._tick;` as its first line (tracked dependency), then
  iterates `instantiator.objectAt(i)`. Pattern in
  `MetricsBackend.qml`: `_coreTick`, `_gpuTempTick`, `_gpuUsageTick`.
- **`SensorTreeModel` walks every subsystem.** Use it instead of
  hardcoding per-machine sensor ids (e.g. `gpu/gpu1/temperature` works
  on the dev rig but breaks on a `gpu/gpu0/…` machine). The pure
  classifier `Catalog.classifyDiscoveredIds` filters the flat id list
  into per-bucket arrays (cores, gpu temp, gpu usage) — testable in
  Node without Plasma.

## Live light/dark scheme detection: `Qt.styleHints`, not Kirigami

`Kirigami.Theme.backgroundColor` reflects the panel's `Complementary`
colorSet (fixed regardless of the user's System Settings → Colors
choice). Even a probe Item with `inherit: false; colorSet: Window`
does not re-evaluate live in plasmashell. The canonical KDE signal
since KF 6.22 is `Qt.styleHints.colorScheme` (Qt 6.5+).

Critical: the property has **no NOTIFY** (warning explicit in Qt's
own doc) — binding it would never re-evaluate. Subscribe to the
`colorSchemeChanged` signal via `Connections`, write the new value
into an intermediate regular property, and let the public `readonly`
API bind to that. Canonical pattern in `Theme.qml`
(`_qtScheme` → `isDarkMode`).

Caveat: some setups (third-party look-and-feel themes like Vapor) do
not emit the signal live inside plasmashell; always expose an
explicit Light/Dark override for the user (see `AppearanceBody.qml`'s
`colorMode` radio group).

## Plasma config dialog (`configMetrics.qml`, `configAppearance.qml`)

Top-level wrappers are also Plasma-bound — they import
`org.kde.kcmutils as KCM` for `SimpleKCM`. They live at
`contents/ui/` (not under `platforms/plasma/`) for historical reasons
but follow the same isolation seam: their only job is to bridge
`cfg_*` magic to plain QML properties on the `core/` body via
`property alias` declarations.

### KDE bug 484541: every `cfg_*` is set on every page

Plasma 6 sets every `cfg_<key>` (and the auto-generated
`cfg_<key>Default` for "Reset to defaults") on each opened config
page. Pages that don't bridge a key still receive the assignment and
log a warning. **Placeholder pattern**: declare `property var
cfg_<key>` (and `cfg_<key>Default`) for every key handled on another
page, so the assignments land somewhere instead of polluting the
journal. Full discussion in
[`docs/config-dialog.md`](../../../docs/config-dialog.md).

### Config dialog has its own qmlcache

If a QML change to a config page doesn't seem to take effect after
restarting plasmashell, clear
`~/.cache/{plasmashell,kcmshell6,plasmawindowed}/qmlcache/` and
restart again. The project's `refresh-widget` skill already does this.

## Other plasmashell quirks

- **`plasmawindowed` exits silently on QML parse errors** → check the
  journal (filter out `breezerc`), see
  [`docs/development.md`](../../../docs/development.md) § "Standalone
  preview".
- **After `contents/config/main.xml` changes, restart plasmashell**
  (the config schema is read once at applet load).

## Where the rest lives

- Portable views + pure logic: [`../core/CLAUDE.md`](../core/CLAUDE.md)
  and `../core/`.
- Cross-cutting rules (English-only, 500-line cap, no nested
  ternaries, SOLID, Stack reminder): root
  [`/CLAUDE.md`](../../../CLAUDE.md).
