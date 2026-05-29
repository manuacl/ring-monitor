# Logic modules

The pure-logic `.js` modules live in one of two places, by usage:

- **`contents/ui/core/`** — shared by both platforms (`MetricsCatalog`,
  `ColorThemes`, `ReorderLogic`, `RingGeometry`, `UpdateCheck`).
- **`contents/ui/platforms/<p>/`** — used by only one platform, kept
  beside that platform's adapter so it isn't shipped as dead code to
  the other artifact: `platforms/standalone/` holds `ProcStatParser`,
  `MemInfoParser`, `CpuTempDiscovery`; `platforms/plasma/` holds
  `SensorPicking`. See the placement rule in
  [`../contents/ui/core/CLAUDE.md`](../contents/ui/core/CLAUDE.md)
  § "Logic in dedicated `.js` files".

All of them — wherever they live — follow the same shape:

```js
// Pure functions and constants here.
function foo(...) { ... }

if (typeof module !== "undefined" && module.exports) {
    module.exports = { foo: foo, ... };
}
```

No `.pragma library` — that's QML-only syntax and breaks Node parsing. We
trade off the per-import-instance state (irrelevant here, the functions are
pure) for dual-loadability.

## `ReorderLogic.js`

Drag-to-reorder math for `DraggableList.qml`.

| Function | What it returns |
|---|---|
| `computeDropTarget(mouseY, rowStep, count)` | model index the cursor is over, clamped to `[0, count-1]` |
| `computeYShift(rowIndex, dragSource, dropTarget, step)` | y-offset to apply to a row to "make room" for the dragged item |
| `applyMove(arr, from, to)` | new array with `arr[from]` moved to `to` (input not mutated) |

Key invariants — encoded as tests in `tests/reorder-logic.test.mjs`:

- `computeYShift(i, src, src, step) === 0` for all `i` (cursor over origin
  ⇒ no rows shift). This is what makes "drag and return without dropping"
  feel right.
- `computeYShift(src, ...) === 0` always (the dragged row itself never
  shifts; its visual position is owned by the floating reparented copy).
- `applyMove` is pure. Successive drags can't carry state between them.

The historical bug that drove this extraction: with QML's
`Drag`/`DropArea`, `dropTargetIndex` stuck across drags and the visual gap
locked at the previous drop position. The current code does not use
`Drag`/`DropArea` at all — `DraggableList` tracks `mouseY` via
`positionChanged` and arithmetically picks the target row.

## `MetricsCatalog.js`

Static catalog + CSV helpers for the metric system.

| Export | Purpose |
|---|---|
| `METRIC_IDS` | canonical order: `["cpu", "ram", "swap", "gpu", "disk"]` |
| `METRIC_LABELS` | short labels (no i18n — these are abbreviations) |
| `METRIC_SENSOR_IDS` | id → ksysguard sensor id |
| `parseCsv(str)` | tolerant CSV split, drops empty segments |
| `filterByOrder(ids, order)` | keep only `ids`, sorted by `order` |
| `filterByAvailable(enabledIds, availableIds)` | order-preserving intersection — drop enabled ids absent from `availableIds`; `null`/`undefined` passes through (availability unknown) |
| `labelFor(id)` | label or uppercase fallback |
| `sensorIdFor(id)` | sensor id or `""` |
| `toggleEnabled(ids, id, on)` | new array with `id` added or removed |

i18n descriptions deliberately live in `configMetrics.qml`, not here:
xgettext extracts i18n strings from `i18n("literal")` calls in QML, and
keeping them in a `.js` module would either skip extraction or force
ugly workarounds.

## `ColorThemes.js`

Static catalog of ring color themes + the resolver that maps a theme
id to the concrete color to apply, given the current platform state.

| Export | Purpose |
|---|---|
| `THEMES` | list of `{id, label, lightColor, darkColor}` — 7 entries (`system`, `blue`, `green`, `orange`, `violet`, `red`, `custom`) |
| `THEMES_BY_ID` | id → theme lookup |
| `effectiveIsDark(mode, systemIsDark)` | resolves the `colorMode` config (`auto` / `light` / `dark`) into the boolean `resolveColor` consumes — `auto` trusts the system detection, `light`/`dark` force the answer |
| `resolveColor(themeId, isDark, systemHighlight, customLight, customDark)` | dispatch — `system` forwards `systemHighlight`, `custom` picks between `customLight`/`customDark` by `isDark`, predefined themes fall through to their `lightColor`/`darkColor` |

