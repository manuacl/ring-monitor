# Logic modules

The pure-logic `.js` modules live in one of two places, by usage:

- **`contents/ui/core/`** — shared by both platforms (`MetricsCatalog`,
  `ColorThemes`, `ReorderLogic`, `RingGeometry`, `UpdateCheck`).
- **`contents/ui/platforms/<p>/`** — used by only one platform, kept
  beside that platform's adapter so it isn't shipped as dead code to
  the other artifact: `platforms/standalone/` holds `ProcStatParser`,
  `MemInfoParser`, `CpuTempDiscovery`, `HwmonTempDiscovery`;
  `platforms/plasma/` holds `SensorPicking`, `TempSensorCatalog`. See
  the placement rule in
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
| `splitReadoutOffset(side, splitMode, stacked, size, valuePx)` | `{x, y}` centre offset for a split readout. `side` −1 = left/read, +1 = right/write. Flat (temperature split): horizontal ±18 % of size, one line. `stacked` (disk-I/O split, whose "0.1MB/s" readouts are too wide to share a line): diagonal — read up-left, write down-right — by 0.35×/0.45× valuePx. `!splitMode` → `{0,0}`. |

Why extract this? The earlier inline ternary chain in `Ring.qml`
(`Math.max(4, Math.round(size * 0.055))` repeated five times) is the
canonical signal that a pure-math helper wants to exist. Putting it in a
testable file means changes to "how big should the label be at size 40"
are testable without launching Plasma.

## `DiskIoScale.js`

