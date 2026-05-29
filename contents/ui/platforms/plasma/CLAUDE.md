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
- `DiskPartitions.qml` — a focused `SensorTreeModel` walk that returns
  `[{id, label, sensorId}]` for the mounted filesystems
  (`disk/<uuid>/usedPercent`, id = UUID, label = volume name from the
  parent node's `Qt.DisplayRole`). Reused by **both** `MetricsBackend`
  (drives a per-partition `Sensor` `Instantiator`) and `configMetrics.qml`
  (feeds the partition checkboxes — the KCM page has no backend of its
  own).
- `ThemedIcon.qml` wraps `Kirigami.Icon` (one-liner, just for the import
  seam).
- `ColorPicker.qml` wraps `org.kde.kquickcontrols.ColorButton`.

This directory also hosts **Plasma-only pure logic** (not just
adapters): `SensorPicking.js` (first-ready-wins among KSysGuard sensor
candidates) lives here rather than in `core/` because only the Plasma
backend consumes it — keeping it in `core/` would ship it as dead code
in the standalone binary. Same placement rule in the other direction
for `platforms/standalone/` (the `/proc` parsers). See
[`../core/CLAUDE.md`](../core/CLAUDE.md) § "Logic in dedicated `.js`
files".

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
  into per-bucket arrays (cores, gpu temp, gpu usage, disk partitions) —
  testable in Node without Plasma.
- **Disk sensors are keyed per-filesystem by UUID, not by mountpoint.**
  ksystemstats exposes `disk/<uuid>/usedPercent` (+ `/free`, `/total`,
  `/name`, …) for each *mounted filesystem*, labelled by the volume name
  on the parent `disk/<uuid>` node. It already deduplicates a multi-mount
  filesystem (a btrfs root mounted at `/`, `/var`, `/home`) into one entry
  and already drops pseudo/overlay mounts (composefs `/`). Physical disks
  (`disk/sda`, `disk/nvme0n1`) carry throughput (`/read`, `/write`) but
  **no `/usedPercent`** — so `classifyDiscoveredIds` keys the partition
  bucket on the `usedPercent` leaf (excluding the `disk/all` aggregate).
  The mountpoint is **not** exposed as a sensor, which is why the disk
  multi-ring default can't match `$HOME` on Plasma (→ aggregate fallback).
- **The mount probe is `findmnt`, not `lsblk` — and UUIDs need lower-casing.**
  Two gotchas on `MountInfo.qml`'s live-mount probe, both cost a live-debug
  iteration (#58):
  - **Use `findmnt` (kernel mount table), not `lsblk` (block-device view).**
    The self-heal gate trusts "UUID absent from the live set ⇒ unmounted". A
    btrfs filesystem mounted only via subvolumes can make `lsblk`'s singular
    `MOUNTPOINT` empty (row dropped) while it is genuinely mounted — `lsblk`
    would then wrongly drop a still-mounted disk's ring. `findmnt -P -o
    UUID,TARGET,LABEL` lists every mount, so "absent ⇒ unmounted" holds.
  - **Lower-case the UUID.** `findmnt`/`lsblk` (via libblkid) print FAT/vfat
    volume serials UPPERCASE (`6F45-2B2F`), but the `disk/<uuid>` sensor id —
    and the persisted `enabledPartitions` / `partitionLabels` — is lowercase
    (`6f45-2b2f`). Skipping the lower-case (done at the parse boundary in
    `MountInfo.js`) renders a vfat USB key's ring at 0% (no matching sensor)
    and makes the gate drop it. ext4/btrfs UUIDs are already lowercase.
- **A `SensorTreeModel` does NOT signal an unmount — and a fresh instance
  doesn't help.** When a filesystem unmounts (USB unplug), the model fires no
  `rowsRemoved` / `modelReset` / `layoutChanged`, the per-partition
  `Sensor.status` stays `Ready`, and even a manual re-walk still lists the gone
  `disk/<uuid>` — the data is frozen, not just the change signals. The
  staleness is at the **ksystemstats daemon** level, not just our QML model, so
  a freshly-built `SensorTreeModel` (e.g. the config dialog's own backend)
  **still lists the unplugged partition** within the same session — only a
  plasmashell/daemon restart clears it. So you **cannot** detect an unplug from
  the tree anywhere; source the live mounted set elsewhere (`MountInfo.qml`
  runs `findmnt`). Two consumers gate on it:
  - the rendered ring set, via `DiskMetrics.resolveDiskRingIds(…, mountedIds)`
    (`MainContent`), so a ring self-heals away on unplug;
  - the **config picker**, via `MetricsBackend.mountedAvailablePartitions`
    (`= DiskMetrics.filterToMounted(availablePartitions, mountedPartitionIds)`),
    so an unmounted-but-frozen partition drops from the selectable checkboxes
    and, if still configured, surfaces as a greyed stale row instead of a live
    one. `configMetrics.qml` sets `removableTrackingActive: true` so the
    findmnt poll runs while the dialog is open.

  Confirmed on real hardware, issue #58.

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

### Adding a persisted config key: six touch points

A new `<entry>` in `contents/config/main.xml` is not enough — the key
has to land in **all six** of these or one platform silently uses a
different value (or the standalone build never reads it):

1. `contents/config/main.xml` — the `<entry>` + default (source of truth).
2. `platforms/plasma/ConfigStore.qml` — `readonly property X: Plasmoid.configuration.X`.
3. `platforms/standalone/ConfigStore.qml` — `property X: <default>` (mirror the default byte-for-byte).
4. `configMetrics.qml` (or the owning page) — `property alias cfg_X: body.X` + the `cfg_XDefault` placeholder.
5. `configAppearance.qml` (and any other page) — `cfg_X` + `cfg_XDefault` 484541 placeholders.
6. `platforms/standalone/SettingsDialog.qml` — a `_bridgeMap` entry `[body, "X", "X"]` (+ the pair in `standalone-settings-dialog.test.mjs`).

The `config-store` / `standalone-config-store` / `standalone-settings-dialog`
drift tests enforce 2/3/6, but only once run — work the list top-to-bottom
when adding the key (forgetting the **Plasma** ConfigStore is the easy miss).

### Config dialog has its own qmlcache

If a QML change to a config page doesn't seem to take effect after
restarting plasmashell, clear
`~/.cache/{plasmashell,kcmshell6,plasmawindowed}/qmlcache/` and
restart again. The project's `refresh-plasma-widget` skill already does this.

## Frame-fixed settings: hide the slider, hardcode the adapter

On the Plasma desktop containment the plasmoid frame is user-dragged
to a fixed size; the GridLayout's `rowSpacing` / `columnSpacing` eat
into that area and the Ring delegates' `Layout.fillWidth/fillHeight`
shrink the rings proportionally to compensate. **A "Ring spacing"-
style slider therefore looks like a no-op to the user** (rings shrink
as gap grows, net total unchanged). Same shape for any future setting
that interacts with the GridLayout's metrics (extra padding,
inter-section gaps, etc.).

When a setting falls into this profile, use the two-step pattern
documented inline on `ringSpacingPercent` (PR #40) and `windowMargin`:

1. **Hide the UI** — add a `property bool <key>Visible: false` to
   `core/AppearanceBody.qml`, wrap the slider row in
   `visible: body.<key>Visible`. The standalone `SettingsDialog`
   flips it on; the Plasma wrapper leaves it default. Same
   opt-in pattern as `AboutBody.autostartAvailable`.
2. **Hardcode the value** in `platforms/plasma/ConfigStore.qml` —
   `readonly property int <key>: 0` instead of binding through
   `Plasmoid.configuration.<key>`. Add the key to
   `HARDCODED_OVERRIDES` in `tests/config-store.test.mjs` and pin
   the hardcoded value with a dedicated test so a future
   "let me restore the binding" refactor lands as CI red.

The schema entry in `contents/config/main.xml` stays — standalone
still consumes it, and a user who knows what they're doing can still
override the Plasma side by hand-editing the appletsrc (binding is
bypassed, but the key persists; useful for debugging).

## Other plasmashell quirks

- **`plasmawindowed` exits silently on QML parse errors** → check the
  journal (filter out `breezerc`), see
  [`docs/development.md`](../../../docs/development.md) § "Standalone
  preview".
- **After `contents/config/main.xml` changes, restart plasmashell**
  (the config schema is read once at applet load).
- **QML `console.log` is filtered from the journal — use `console.warn`.**
  plasmashell drops QML debug-level messages, so `console.log(...)`
  produces nothing in `journalctl --user`; `console.warn(...)` shows.
  Reach for `console.warn` when instrumenting a widget QML file you'll
  observe via the journal.
- **`plasma5support` `DataSource` (engine `"executable"`) runs commands
  with the session `PATH`.** So invoke tools by bare name (`findmnt`), not
  an absolute path — see the no-absolute-path rule in the root
  [`CLAUDE.md`](../../../CLAUDE.md). Result keys are `"exit code"`,
  `"exit status"`, `"stdout"`, `"stderr"`; deliver is async (handle in
  `onNewData`, then `disconnectSource`). Canonical use: `MountInfo.qml`.

## Where the rest lives

- Portable views + pure logic: [`../core/CLAUDE.md`](../core/CLAUDE.md)
  and `../core/`.
- Cross-cutting rules (English-only, 500-line cap, no nested
  ternaries, SOLID, Stack reminder): root
  [`/CLAUDE.md`](../../../CLAUDE.md).