Why a pure module? The dispatch logic is small but has 7 branches and
a fallback — exactly the kind of thing that grows nested ternaries if
inlined in a QML binding. Extracting it lets `MainContent.qml`'s
`ringColor:` binding stay a one-liner, and lets the dispatch be
exhaustively unit-tested in Node without spinning up Plasma.

The two non-data themes (`system`, `custom`) use a lookup-map dispatch
inside `resolveColor` rather than nested ternaries (CLAUDE.md rule);
the three `colorMode` values use the same pattern inside
`effectiveIsDark`.

`colorMode` is a separate concern from `colorTheme`: the theme picks
*which colors* to use, the mode picks *which variant* (light / dark)
to apply. Splitting them lets users on Plasma themes that break the
auto-detect (Vapor, third-party look-and-feel themes that override
the system color scheme) force the variant explicitly.

## `RingGeometry.js`

All the size/stroke/sweep math from `Ring.qml`.

| Function | Purpose |
|---|---|
| `BASE_START_ANGLE` / `BASE_SWEEP_ANGLE` | 135° / 270° — the established arc shape |
| `clampPercent(p)` | clamp to `[0, 100]`, NaN → 0 |
| `sweepForPercent(p)` | percent → sweep angle in degrees |
| `dimensionsFor(size)` | `{ ringStroke, ringRadius, nestedStroke, nestedGap, labelPx, valuePx }` |
| `nestedRingLayout(ringRadius, ringStroke, preferredStroke, preferredGap, count)` | `{stroke, gap, radii}` for the thin CPU-cores rings nested *inside* the main ring (shrinks past `COMFORT_RING_COUNT` = 7) |
| `equalRingLayout(ringRadius, preferredStroke, preferredGap, count)` | `{stroke, gap, radii}` for the **equal-thickness** disk partition rings that *replace* the main ring — outermost at `ringRadius`, shrinks past `DISK_COMFORT_RING_COUNT` = 5. `radii[0] === ringRadius`. |

Why extract this? The earlier inline ternary chain in `Ring.qml`
(`Math.max(4, Math.round(size * 0.055))` repeated five times) is the
canonical signal that a pure-math helper wants to exist. Putting it in a
testable file means changes to "how big should the label be at size 40"
are testable without launching Plasma.

## `UpdateCheck.js`

Pure semver math + cache-TTL gating for the in-widget "update
available" badge. The runtime side (XMLHttpRequest, Component.onCompleted
gate, ConfigStore writes) lives in `core/UpdateChecker.qml`.

| Function | Purpose |
|---|---|
| `parseSemver(tag)` | `"v0.4.0"` / `"0.4.0"` → `[0,4,0]`, malformed → `null`. Tolerates a `-rc1` / `+build42` suffix (KConfig stores the GitHub tag verbatim, `Plasmoid.metaData.version` strips the leading `v` — both must parse to the same triple). |
| `compareSemver(a, b)` | 3-way numeric compare on `[maj,min,pat]`. Null inputs → `0` (safe default; the caller can short-circuit on `isNewerVersion`). |
| `isNewerVersion(local, remote)` | both strings; `true` iff remote strictly > local. False for malformed input — the badge stays hidden rather than crying wolf. |
| `shouldRecheck(lastCheckMs, nowMs, ttlMs)` | gate before the XHR fires. `lastCheckMs === 0` (never checked) always returns `true`. |
| `shouldNotify(local, remote, acknowledged)` | the badge-visibility test: `isNewerVersion(local, remote) && !acknowledged`. A malformed acknowledged value is treated as no-ack (defensive). |

The two-step gate (`shouldRecheck` for the network call, `shouldNotify`
for the UI) keeps the two concerns independent: a successful fetch with
a remote == local doesn't surface a badge, and an unacknowledged update
keeps showing the badge across widget restarts without re-hitting the
network. Encoded as tests in `tests/update-check.test.mjs`.