Scaling + formatting for the disk-I/O throughput ring (issue #77).
Disk throughput has no fixed ceiling, so unlike a usage % it can't map
linearly onto the 0-100% arc. This module implements the **auto-scaling
rolling peak** chosen for #77: each sample updates a decaying per-ring
peak and the arc fills to `rate / peak`, while the numeric label always
shows the real MB/s — the same `Ring.value` vs `rawValue` decoupling the
temperature ring uses (`tempToPercent`). Shared by both backends (Plasma
gets byte/s rates from ksysguard's `disk/all/{read,write}` sensors,
standalone from `DiskStatsParser`), so the peak/combine/format logic is
written once here.

| Function | Purpose |
|---|---|
| `combinedRate(readBps, writeBps)` | Read + write sum (the default "combined" ring). Negative / NaN halves coerce to 0 so one unread sensor never poisons the sum. |
| `updatePeak(prevPeak, rateBps)` | New ceiling for this tick: `max(rate, prevPeak * PEAK_DECAY, PEAK_FLOOR_BPS)`. Rises immediately to a faster live rate; decays ~2 %/tick while idle so a one-off burst doesn't pin the gauge near-empty for the session (the documented "meaning drifts" trade-off). The floor (10 MB/s) avoids a divide-by-zero and stops idle noise from filling the arc. |
| `rateToPercent(rateBps, peakBps)` | `rate / peak`, clamped to `[0, 100]`; non-finite / non-positive peak → 0. Drives the sweep only. |
| `formatRate(bps)` | `"{n} MB/s"` for the centre label — one decimal below 100 MB/s, none above. Always MB/s (10⁶ B, the `iostat`/`dstat` convention) so the label width stays stable across the value animation instead of flipping KB/MB/GB mid-sweep. |

Covered by `tests/disk-io-scale.test.mjs`.

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
| `releaseScope(tag)` | the release-scope suffix (issue #89): `-p` → `"plasma"`, `-s` → `"standalone"`, no suffix → `"both"`. Any non-scope trailer (`-rc1`, …) or malformed input → `"both"`, the safe default that notifies every platform. The suffix lives on the **tag only**, never in `metadata.json`, so `parseSemver` still compares the numeric core. |
| `pickRelevantRelease(releases, platform)` | newest scope-relevant `tag_name` from a GitHub **`/releases` list**, skipping drafts, prereleases, and releases scoped to the other platform. `""` when nothing qualifies. The list (not `/releases/latest`) is queried because the highest tag may be scoped to the other platform — a `-p` release above an intermediate `-s` one a standalone user needs. |
| `shouldNotify(local, remote, acknowledged, platform)` | the badge-visibility test: `isNewerVersion(local, remote)`, the release in scope for `platform`, AND `!acknowledged`. A malformed acknowledged value is treated as no-ack (defensive); an empty `platform` disables the scope filter (the dormant pre-#89 behaviour). |

The two-step gate (`shouldRecheck` for the network call, `shouldNotify`
for the UI) keeps the two concerns independent: a successful fetch with
a remote == local doesn't surface a badge, and an unacknowledged update
keeps showing the badge across widget restarts without re-hitting the
network. Encoded as tests in `tests/update-check.test.mjs`.

### Platform-scoped notifications (issue #89)

The Plasma widget and the standalone build share one version counter
and one GitHub release stream, so a naive "remote is newer" check would
ping a Plasma user for a standalone-only release and vice-versa. The
fix is a **scope suffix on the release tag** — `-p` (Plasma-only), `-s`
(standalone-only), none (both) — read by `releaseScope` and enforced by
`pickRelevantRelease` (selection) + `shouldNotify` (badge). The
`platform` flows in from each adapter via `UpdateChecker.platform`. The
suffix is appended at release time by `version.yml`, which infers the
scope from the cumulative diff since the last tag via
[`scripts/infer-release-scope.sh`](../scripts/infer-release-scope.sh)
(`release.yml` strips it back off so `metadata.json` / the `.plasmoid`
stay clean `X.Y.Z`). The classifier is biased toward *no* suffix: it
marks a release single-platform only when nothing shared (`core/`), no
second platform, and no ambiguity is involved — a wrong suffix would
hide a real update, whereas an extra notification is harmless. Until a
release happens to be single-scope, every tag is unsuffixed (`"both"`)
and behaviour matches the pre-#89 widget. Full rationale: issue #89; the
release-flow details live in [`releasing.md`](releasing.md).

## `ProcessRanking.js`

Pure ranking + formatting for the CPU-ring and RAM-ring process tooltips
(issues #69/#70), shared by both platform adapters. It consumes
**already-normalised** process records and only sorts + formats — the
"total 0-100%" CPU normalisation happens at the source (the standalone
`/proc/<pid>/stat` delta is intrinsically total-normalised over the
system-wide jiffy delta; the Plasma adapter divides ksysguard's reading
by the core count), so this module stays platform-agnostic.

Record shape: `{ pid, name, cpuPercent, rssKb? }`. `rssKb` is populated
by the sampler when memory data is available and used by `rankByMemory`
for the RAM-ring tooltip; `cpuPercent` drives `rankByCpu` for the
CPU-ring tooltip. Both paths share a common `_cleanRecords` normaliser
(coerces `pid` to `Number`, drops records with no `pid`) so the
flicker-prevention tiebreak stays numeric on both.

| Function | Purpose |
|---|---|
| `DEFAULT_LIMIT` | `20` — top-20 cap (issues #69/#70). |
| `rankByCpu(records, limit)` | New array sorted by `cpuPercent` desc, capped to `limit` (default `DEFAULT_LIMIT`). Ties break by `pid` asc so the order is deterministic across ticks (no tooltip flicker). Drops records with no `pid`, coerces NaN/negative/undefined `cpuPercent` to 0, never mutates the input. Non-array input or `limit ≤ 0` → `[]`. |
| `rankByMemory(records, limit)` | New array sorted by `rssKb` desc, capped to `limit` (default `DEFAULT_LIMIT`). Records with absent `rssKb` rank as 0 (kept, not dropped — the backend may not sample memory every tick). Ties break by `pid` asc. Same input guards as `rankByCpu`. |
| `formatCpuPercent(value)` | `12.34` → `"12.3%"` (one decimal, `top`'s precision). NaN/negative/undefined → `"0.0%"`. |
| `formatMemory(rssKb)` | Humanise a KiB count: `< 1024 KiB` → integer KiB, `< 1024 MiB` → one-decimal MiB, else one-decimal GiB. Matches `top`'s RES column precision. |
| `formatMemPercent(rssKb, totalKb)` | `(rssKb / totalKb) * 100` to one decimal + `"%"`. Guards: `totalKb` not finite or `<= 0` → `"0.0%"`; clamped at 100% so a transient RSS spike above total doesn't show `">100%"`. |
| `formatLoadAverages(loads)` | The three kernel load averages → `"0.42  0.55  0.61"` (two decimals, double-space separated). Pads a short/missing array with `0.00`; ignores entries past the first three. The `Load average:` label is added + translated by the QML caller. |

Covered by `tests/process-ranking.test.mjs`.

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

## `TempSensorCatalog.js`

Lives in `contents/ui/platforms/plasma/` — **plasma-only** (the
standalone picker's catalog comes from `HwmonTempDiscovery.js`), same
placement rule as `SensorPicking.js`.

Pure decisions behind the sensorTemp picker's Celsius-sensor discovery
(issue #164). The Plasma side probes in two phases — a cheap
`SensorTreeModel` walk, then a live `Sensors.Sensor` per candidate — and
both sides of that seam defer to this module so the logic stays
Node-testable:

| Function | Purpose |
|---|---|
| `UNIT_CELSIUS` | `KSysGuard::Unit::UnitCelsius` as an int (`1000`), as reported by `Sensors.Sensor.unit` — the Unit enum is not exposed to QML, so the literal is compared here. Live-probe verified (#164). |
| `isTempCandidate(display)` | Phase-1 pre-filter: does a tree DisplayRole string look like a temperature leaf ("Composite (°C)")? The localized name carries the unit suffix; regex/group nodes don't. |
| `disambiguationSegment(id)` | The device/chip part of a sensor id (`"lmsensors/nct6775-isa-0290/temp1"` → `"nct6775"`), bus/address tail stripped — noise in a picker label. |
| `buildTempSensorEntries(probed)` | Phase 2: from probed candidates `[{id, name, unit, ready}]` keep the Celsius + Ready ones and shape the `[{id, label}]` picker list. Per-core CPU temps and the min/max variants are dropped as noise (the cpuTemp metric already covers them — N "Core N" rows crowded the picker, live feedback #167); the average stays. lmsensors names are driver-generic, so they ALWAYS carry the chip segment ("Composite (nvme)"); cpu/gpu names stay bare unless they collide ("GPU (gpu0)"), with the full id as last resort. Sorted locale-aware by label then id so the picker order is stable across discovery refreshes. |

Covered by `tests/temp-sensor-catalog.test.mjs`. The QML adapter running
the two phases is `platforms/plasma/TempSensorDiscovery.qml`.

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
| `parseMountPairs(stdout)` | `[{uuid, label, mountpoint, fstype}]`, one per mounted filesystem with a UUID (`fstype` from the `findmnt -o … ,FSTYPE` column, `""` when absent — feeds the #68 tooltip). `-P` (key=`"value"` pairs) is used over raw columns so spaces in a label or target survive. The UUID is **lower-cased** to match ksysguard's keys (findmnt prints FAT/vfat serials UPPERCASE, e.g. `6F45-2B2F`, while ksysguard uses `6f45-2b2f`). Rows without a UUID (pseudo / network mounts) and rows whose target isn't an absolute path are dropped; a filesystem mounted at several targets (btrfs subvolumes, bind mounts) appears once — the first row, whose target drives the removable classification. Removable classification is **not** done here — that's the shared `DiskMetrics.isRemovableMount(mountpoint)` predicate, applied by the consumer so the standalone `/proc` path classifies through the same rule. |
| `removableList(mounted)` | `[{id, label}]` for the rows flagged `removable` (`id` = the ksysguard-keyed uuid) — the auto-show source `MetricsBackend.removablePartitions` publishes. |
| `uuidList(mounted)` | `[uuid]` for every row — the authoritative "still mounted" set behind `MetricsBackend.mountedPartitionIds` (the #58 self-heal gate). Both helpers take the augmented rows `MountInfo.qml` publishes (parse output + `removable`); null input yields an empty list. |

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

## `DiskStatsParser.js`

Lives in `contents/ui/platforms/standalone/` — **standalone-only** (the
Plasma build gets disk throughput from ksysguard's `disk/all/{read,write}`
sensors, never from `/proc/diskstats`). Pure parse + delta math for the
disk-I/O ring (issue #77): the standalone `MetricsBackend.qml` reads
`/proc/diskstats` via `ProcReader`, hands the raw text here, and gets
byte/s rates that feed the shared `core/DiskIoScale.js` peak-scaling.

| Function | Purpose |
|---|---|
| `parseDiskStats(content)` | Raw `/proc/diskstats` → `{ name: {readSectors, writeSectors} }`. Reads only the two sector counters (3rd + 7th post-name fields); skips lines too short to carry them. Defensive against null / empty input (`{}`). |
| `aggregateWholeDisks(map)` | Sums sector counters across **whole physical disks only** — drops partitions (`sda1`, `nvme0n1p2`, `mmcblk0p1`: their de-suffixed base names a present device), eMMC hardware areas (`mmcblk0boot0`/`boot1`/`rpmb`), and the numbered virtual / stacked device families (`loop`/`ram`/`zram`/`dm-`/`md`/`sr`/`fd`, each anchored on a trailing digit). Summing a disk *and* its sub-devices would multiply the throughput. |
| `ratesFromSamples(prev, cur, intervalSec)` | `{readBps, writeBps}` = sector delta × 512 B / elapsed. A negative delta (counter reset on re-enumeration / hotplug) clamps to 0 rather than flashing a huge spurious rate; non-positive interval → 0. |

Covered by `tests/disk-stats-parser.test.mjs`.

## `ProcParser.js`

Lives in `contents/ui/platforms/standalone/` — **standalone-only** (the
Plasma build sources per-process data from `org.kde.ksysguard.process`
`ProcessDataModel`). Pure parsers for the CPU-ring process tooltip
(issue #69): `ProcessSampler.qml` reads `/proc/<pid>/stat`,
`/proc/loadavg`, and `/proc/stat` via `ProcReader`, hands the raw text
here, and feeds the result to the shared `core/ProcessRanking.js`.
Self-contained (the dual-load convention forbids importing the sibling
`ProcStatParser.js`, so `sumJiffies` is duplicated).

| Function | Purpose |
|---|---|
| `parsePidStat(raw)` | `/proc/<pid>/stat` → `{ pid, name, jiffies }` (jiffies = utime + stime; children excluded, matching `top`). Splits `comm` on the **last** `)` so a process name containing spaces/parens (`(Web Content)`, `((sd-pam))`) doesn't shift the field offsets. `null` on malformed / truncated input. |
| `parseLoadAvg(raw)` | `/proc/loadavg` → `[load1, load5, load15]`; missing/malformed tokens degrade to 0. |
| `sumJiffies(fields)` | Sum of an aggregate-cpu jiffy array — the system-wide total, the denominator for the "total 0-100%" normalisation (a process's jiffy delta over the whole machine's, so a single pegged core reads ~`100/ncores`% and the rows sum toward the aggregate ring). |
| `computePercents(prevMap, curMap, totalJiffiesDelta)` | Per-process CPU% over the interval between two pid→record snapshots, for pids present in **both** (a new pid has no prior sample → appears next tick). Clamps a negative delta (pid reuse) to 0 and the result to `[0, 100]`. Ranking + the top-N cap are the caller's job (`core/ProcessRanking.rankByCpu`). |

Covered by `tests/proc-parser.test.mjs`.

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

## `HwmonTempDiscovery.js`

Standalone-only (in `platforms/standalone/`, beside the adapter — same
placement rationale as `CpuTempDiscovery.js`). Custom hardware
temperature discovery for the sensorTemp metric (issue #164): enumerates
EVERY hwmon temperature input — not just the CPU one, which stays
`CpuTempDiscovery.js`'s job — and gives each a STABLE id the settings
dialog can persist and the backend can resolve back to the current-boot
sysfs path at runtime.

The id grammar never contains `hwmonN` (allocation-order, changes across
boots): `<chipName>/temp<N>` (e.g. `"nvme/temp1"`), or
`<chipName>@<device>/temp<N>` when two hwmon dirs share a chip name
(`<device>` = basename of the hwmon `device` symlink target, e.g.
`"0000:04:00.0"`). Each runtime enumeration rebuilds the id →
current-path map; only the id is stable enough to persist.

| Function | Purpose |
|---|---|
| `buildCatalog(chips)` | From enumerated raw data `[{dir, name, device, sensors: [{input, label}]}]` → `[{id, label, path}]`, sorted chip-name then numeric sensor index. `path` embeds `hwmonN` (current boot only — resolve at runtime, never persist); a missing `tempN_label` falls back to the bare `tempN`. Sensorless chips still count for name-collision detection, so an id doesn't change shape when a sensor appears after a late modprobe. Every label carries the chip stem — `Composite (nvme)`, `Tctl (k10temp)` — because the raw sysfs names are too generic to pick from; a duplicated stem-form (same label twice on ONE chip) falls back to the full id. |
| `resolveSensorPath(catalog, id)` | Persisted id → current-boot sysfs path, or `""` when the id isn't in the catalog (sensor gone, or enumeration hasn't run yet). |
| `buildThermalCatalog(zones)` | Catalog from `/sys/class/thermal` zones, UNIONED with the hwmon one after `filterMirroredZones` drops the zones a chip already exposes (`HwmonTempSensors.enumerate()` always walks both). Same grammar: `<type>/temp`, `<type>@<device>/temp` on type collision; a colliding type with NO resolvable device falls back to `<type>@<zone-dir>/temp` — the zone number is registration-order (unstable), but a duplicated id is strictly worse (the picker's text→id first-match would make the twin unreachable). Zones have no label file — the type is the name, left bare (no redundant `acpitz (acpitz)` stem suffix). |
| `filterMirroredZones(chips, zones)` | Drops the thermal zones a hwmon chip already exposes: the kernel links a thermal-backed chip to its zone through the `device` symlink (basename == zone dir, e.g. `hwmon0 acpitz_0` → `thermal_zone0`). Keeps everything when `chips` is empty (ARM boards / VMs whose temps live only in the thermal framework — the union then equals the full thermal catalog); a chip with an unresolvable device symlink never mirrors. |
| `parseTempCelsius` / `isTempInput` / `tempIndexFromInput` | Verbatim copies of the `CpuTempDiscovery.js` one-liners — dual-loaded modules can't import each other (QML's `.import` is a syntax error under Node `require`), the same duplication `GpuDiscovery.js` already carries. |

Covered by `tests/hwmon-temp-discovery.test.mjs`. The QML probe adapter
is `platforms/standalone/HwmonTempSensors.qml` (sysfs walk through
`ProcReader`, incl. the `readLink` of the `device` symlink).

## `GpuDiscovery.js`

Standalone-only sysfs-based AMD/Intel GPU discovery (in
`platforms/standalone/`, beside the adapter — same placement rationale as
`CpuTempDiscovery.js`). Mirrors the same I/O-injected pure-module pattern:
`MetricsBackend.qml` passes `listDir` / `read` closures so this module
never touches sysfs directly and is fully Node-testable.

Walks `/sys/class/drm/card*`, reads the vendor id, and returns the sysfs
paths the backend should poll each tick. NVIDIA (`0x10de`) is excluded —
handled by `NvmlReader` / NVML. AMD utilisation needs kernel 4.19+
(`amdgpu` driver); Intel utilisation is deferred (i915-perf needs elevated
perms); temperature works for both via the DRM card's `device/hwmon`
entry.

| Function | Purpose |
|---|---|
| `discoverGpu(listDir, read)` | Main entry. Returns `{ vendor, busyPath, tempPath }` for the first AMD or Intel DRM card (lowest card number wins), or `null` when none exists. `vendor` is `"amd"` or `"intel"`; `busyPath` is the `gpu_busy_percent` sysfs file or `null` (Intel, or AMD on older kernels); `tempPath` is `device/hwmon/hwmonN/temp1_input` or `null`. The AMD branch additionally sets, **when the node exists** (key omitted otherwise — graceful degrade for the GPU tooltip, issue #71): `vramUsedPath` / `vramTotalPath` (`device/mem_info_vram_{used,total}`, bytes) and `powerPath` (`device/hwmon/hwmonN/power1_input`, **microwatts** — the consumer divides by 1e6 for watts). |
| `parseTempCelsius(raw)` | Millidegrees-C sysfs reading → °C. Same formula as `CpuTempDiscovery.parseTempCelsius`; duplicated here to keep `GpuDiscovery.js` self-contained without a cross-module import. |
| `_sortedDrmCards(entries)` | Filter a `listDir("/sys/class/drm")` result to `card\d+` entries, sorted numerically (card0 < card1) for a stable pick across boots. |
| `_drmHwmonDir(hwmonBase, listDir)` | Walk a card's `device/hwmon/` directory and return the first `hwmonN` directory path, or `null`. Shared by `tempPath` (`/temp1_input`) and the AMD `powerPath` (`/power1_input`). |
| `_drmHwmonTempPath(hwmonBase, listDir)` | Thin wrapper over `_drmHwmonDir` returning `<dir>/temp1_input` (or `null`). |

Covered by `tests/gpu-discovery.test.mjs` (AMD with/without `gpu_busy_percent`,
Intel temp-only, NVIDIA excluded, card-order stability, NVIDIA+AMD mixed
host, case-insensitive vendor match).

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
| `parseMounts(content)` | `/proc/mounts` → `[{device, mountpoint, fstype}]` for real block-device filesystems only. The `device.startsWith("/dev/")` test drops composefs/overlay/tmpfs/fuse in one rule (their device field isn't a `/dev` path); `squashfs` is additionally skipped (loop-mounted system images); and the EFI System Partition is filtered — a FAT-family fstype (`vfat`/`msdos`/`fat`) on an EFI mountpoint (`/boot/efi`, `/efi`, or a no-xbootldr `/boot`), since the ESP is a real `/dev` block device the rules above don't catch. The match is deliberately narrow: an ext4 `/boot` (a separate xbootldr partition) and a FAT data disk mounted elsewhere both survive — matching ksystemstats, which omits only the ESP, so the two builds' pickers agree (issue #66). Un-escapes octal `\040`-style mountpoints. |
| `buildPartitions(mounts, blockInfo)` | Dedup by device → `[{id, label, mountpoint, fstype, device}]`. `id` = fs UUID (falls back to the device path), `label` = volume label (falls back to the device basename), `mountpoint` = the shortest mount of that device (any works for `statvfs` — same filesystem), `fstype` = the filesystem type (identical across a device's mounts; feeds the #68 tooltip). Collapses the 5 mounts of an rpm-ostree btrfs root into one entry. |
| `defaultSelection(mounts, partitions, canonicalHome)` | `[id]` of the filesystem bearing `$HOME` — the longest mountpoint that is a prefix of the resolved home path (e.g. `/var/home` over `/var` over `/`). `[]` when home can't be matched. |

Covered by `tests/disk-discovery.test.mjs` (real rpm-ostree `/proc/mounts`
SCENARIO: sda3 mounted 5× → one root partition; composefs / tmpfs /
fuse dropped; the vfat ESP at `/boot/efi` dropped while ext4 `/boot`
(xbootldr) stays; `$HOME=/home/user` → `/var/home` → sda3).

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
| `isPartitionShown(id, removableIds, enabledIds, optOutIds)` | The picker checkbox's `checked` rule, so the box reflects ring **visibility**: a removable (`id ∈ removableIds`) is shown unless opted out (auto-show); a fixed disk is shown iff manually enabled. Per-partition mirror of `resolveDiskRingIds` membership for a mounted partition (no maxCount/default). The toggle is the inverse — `MetricsBody.setPartitionEnabled` writes the opt-out list for a removable, the manual selection for a fixed disk. |
| `stalePartitions(enabledCsv, orderCsv, discovered, labelCacheJson)` | Configured ids no longer discovered (the disk was unplugged) — returned as `[{id, label}]`, order-CSV ids first then enabled-only, deduped. `label` comes from the cache, falling back to the bare UUID. Drives the greyed "no longer connected" rows in the picker (issue #49). |
| `parseUuidMap` / `serializeUuidMap` / `pruneMap` | Generic tolerant UUID→string JSON-map primitives, shared by the label cache **and** the per-partition color map. `parseUuidMap` returns `{}` on empty/malformed input; `serializeUuidMap` sorts keys so an unchanged map round-trips to the same string (no spurious config write); `pruneMap(json, keepIds)` drops entries whose id isn't in `keepIds`, bounding a map to the referenced partitions. |
| `mergeLabelCache(prev, discovered, referencedIds)` | The UUID→label cache backing the friendly name on stale rows: keeps the fresh discovered label, else the last-known one (so an unplugged partition keeps its name), **bounded to `enabled ∪ order`** so it can't grow unbounded. |
| `colorFor` / `withColor` / `withoutColor` / `resolveRingColors` | The **per-partition disk ring color** map (UUID→`#rrggbb`, issue #67). `colorFor(json, id)` → the stored color or `""` (→ inherit the shared color); `withColor`/`withoutColor` are immutable set/remove (`MetricsBody.setPartitionColor`/`clearPartitionColor` write through them); `resolveRingColors(ids, json, fallback)` returns colors aligned to `ids` (outermost first), the override where set else `fallback` (the shared ring color) — drives `Ring.equalColors` via `MainContent._diskColors`. One fixed color per disk (no light/dark pair); un-overridden partitions still track light/dark through the fallback. The color map is bounded to `enabled ∪ order ∪ discovered` via `pruneMap` (`MetricsBody._refreshColorMap`) — a discovered partition's color is kept even when unchecked/unordered (the picker can color it); only a color whose partition is both gone and unreferenced is pruned. |
| `buildPartitionDetail(id, info, stats)` | Assemble the per-partition detail object the disk-ring tooltip renders (issue #68): both backends pass the `id`, the resolved `info` (`{label, mountpoint, fstype}`) and the read `stats` (`{usedPercent, totalBytes, freeBytes}`); this owns the defaulting + the single removable rule (`isRemovableMount` on the mountpoint). `usedPercent` is the caller's gauge value, never recomputed here — the % the ring is drawn from and the tooltip's % can't disagree. Consumed by `DiskTooltipModel.buildRows`. |
| `isRemovableMount(mountpoint)` | `true` when a filesystem's mountpoint marks it as user-plugged removable media — KDE/udisks2 auto-mounts those under `/run/media/<user>/` (older / non-KDE setups: `/media/<user>/`); fixed disks mount under `/`, `/boot`, `/var`, … It's a strict prefix test (`/var/media/...` is **not** removable). The only removable signal available on Plasma (ksysguard exposes no removable flag), and the standalone `/proc/mounts` path sees the same mountpoints, so both platforms classify identically through this one helper. |

Covered by `tests/disk-metrics.test.mjs` (+ `tests/disk-colors.test.mjs` for the color-map + `pruneMap` layer). The color map lives here, not in a separate `DiskColors.js`, because the dual-load convention (Node `--test` + QML) forbids a `.js` importing a sibling `.js` — so sharing the `parseUuidMap`/`serializeUuidMap` plumbing requires living in the same file (same reason `parseCsv` is duplicated rather than imported).

## `DiskTooltipModel.js`

Shared (`core/`) presentational logic for the disk-ring **hover tooltip**
(issue #68). Both platform backends expose the same per-partition detail
object; the view (`DiskTooltip.qml`) stays thin, repeating over
`buildRows()`'s output. All formatting + composition lives here so it's
tested once.

The `partitionDetail(id)` contract each backend satisfies (one object):
`{ id, label, mountpoint, fstype, usedPercent, totalBytes, freeBytes,
removable }`. `usedPercent` is the **same number the ring is drawn from**
(ksysguard `usedPercent` on Plasma, the `df` formula on standalone — the
documented per-platform divergence), never recomputed from the bytes, so
the tooltip can't disagree with the gauge. `totalBytes`/`freeBytes` are
`0`/absent until the source resolves → the byte figures degrade to
percent-only.

`freeBytes` is **what the user can actually write** (statvfs `f_bavail` / df
"Avail"), the file-manager convention. `buildRows` derives `used = total -
free` (so `used + free = total` always holds), which means an ext4 root's
reserved blocks (~5%, root-only) count as *used* in the byte figures while
`usedPercent` follows the `df` formula that **excludes** the reservation — so on
a reserved-block filesystem the used/total ratio can read a few % above the
displayed `%`. The `%` stays authoritative (it's the ring's number); the byte
figures are illustrative. btrfs (no classic reservation) shows no gap.

| Function | Purpose |
|---|---|
| `formatSize(bytes)` | IEC binary size string (`56 GiB`, `1.5 TiB`, `512 B`), `df -h` style — one decimal below 10, integer above, promote at the rounding boundary (`1023.7 GiB` → `1.0 TiB`). NaN / negative coerce to `0 B`. Capacity is binary (Dolphin convention), deliberately NOT the SI 10³ steps `DiskIoScale` uses for I/O *rate*. |
| `composeUsage(usedPercent, usedBytes, totalBytes)` | `12% · 56 GiB / 466 GiB`, or just `12%` when `totalBytes ≤ 0` (bytes source not yet resolved). `%` is rounded, taken as-is from the ring's value. |
| `composeFree(freeBytes, totalBytes)` | `120 GiB free`, empty when `totalBytes ≤ 0` (so the view hides the line rather than show a misleading `0 B free`). |
| `subLabel(mountpoint, fstype)` | `/ · btrfs`; one alone when the other is missing; `""` when both are. The dimmed second line disambiguating same-labelled volumes. |
| `iconFor(removable)` | Freedesktop icon name — `drive-removable-media` for an auto-shown removable, `drive-harddisk` for a fixed disk. |
| `buildRows(details)` | Maps the `partitionDetail[]` (ring order, outermost first) to the view's row model `[{ id, label, subLabel, usageText, freeText, iconName, removable }]`; derives `used = total − free` (clamped at 0). Non-array → `[]`. |

Covered by `tests/disk-tooltip-model.test.mjs`.

## `GpuTooltipModel.js`

Shared (`core/`) presentational logic for the GPU-ring **hover tooltip**
(issue #71). Same shape as `DiskTooltipModel`: both platform backends expose
one per-device detail object and the view (`GpuTooltip.qml`) stays thin,
iterating `buildStatRows()`'s output and rendering strings. All formatting +
composition lives here so it's tested once.

The `gpuDetail` contract each backend satisfies (one object):
`{ model, usagePercent, vramUsedBytes, vramTotalBytes, tempC, powerW,
clockMhz }`. **Every field may be absent** (undefined/NaN) — GPU telemetry is
host-dependent, so NVIDIA (NVML) supplies all fields while AMD supplies some
and Intel few. `buildStatRows()` skips any row whose source is absent, so the
tooltip degrades gracefully per host rather than showing fake zeros. VRAM size
follows the IEC binary convention (same `formatVram` idiom as
`DiskTooltipModel.formatSize`), distinct from the SI rate units of
`DiskIoScale`.

| Function | Purpose |
|---|---|
| `formatVram(bytes)` | IEC binary size string (`8.0 GiB`, `24 GiB`, `512 MiB`) — one decimal below 10, integer above, rounding-boundary promotion. NaN / negative → `0 B`. |
| `formatPower(watts)` | `42.5 W` below 100, `115 W` at/above (one decimal only where legible). `""` when the sensor is absent / non-finite, so the row is skipped. |
| `formatClock(mhz)` | `1815 MHz` (integer). `""` when absent. |
| `formatPercent(value)` | `73%` — rounded integer, negative clamped to 0. Used for engine utilisation. |
| `composeVram(usedBytes, totalBytes)` | `6.2 GiB / 24 GiB · 26%` when `totalBytes > 0`; `""` when total is unknown (so the line hides rather than show `0 B / 0 B`). |
| `buildStatRows(detail)` | Ordered view model `[{ label, value }]` — Model, Usage, VRAM, Temperature, Power, Clock — **omitting any line whose source field is absent**. A full-NVIDIA host shows all six; an Intel host may show only Model/Usage/Temperature. |
| `dedupeByPid(records)` | Collapse duplicate pids (process appears once per compute context + once per graphics context in NVML enumeration) keeping max `vramBytes`. Input `[{pid, vramBytes}]` → output `[{pid, vramBytes}]` with duplicates merged. Non-array → `[]`. |
| `rankProcesses(records, limit)` | Sort `[{ pid, name, vramBytes }]` by `vramBytes` descending, tiebreak `pid` ascending, cap to `limit` (default `DEFAULT_LIMIT = 20`). Absent `vramBytes` ranks as 0 (kept, not dropped). Non-array → `[]`. |
| `formatProcessVram(bytes)` | Alias of `formatVram` (same unit family) for the process VRAM column. |

Covered by `tests/gpu-tooltip-model.test.mjs`. No backend or view consumes it
yet — PR1 of the #71 sequence lands the tested contract; the platform backends
(VRAM/power/clock/model + NVIDIA processes) and `GpuTooltip.qml` view follow.

## `WindowPlacement.js`

Standalone-only placement math for the root window (in
`platforms/standalone/`, beside `Main.qml` — the Plasma panel positions
its own slot). Resolves the user's `windowAnchorCorner` + `windowMarginX`
/ `windowMarginY` + `windowScreen` config into concrete geometry for whichever
host path is active, and is the single tested source of truth shared by both
(issue #98, #142).

| Function | Purpose |
|---|---|
| `cornerToAnchorSpec(corner)` | `corner` → `{left, top}` booleans (which screen edges the margins inset from; `false` = right / bottom). Unknown corner → top-right. Used by the Wayland layer-shell path: `Main.qml` passes the spec to `wayland_layer_shell.cpp` `configure()`, which maps it to `LayerShellQt` anchor enums + `QMargins`. |
| `computeX11Origin(corner, screenW, screenH, winW, winH, marginX, marginY, screenX, screenY)` | Absolute top-left `{x, y}` for the X11 / XWayland path, where the window is a managed toplevel positioned via `WindowAnchor.setGeometry`. Margins inset from the anchored edge; opposite-corner cases subtract the window extent so the content stays on-screen. Callers pass an already screen-capped `winW`/`winH`, and (new with #142) `screenX`/`screenY` are the virtual-desktop offsets of the target screen (0 for primary; non-zero for right-side/bottom-side monitors). |
| `pickScreen(screens, name)` | From `Qt.application.screens` (array-like, NOT a JS Array — guard is length-based), return the screen whose `.name` matches (e.g. `"HDMI-1"`, `"DP-2"`). Returns `null` for an empty/unknown name or empty list — the CALLER owns the fallback (follow the window's current screen); the stored name is never modified. |

The corner-set lives here as `CORNERS`; `AppearanceBody.qml` keeps its own
parallel value array (a core component can't import a `platforms/*`
module — the plasma-isolation invariant), so the two must stay in sync.
Covered by `tests/window-placement.test.mjs` (4 corners × margins, the
pre-#98 top-right parity case, unknown-corner fallback, screen-name picking
and hot-plug fallback).

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

## `BatteryAggregate.js`

Shared (`core/`) fold from per-battery records to one ring value (issue
#94). Both platforms discover batteries differently (Plasma via a
`SensorTreeModel` walk, standalone via `/sys/class/power_supply`) but
hand the same shape to this module, so the aggregation rule lives once
in `core/`.

| Function | Purpose |
|---|---|
| `aggregate(records)` | Combine `[{ percent, weight, charging }]` into `{ percent, charging, available }`. `available` is true only for a non-empty array with at least one finite-`percent` entry (a desktop with no battery → `available:false` → the ring is hidden via the availability interface, #52). `percent` is the **weight-weighted** mean (weight = battery capacity), clamped to `[0,100]`; records with a non-finite `percent` are dropped, and a zero/absent total weight degrades to a simple arithmetic mean. `charging` is the **OR** across batteries — any battery charging (laptop plugged in) reads charging. |

Covered by `tests/battery-aggregate.test.mjs` (empty / null, single &
multi-battery weighting, zero/non-finite weights, charging OR, clamping,
NaN filtering).

## `BatteryStatus.js`

Standalone-only (`platforms/standalone/`) sysfs parsers for
`/sys/class/power_supply/BAT*/` (issue #94) — kept beside the standalone
`BatterySampler` (the only consumer) so it isn't dead-shipped in the
Plasma plasmoid.

| Function | Purpose |
|---|---|
| `isBatteryDir(name)` | `true` for a `BAT*` entry (`/^BAT/i`); AC-adapter dirs (`AC`, `ADP0`, `mains`, …) are excluded so only real batteries are sampled. |
| `parseCapacity(raw)` | The `capacity` file → integer **clamped to [0, 100]**, or `NaN` for absent / empty / garbage. The clamp keeps the contract true at the boundary (some ECs report 105) instead of relying on `aggregate`'s single downstream clamp, which a multi-battery weighted mean would skew before reaching. |
| `isCharging(statusRaw)` | The `status` file → bool. `"Charging"` and `"Full"` map to `true` (plugged in), `"Discharging"` / `"Not charging"` / unknown to `false`. Case-insensitive, tolerant of the sysfs trailing newline. |
| `parseWeight(raw)` | `energy_full` or `charge_full` → the capacity weight; absent / non-positive / garbage → `1` so weighting degrades to a simple mean. |

Covered by `tests/battery-status.test.mjs` (battery-vs-AC names, capacity
trimming, charging states incl. `Full`, weight fallback). The Plasma side
has no equivalent — ksysguard exposes the charge percentage as a sensor
and no per-battery capacity, so its `BatterySampler` weights all
batteries equally and reads charging from the charge-rate sign.