## `SensorPicking.js`

Lives in `contents/ui/platforms/plasma/` — it's **plasma-only** (the
standalone backend resolves a single sysfs path via `CpuTempDiscovery`
rather than picking among ready candidates), so per the placement rule
it sits beside the Plasma adapter, not in `core/`.

Pure picking algorithm for "list of candidate sensors, return the
first one that's ready". Used by `platforms/plasma/MetricsBackend.qml`
for the GPU usage/temp fallback chain (try the `gpu/all/*` aggregate,
fall back to any per-GPU sensor that resolved).

| Function | Purpose |
|---|---|
| `pickFirstReadyValue(candidates)` | First `{ready:true}` candidate's `value` (`\|\| 0` for `undefined` / `NaN` / `null` / `false` / `""`); `0` if no candidate is ready. Null/undefined entries in the list are skipped so callers can build the list with `if (s) candidates.push(...)` without an extra filter pass. Subtle semantic: a candidate with `ready: true` AND a falsy value still **wins** — the helper returns `0` rather than falling through to subsequent candidates. The fallthrough path is only entered when `ready` itself is false. This matches the pre-`pickFirstReadyValue` pattern (`sensor.value \|\| 0` after a `status === Ready` check), so the refactor is semantics-preserving. If "try the next ready candidate when this one has no value" is ever wanted, that's a new helper, not a tweak of this one. |

Why a dedicated module instead of inlining? Two reasons. (1) The
algorithm has subtle edge cases — a `value: 0` from a ready sensor
must NOT fall through to the next candidate, but a `value: null`
must (and the `|| 0` rule handles both). Centralising the test
matrix in Node is cheaper than asserting it via QML test harnesses.
(2) Even a single-platform helper earns a dedicated, Node-tested
module — it just lives beside its adapter (`platforms/plasma/`)
rather than in `core/`. See
[`plasma-isolation/plan.md`](plasma-isolation/plan.md) "PR A" for
the broader rationale.

## `MountInfo.js`

Lives in `contents/ui/platforms/plasma/` — it's **plasma-only** (the
standalone backend already gets mountpoints from `/proc/mounts` via
`DiskDiscovery`), so per the placement rule it sits beside the Plasma
adapter, not in `core/`.

Parses the `findmnt -P -o UUID,TARGET,LABEL` pairs output that
`MountInfo.qml` runs through plasma5support. This is how the Plasma
build learns each filesystem's mountpoint — ksysguard exposes only the
label + `usedPercent` per UUID, never the mountpoint, so removable
detection (auto-show / auto-check of plugged USB keys) would be
impossible from sensors alone. findmnt's `UUID` is exactly ksysguard's
`disk/<uuid>` key, so the parsed rows join straight onto the
per-partition sensors. `findmnt` (kernel mount table) is used over
`lsblk` (block-device view) so the set is complete — it lists btrfs
subvolume mounts that lsblk's singular `MOUNTPOINT` can report empty,
which matters because the live-mount self-heal gate trusts "absent ⇒
unmounted" (see `DiskMetrics.resolveDiskRingIds`).

| Function | Purpose |
|---|---|
| `parseMountPairs(stdout)` | `[{uuid, label, mountpoint}]`, one per mounted filesystem with a UUID. `-P` (key=`"value"` pairs) is used over raw columns so spaces in a label or target survive. The UUID is **lower-cased** to match ksysguard's keys (findmnt prints FAT/vfat serials UPPERCASE, e.g. `6F45-2B2F`, while ksysguard uses `6f45-2b2f`). Rows without a UUID (pseudo / network mounts) and rows whose target isn't an absolute path are dropped; a filesystem mounted at several targets (btrfs subvolumes, bind mounts) appears once — the first row, whose target drives the removable classification. Removable classification is **not** done here — that's the shared `DiskMetrics.isRemovableMount(mountpoint)` predicate, applied by the consumer so the standalone `/proc` path classifies through the same rule. |

Covered by `tests/mount-info.test.mjs` (which also text-guards the
`MountInfo.qml` adapter surface — its plasma5support import keeps it out
of `qmltestrunner`, same as the other Plasma adapters).

## `ProcStatParser.js`

Lives in `contents/ui/platforms/standalone/` — **standalone-only**
(the Plasma build reads CPU usage from a KSysGuard sensor, never from
`/proc/stat`). Pure parse + delta math for `/proc/stat`: the standalone
`MetricsBackend.qml` reads the file via the `ProcReader` C++ helper,
hands the raw text to this module, and gets aggregate + per-core
percentages from the difference between two samples.

| Function | Purpose |
|---|---|
| `parseProcStat(content)` | Parses raw `/proc/stat` text into `{ all, cores }`. `all` is the aggregate `cpu` line; `cores` is an array of per-CPU rows. Each sample is `{ idle, total }` jiffies. Defensive against null / empty / malformed input (returns `{ all: null, cores: [] }`). Outer gate is `^cpu(\d*)\b` so `cpufreq`, `cpu_avg_freq`, and other `cpu`-prefixed metadata lines never enter the inner parser — locked in by a SCENARIO test in `tests/proc-stat-parser.test.mjs`. |
| `percentFromSample(prev, cur)` | Usage % between two samples: `100 * (1 - idleDelta / totalDelta)`. Clamped to `[0, 100]` and zero on a `totalDelta <= 0` (clock skew / same-jiffy sample). |

Covered by `tests/proc-stat-parser.test.mjs` (a `.js` keeps its test
wherever it lives — the test stays under `tests/`).

## `MemInfoParser.js`

Pure parser for `/proc/meminfo` plus two percent helpers — one for
RAM, one for disk. Used by the standalone `MetricsBackend.qml` (PR E
in the standalone roadmap): the QML adapter reads `/proc/meminfo`
via `ProcReader` and queries `ProcReader.statvfs("/")` for disk
capacity, then hands each into the matching helper.

| Function | Purpose |
|---|---|
| `parseMemInfo(content)` | Parses `/proc/meminfo` into `{ total, available }` (kB). Defensive against null / empty / malformed input (fields stay `null`). Picks `MemAvailable` rather than `MemTotal - MemFree` — same convention as `free -h`; using `MemFree` would report 90 %+ on any machine with a healthy page cache. |
| `usagePercent(total, available)` | `(1 - available / total) * 100`, clamped to `[0, 100]`. Returns `0` on missing / non-numeric inputs. Used for the **RAM** path, where `MemAvailable` already accounts for reclaimable cache. Not appropriate for disks with a root reservation — use `diskUsagePercent` there. |
| `diskUsagePercent(total, free, available)` | df(1)'s "Use%" formula: `(total - free) / (total - free + available)`, clamped to `[0, 100]`. Returns `0` on missing / non-numeric inputs. Treats root-reserved blocks (~5 % on ext4) as "size invisible to the user" — without this, a freshly-formatted empty ext4 would report 5 % used. Wired to the **disk** path in `standalone/MetricsBackend.qml`. |

Covered by `tests/mem-info-parser.test.mjs`.

## `CpuTempDiscovery.js`

Vendor-agnostic CPU-temperature sensor discovery for the standalone
build. On Plasma, KDE's `ksystemstats` already does this walk behind
the `cpu/all/averageTemperature` sensor; this module is the in-house
equivalent so the standalone backend finds the CPU temperature on any
machine without a KDE dependency.

The CPU temperature has no fixed sysfs path: `hwmonN` numbering is
allocation-order, and which chip owns the CPU sensor depends on the
vendor (Intel `coretemp`, AMD `k10temp` / `zenpower`, ARM
`cpu_thermal`, …). So `standalone/MetricsBackend.qml` enumerates the
sysfs trees via `ProcReader.listDir` + `read`, and these **pure**
functions decide which entry is the CPU — same I/O-in-adapter,
decisions-in-a-pure-module split as `ProcStatParser` / `MemInfoParser`
(all three standalone-only, in `platforms/standalone/`).

Two sources, tried in order by the backend: hwmon first (it carries
per-sensor labels), then `/sys/class/thermal` as a fallback (CPU temp
on many ARM SBCs / VMs lives only in the thermal framework).

| Function | Purpose |
|---|---|
| `parseTempCelsius(raw)` | Millidegrees-C sysfs reading → °C. Empty / non-numeric (a refused or missing `read`) → `NaN`, which `MetricsCatalog.tempToPercent` / `convertTemp` already render as an unavailable `0`. |
| `pickCpuHwmonDir(entries)` | From `[{ dir, name }]` (each hwmon's `name` file), the `dir` of the highest-priority CPU chip in `CPU_HWMON_NAMES`, or `""`. Vendor-specific drivers outrank the generic `acpitz` fallback. |
| `pickCpuTempInput(sensors)` | From `[{ input, label }]` within one chip, the best `tempN_input` — prefers the package/die label (`Package id 0`, `Tctl`, `Tdie`) over per-core / per-CCD, breaks ties by lowest index. `""` when the chip has no temp input. |
| `pickCpuThermalZone(zones)` | Fallback path: from `[{ dir, type }]`, the `dir` of the best CPU `thermal_zoneN` in `CPU_THERMAL_ZONE_TYPES` (`x86_pkg_temp`, `cpu-thermal`, …), or `""`. |
| `isTempInput` / `tempIndexFromInput` | `tempN_input` matcher + index extractor used by the pickers. |

Covered by `tests/cpu-temp-discovery.test.mjs` (includes a real-layout
scenario: `coretemp` / `Package id 0` chosen over nvme / chipset / wmi
/ battery hwmons).

## `DiskDiscovery.js`

Standalone-only filesystem discovery for the disk multi-partition ring
(in `platforms/standalone/`, beside the adapter — only the standalone
backend reads `/proc/mounts`). The QML side feeds three raw inputs from
`ProcReader` (`/proc/mounts`, `blockDeviceInfo()`, `canonicalHome()`)
and these pure functions turn them into the partition list + default
selection. Mirrors what ksysguard does on Plasma: one entry per
**filesystem** (deduped by device), keyed by UUID, labelled by volume
name.

| Function | Purpose |
|---|---|
| `parseMounts(content)` | `/proc/mounts` → `[{device, mountpoint, fstype}]` for real block-device filesystems only. The `device.startsWith("/dev/")` test drops composefs/overlay/tmpfs/fuse in one rule (their device field isn't a `/dev` path); `squashfs` is additionally skipped (loop-mounted system images). Un-escapes octal `\040`-style mountpoints. |
| `buildPartitions(mounts, blockInfo)` | Dedup by device → `[{id, label, mountpoint, device}]`. `id` = fs UUID (falls back to the device path), `label` = volume label (falls back to the device basename), `mountpoint` = the shortest mount of that device (any works for `statvfs` — same filesystem). Collapses the 5 mounts of an rpm-ostree btrfs root into one entry. |
| `defaultSelection(mounts, partitions, canonicalHome)` | `[id]` of the filesystem bearing `$HOME` — the longest mountpoint that is a prefix of the resolved home path (e.g. `/var/home` over `/var` over `/`). `[]` when home can't be matched. |

Covered by `tests/disk-discovery.test.mjs` (real Bazzite `/proc/mounts`
SCENARIO: sda3 mounted 5× → one "bazzite" partition; composefs / tmpfs /
fuse dropped; `$HOME=/home/manu` → `/var/home` → sda3).

## `DiskMetrics.js`

Shared (`core/`) view-side helpers for the disk multi-partition ring —
the per-partition discovery + value reads are platform-specific, but
these computations are identical on both hosts. Selecting the enabled
subset in display order is done with `MetricsCatalog.filterByOrder`
(no disk-specific helper).

| Function | Purpose |
|---|---|
| `averagePercent(values)` | Mean of a 0–100 array (the centre readout for the multi-ring disk). `0` on empty or any non-finite member — never propagates NaN into the centre text. |
| `orderPartitions(savedOrderCsv, available)` | Order the discovered partitions for the reorderable picker + ring nesting: ids in the saved CSV first (that order), then newly-discovered ones appended alphabetically by label; stale (no-longer-discovered) ids excluded — they surface separately via `stalePartitions`, not in the draggable list. Empty saved order → fully alphabetical (the default). First = outermost ring. Mirror of `MetricsCatalog.mergeWithCatalog` for the dynamic partition set. |
| `resolveDiskRingIds(manualIds, removableMounts, optOutIds, defaultIds, maxCount, mountedIds)` | The final ordered disk-ring set rendered by `MainContent`: the manual selection (`manualIds`, already ordered) first, then each currently-mounted removable filesystem (`removableMounts = [{id,…}]`) not already selected and not in `optOutIds` (the **auto-show**), deduped; falls back to `defaultIds` when the union is empty (`[]` = aggregate ring on Plasma, the `$HOME` FS on standalone), capped at `maxCount`. `mountedIds` is the live set of ALL mounted UUIDs (from the kernel mount table via `findmnt`); when non-empty it **gates the manual ids** so an unmounted partition's ring self-heals away ([#58](https://github.com/manuacl/ring-monitor/issues/58)) — this is needed because ksysguard's own tree freezes on unmount and keeps listing the gone UUID. Empty/absent `mountedIds` (startup poll window, or standalone before Phase 4) → no gating, so fixed-disk rings aren't blanked. `optOutIds` is `[]` until Phase 3 adds its config key. |
| `sortByLabel(partitions)` | Alphabetical (case-insensitive) sort by label, ties broken by id. The default ordering used by `orderPartitions` for the un-saved tail. |
| `filterToMounted(partitions, mountedIds)` | Keep only the `partitions` whose `id` is in the live `mountedIds` set (from `findmnt`); empty/absent `mountedIds` → passthrough (no live data yet). Gates the Plasma config picker: ksysguard's `SensorTreeModel` freezes on unmount and a *fresh* instance is also stale at the daemon level ([#58](https://github.com/manuacl/ring-monitor/issues/58)), so raw `availablePartitions` would offer an unplugged disk as a live checkbox. The picker feeds the filtered list to `stalePartitions` too, so a still-configured unmounted partition then surfaces as a greyed stale row instead. Exposed as `MetricsBackend.mountedAvailablePartitions`. |
| `stalePartitions(enabledCsv, orderCsv, discovered, labelCacheJson)` | Configured ids no longer discovered (the disk was unplugged) — returned as `[{id, label}]`, order-CSV ids first then enabled-only, deduped. `label` comes from the cache, falling back to the bare UUID. Drives the greyed "no longer connected" rows in the picker (issue #49). |
| `parseLabelCache` / `serializeLabelCache` / `mergeLabelCache` | The UUID→label cache backing the friendly name on stale rows. `mergeLabelCache(prev, discovered, referencedIds)` keeps the fresh discovered label, else the last-known one (so an unplugged partition keeps its name), and is **bounded to `enabled ∪ order`** so it can't grow unbounded. `serializeLabelCache` sorts keys so an unchanged cache round-trips to the same string — no spurious config write per discovery pass. |
| `isRemovableMount(mountpoint)` | `true` when a filesystem's mountpoint marks it as user-plugged removable media — KDE/udisks2 auto-mounts those under `/run/media/<user>/` (older / non-KDE setups: `/media/<user>/`); fixed disks mount under `/`, `/boot`, `/var`, … It's a strict prefix test (`/var/media/...` is **not** removable). The only removable signal available on Plasma (ksysguard exposes no removable flag), and the standalone `/proc/mounts` path sees the same mountpoints, so both platforms classify identically through this one helper. |

Covered by `tests/disk-metrics.test.mjs`.

> New shared `core/*.{js,qml}` **and** `platforms/standalone/*.{js,qml}`
> files must be added to the `QML_FILES` list in `CMakeLists.txt` — the
> standalone build compiles each one into the `RingMonitor.Standalone`
> QML module explicitly. A file missing from that list isn't in the
> module, so any `import` of it fails and the QML root silently fails to
> load (the binary exits `1` with no diagnostic). Conversely,
> `platforms/plasma/*` must NOT be listed (it would be dead code in the
> standalone binary). The Plasma build is unaffected (it loads from the
> filesystem / plasmoid package). Both directions are guarded by
> `tests/standalone-qml-module.test.mjs`.
