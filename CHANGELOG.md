# Changelog

**Every PR** adds a `### Technical` entry under `## [Unreleased]` — the
per-PR implementation log. When a release is **tagged** (a `bump:*`-labelled
PR merges), its **user-facing** summary (Added / Changed / Fixed — what
changed for someone running the widget) is written at the top of the new
version section, **grouping all changes since the last tag**, with the
accumulated Technical detail moved underneath. A PR that changes only docs
or CI (nothing to log technically) adds a single `### Other` one-liner
instead — neither user-facing nor technical. Entries before 0.7.0 are
user-facing only.

## [Unreleased]

### Added

- New **Battery** ring showing charge level 0–100 % (#94). Add it like any other metric in the settings. The arc **dims while on battery** and brightens when plugged in / charging, so a glance tells you the power state. On laptops with two batteries the ring shows a single capacity-weighted total; on a desktop with no battery the ring simply doesn't appear. Works on both the Plasma widget and the standalone app.

### Technical

- feat(ui): battery charge ring (issue #94), wired end-to-end on both platforms behind the #52 availability interface so a battery-less desktop never shows a dead ring. New shared pure fold `core/BatteryAggregate.js` (`aggregate([{percent,weight,charging}]) → {percent,charging,available}` — capacity-weighted mean, charging = OR across batteries, drops non-finite entries, falls back to arithmetic mean on zero/missing weight). **Plasma:** new `platforms/plasma/BatterySampler.qml` enumerates `power/*/chargePercentage` leaves from a `SensorTreeModel` walk (no `power/all` aggregate; batteries keyed by UDI tail, re-walked on tree changes) + a charge-rate sensor per battery, aggregated via the shared fold, exposed as a reactive `battery` property (Instantiator tick-counter pattern). **Standalone:** `MetricsBackend._sample()` reads `/sys/class/power_supply/BAT*/{capacity,status,energy_full|charge_full}` via new `platforms/standalone/BatteryStatus.js` parsers, same fold. `MainContent` routes the battery percent to the ring and multiplies arc opacity by a discharging-dim factor; `MetricsCatalog` gains the `battery` id (no ksysguard sensor id, availability-gated) + `isBatteryMetric()`. The charging cue (bright = not draining) is aligned across hosts: a plugged-in battery (charging or full) is bright, a discharging one dims. They derive it from different data — ksysguard exposes no charge-state/AC-online sensor, so Plasma reads the signed `chargeRate` and treats `rate >= 0` (incl. full-on-AC `rate == 0`) as charging to match standalone's `status="Full"`→charging; documented in `docs/components.md`. New `tests/battery-aggregate.test.mjs` + `tests/battery-status.test.mjs`; `metrics-catalog` / `metrics-backend` / `standalone-metrics-backend` / `tst_MetricsBody` guards extended; both new shared modules registered in `CMakeLists.txt`. `tests/metrics-catalog.test.mjs` split (`classifyDiscoveredIds` cases → `tests/metrics-catalog-classify.test.mjs`) to stay under the 500-line cap.
### Other

- ci: the `qmlformat is a no-op` gate now reports every dirty file in a single run (accumulate-then-exit, same pattern as the file-size gate) instead of exiting on the first one — plus a comment noting the local qmlformat may be newer than the Fedora 41 container's, so a locally-clean tree is not sufficient proof (#161).

## [0.16.0] — 2026-08-06

### Added

- New **custom hardware temperature** metric (#160): display any temperature sensor exposed by your system — liquid-cooling loop, motherboard, SSD… Pick the sensor ID, give the ring its own label, and set the min/max °C range the ring scales against. Optional and off by default; the existing CPU/GPU temperature rings are unchanged.

- The custom temperature metric is now much easier to set up (#164): pick from a **dropdown of the temperature sensors discovered on your system** — each clearly named with its chip, with the live reading shown next to the selected one — instead of typing a sensor ID by hand. It now works in the **standalone app** too (hwmon sysfs), and the CPU and GPU temperature rings each get their own configurable min/max range.

### Technical

- fix(metrics): sensorTemp post-review follow-ups (#167). Thermal zones are no longer an empty-hwmon-catalog fallback but UNIONED with the hwmon catalog: new pure `HwmonTempDiscovery.filterMirroredZones(chips, zones)` drops the zones a chip already exposes (kernel link: the chip's `device` symlink basename IS the zone dir — `hwmon0 acpitz_0` → `thermal_zone0`), keeping the rest with boot-stable ids even if a driver late-modprobes at the next boot (previously a persisted thermal id silently broke in that flip); `HwmonTempSensors.enumerate()` now always walks `/sys/class/thermal` (`_readThermalZones()` is I/O-only again). Colliding thermal types without a resolvable device now get a `<type>@<zone-dir>/temp` id instead of a bare-duplicate the picker's text→id first-match made unreachable (registration-order suffix, unstable — the lesser evil). Comment cleanups: `SensorTempSettings.qml`'s duplicated KCM/Timer rationale reduced to a pointer at `platforms/plasma/CLAUDE.md`, stale `_stemOf` "on collisions" wording corrected. Also: the AI-attribution footer is dropped from the `finish-branch` PR template and the no-footer convention recorded in root `CLAUDE.md` § Working rules.

- feat(metrics): sensorTemp picker UX, standalone hwmon port, and per-metric temperature bounds (#164). **Picker (both platforms):** `SensorTempSettings` is rewritten around an editable ComboBox of discovered sensors (free-text fallback kept for custom/regex ids — `sensorId` stays the source of truth) with a live reading label ("Currently 42.3 °C", tempUnit-formatted) and a contextual error InlineMessage; the rest of the form stays collapsed until an id is set. Discovery is a gated child adapter per platform. Plasma: new `TempSensorDiscovery.qml` (extracted from `MetricsBackend.qml`, 500-line cap) runs a two-phase probe — `SensorTreeModel` walk with a "(°C)" DisplayRole pre-filter, then an `Instantiator` of `Sensors.Sensor` — with every decision in the new pure `TempSensorCatalog.js` (Celsius = `unit === 1000`; the KSysGuard Unit enum isn't exposed to QML); gated by the new `MetricsBackend.tempSensorDiscoveryActive`, which only `configMetrics.qml` turns on. Standalone: new pure `HwmonTempDiscovery.js` builds the catalog with STABLE hwmonN-free ids (`<chip>/temp<N>`, `<chip>@<device>/temp<N>` on chip-name collisions, device = basename of the `device` symlink read via the new `ProcReader.readLink()`; picker labels carry the chip stem — `Composite (nvme)` — since the raw sysfs names are too generic to pick from; `/sys/class/thermal` zones no hwmon chip exposes are UNIONED into the catalog — mirrored zones are filtered via the kernel's `device`-symlink link (basename == zone dir), so x86 lists don't double and a zone id survives a driver late-modprobing at the next boot), and `HwmonTempSensors.qml` is the thin probe adapter — the settings dialog owns one (active → 2 Hz readings while visible), the backend reuses one with `active: false` and reads only the configured sensor per tick (bounded 60-attempt enumeration retry, same as the CPU temp). The standalone `MetricsBackend` gains `sensorTempId` (bound from ConfigStore in `Main.qml`) and the Plasma-parity surface (`tempSensors` / `sensorTempResolved` / `sensorTempValue`); the old `sensorTemp: false` availability hard-gate is gone, and the `sensorTempSupported` editor-gate flag (added in #160 for standalone) is removed entirely — both platforms now render the picker. **Per-metric bounds:** new `cpuTempMinC/MaxC` / `gpuTempMinC/MaxC` keys (Int, defaults 30/90 — the old hardcoded `Catalog.TEMP_MIN_C/TEMP_MAX_C`) through all six touch points; the min/max editor is extracted to `core/TempRangeSettings.qml` (reused by `SensorTempSettings` and by the renamed `cpuTempOptions` / `gpuTempOptions` sub-options — merge toggle + always-visible bounds editor). `MainContent._tempBounds(id)` maps every temp ring with its per-metric bounds, dedicated ring AND merged half-arc — split mode now computes `Catalog.tempToPercent(metricRawTemp(id), bounds…)` locally instead of calling `metricTempPercent()` (kept on the backend surface, unused by core). KSysGuard quirk from the live probe: `SensorTreeModel` has no Name/Unit roles (bogus-role reads fall back to the localized DisplayRole) and regex group nodes never go Ready — pinned in `platforms/plasma/CLAUDE.md`. Not implemented from the issue: the "show bounds in tooltip" mitigation (temp rings have no tooltip).

- fix(config): sensorTemp settings polish from the post-review UX pass (#160). The min/max spinboxes now follow the configured temperature unit — bounds stay stored in °C but display/edit in °F when selected (labels + values convert, resolved via `Catalog.resolveTempMode` exactly like the rings; one °F step can collapse to the same rounded °C, harmless for a display bound). `SensorTempSettings` gains a `tempUnit` input wired from `MetricsBody` through `MetricSubOptions`. Standalone: the sensorTemp row no longer renders its settings editor at all — new `MetricsBody.sensorTempSupported` flag (default true; `MetricsRowDelegate` only attaches the sub-option when it isn't explicitly false), set false by `SettingsDialog` because the platform has no ksysguard and the editor was editable-but-inert there. Re-enabled on standalone by the hwmon port (issue #164).

- feat(metrics): add a configurable hardware temperature metric (#160). New `sensorTemp` catalog id renders any KSystemStats temperature sensor as a ring, configured from the Metrics page (sensor ID, custom ring label, min/max °C range scaling the sweep via `Catalog.tempToPercent`). `sensorTemp` joins `TEMP_METRIC_IDS` with no fixed `METRIC_SENSOR_IDS` entry: the Plasma `MetricsBackend` binds a `Sensors.Sensor` to the user-provided `sensorTempId` and gates `availableMetrics` on a non-empty ID + `Sensor.Ready`, so the row stays greyed until a valid sensor is configured; `configMetrics.qml` additionally keeps the id out of the warm-up passthrough until an ID is set. `MainContent` applies the custom min/max to the sweep and the custom label to the ring. Metrics config UI split to respect the 500-line cap: `MetricsRowDelegate` (row ↔ metric wiring) and `MetricSubOptions` (per-metric child components) extracted from `MetricsBody`, new `SensorTempSettings` / `TemperatureUnitSettings` components; `MetricRow` gains `extraContentEnabled` so the sensor settings stay editable while the metric row is disabled. QML suite split per concern (`tst_MetricsBodyDisk.qml`); the catalog temperature / sensor-value tests moved to `metrics-temperature.test.mjs`. New core QML files registered in `CMakeLists.txt` for the standalone build (their absence broke the AppImage smoke-test at runtime — caught by `standalone-qml-module.test.mjs`); the Plasma `MetricsBackend.qml` shed its inline mounted-set loops to new pure `MountInfo.removableList` / `uuidList` helpers to get back under the cap. Standalone: the `sensorTemp*` keys are persisted and bridged in `SettingsDialog`, and the metric is explicitly gated unavailable (no ksysguard on that platform).

### Other

- docs: replace the dangerous symlink dev workflow with the copy-based `ring-monitor_dev` install (distinct patched Id, coexists with the KDE Store version) across `docs/development.md`, `README.md`, `CLAUDE.md`, `docs/architecture.md`, `docs/config-dialog.md`, the docs indexes and the `skills/` SKILL.md files — the symlink could make Plasma delete the whole repo when the widget was uninstalled (#163). Also adds `skills/` to the bump-label docs-only allowlist (and drops the `.claude/` entry, dead since the tool-local files were gitignored) in `skills/bump-label` / `skills/finish-branch` — same class of false `bump:patch` as the CHANGELOG.md case fixed after PR #143.

## [0.15.0] — 2026-06-17

### Added

- Hover the **GPU ring** to see a detail tooltip — GPU model, utilization, VRAM used/total, temperature, power draw, and clock. On NVIDIA the tooltip also lists the **top GPU processes** by VRAM use (name · PID · VRAM). Fields your hardware doesn't expose are hidden, so the tooltip shows only what your GPU actually reports. Works on both the Plasma widget and the standalone app (#71).

### Technical

- fix(gpu): GPU processes never rendered in the tooltip on NVIDIA (#71, found in live verification) — two stacked bugs. **(1) C++/NVML:** `NvmlReader::runningProcesses()` queried the process count with a NULL buffer (count=0); on driver 610 the call returned `NVML_SUCCESS`+count instead of `NVML_ERROR_INSUFFICIENT_SIZE`, so the device was skipped and the list came back empty (live probe: 0 results despite `nvidia-smi` listing 20+ graphics processes). Rewritten to the pre-sized-buffer idiom (nvtop/btop): pass a 256-slot buffer, grow once and refill on `INSUFFICIENT_SIZE` — never probe with `nullptr`. **(2) Pure JS:** `GpuTooltipModel.dedupeByPid` / `rankProcesses` guarded their input with `Array.isArray()`, which is **false** for the `QVariantList` `runningProcesses()` returns (it reaches QML array-*like*, not a true Array), so all 22 records were dropped (`raw=22 → ranked=0`). Switched to an array-like guard (`typeof x.length === "number"`) — the exact trap in `core/CLAUDE.md` § "QML list properties are NOT JS Arrays" (Node tests pass real Arrays, so the bug stayed green in unit tests while production showed nothing). Regression-pinned: array-like-object cases in `gpu-tooltip-model.test.mjs`, a no-null-probe guard in `nvml-reader.test.mjs`.

- feat(ui): wire the GPU detail tooltip into the UI (issue #71, PR4 — the capstone, carries the user-facing bump). New `core/GpuTooltip.qml` renders the stat rows from `GpuTooltipModel.buildStatRows` plus, on NVIDIA, a top-process sub-list via `rankProcesses` + `formatProcessVram`, reusing the shared `TooltipBehavior` chrome with the body as a direct `contentItem`. `MainContent` arms it on the gpu ring and drives `gpuDetailSamplingActive` through one `when`-gated `Binding` (a single gpu ring → the disk pattern, not the cpu/ram content-scope fan-in), reading `metrics.gpuDetail` / `metrics.gpuProcesses` **only while hovered**. Review follow-ups deferred from PR2/PR3 landed here now that there's a consumer: `gpuDetail` / `gpuProcesses` are now reactive `readonly property var` on both adapters (a function call is not a tracked binding dependency — the live list would otherwise freeze, per `core/CLAUDE.md` § "Reactive argless data"); the NVIDIA process list is ranked + capped to the displayed top-N **before** the `/proc` name-resolution loop so only shown pids hit the GUI thread; the standalone AMD detail-path retry gate now also waits on the VRAM/power sysfs nodes (they can register after busy/temp); and `_gpuProcesses` is cleared on gate-off so a reopened tooltip can't flash last session's maybe-exited pids. Known multi-GPU limitation (single-aggregate-panel by design): on Plasma with >1 GPU the VRAM is the `gpu/all` aggregate while model/power/clock are the first device's — the "Model" row identifies which. New `tests/qml/tst_GpuTooltip.qml`; `main-content-tooltip-wiring.test.mjs` extended to the fourth tooltip; `GpuTooltip.qml` registered in `CMakeLists.txt` for the standalone build.

- feat(backend): add NVIDIA top-GPU-processes backend on both adapters (issue #71, PR3 of the sequence). **Standalone:** new C++ `NvmlReader::runningProcesses()` enumerates NVIDIA GPU processes via NVML `nvmlDeviceGetComputeRunningProcesses_v2` + `nvmlDeviceGetGraphicsRunningProcesses_v2` (non-fatal symbols, requires driver ≥ R460; absent → empty list), returns `[{pid, vramBytes}]`. Pure `GpuTooltipModel.dedupeByPid(records)` collapses duplicate pids (a process appears once per compute + once per graphics context) keeping max vramBytes. `GpuSampler.qml` gains `gpuProcesses()` — calls `runningProcesses()`, dedupes via `dedupeByPid`, resolves pid→name from `/proc/<pid>/stat` via `ProcParser.parsePidStat`, returns `[{pid, name, vramBytes}]`. Gated on the detail-sampling flag (NVIDIA only). Both `MetricsBackend` adapters forward `gpuProcesses()`; Plasma adapter returns `[]` (ksysguard exposes no GPU process data). No view wired yet (PR4).

- feat(backend): add the GPU detail backend on both platform adapters (issue #71, PR2 of the sequence). Lands the cross-platform `gpuDetail()` surface (`{model, usagePercent, vramUsedBytes, vramTotalBytes, tempC, powerW, clockMhz}`, every field absent-able) + a `gpuDetailSamplingActive` gate so the extra sensors poll only while the tooltip is armed. **Standalone:** the C++ `NvmlReader::sample(bool detailed)` now also returns model / VRAM / power (mW→W) / SM-clock via four self-declared, **non-fatal** NVML entry points (an older driver missing one just omits that field); the whole GPU concern (NVML + AMD/Intel sysfs, retry gate, liveness flags) moved verbatim out of the at-cap `MetricsBackend.qml` into a new `GpuSampler.qml` child (500→428 lines), which adds the gated detail reads (AMD VRAM `mem_info_vram_{used,total}` bytes + `power1_input` µW→W via extended `GpuDiscovery.js`). **Plasma:** new tooltip-gated `GpuDetailSensors.qml` child subscribes `gpu/all/{used,total}Vram` + per-device `gpu/gpuN/{name,power,coreFrequency}` (units live-verified on an RTX 2070 — bytes/W/MHz, no conversion), picking the first-Ready device for the per-device fields (ksysguard exposes no `gpu/all/power`); `classifyDiscoveredIds` gains a `gpuDeviceIds` bucket. No view wired yet (PR4). Covered by extended `nvml-reader` / `gpu-discovery` / `metrics-catalog` / `standalone-metrics-backend` / `metrics-backend` guards; `GpuSampler.qml` registered in `CMakeLists.txt`.

- feat(core): add `GpuTooltipModel.js` — pure presentational logic for the GPU-ring hover tooltip (issue #71, PR1 of the sequence). Documents the shared `gpuDetail` contract (`model`, `usagePercent`, `vramUsedBytes`, `vramTotalBytes`, `tempC`, `powerW`, `clockMhz` — every field may be absent so the tooltip degrades per host) and exposes `formatVram` (IEC binary, mirrors `DiskTooltipModel.formatSize`), `formatPower`, `formatClock`, `formatPercent`, `composeVram`, `buildStatRows` (ordered rows, skips absent sensors), `rankProcesses` (by per-process VRAM, pid tiebreak) and `formatProcessVram`. No backend or view wired yet. Covered by `tests/gpu-tooltip-model.test.mjs` (43 cases); registered in `CMakeLists.txt` for the standalone build.

### Other

- docs(core): correct the X11/XWayland tooltip first-show flash diagnosis (#148). Live testing disproved the pointer-grab premise — the transparent-for-input flag is already set pre-map and `exposed` never oscillates; the real cause is a `Window`-popup map-then-resize (maps at pre-layout size, then grows to the laid-out content one frame later, which Wayland hides via atomic commit and X11/XWayland shows). The proposed C++ pre-map flag fix was implemented, tested, and disproven (input transparency can't fix a layout-timing resize). Closed wontfix; `core/CLAUDE.md` note updated.

## [0.14.1] — 2026-06-14

### Technical

- refactor(ui): mutualize the duplicated ring-tooltip placement chrome into a shared `TooltipBehavior.qml` helper (#149). The popup-type heuristic, show-delay `Timer`, grow-only width high-water mark, `samplingActive`/`_show`/`_displayed` state machine, and the Window-popup `anchorMarker` — previously copy-pasted across `ProcessTooltip.qml` and `DiskTooltip.qml` and guarded by the now-removed `tooltip-placement-sync.test.mjs` — now live once in a non-visual helper each tooltip instantiates (`TooltipBehavior { tip: tip }`, parenting its `QQC2.ToolTip` to `behavior.anchorMarker`). Each tooltip keeps its body as a DIRECT inline `ColumnLayout` `contentItem` (the Loader/default-property paths render a Window popup wrong — see `core/CLAUDE.md`), so the trap that forced the duplication is never reintroduced. New `tests/tooltip-behavior.test.mjs` (chrome in helper, body direct) + `tests/qml/tst_TooltipBehavior.qml`; helper registered in `CMakeLists.txt` for the standalone build.

- fix(ui): place the Plasma (in-scene) ring tooltips beside the ring, glued and on the side that fits (#149). Centralized the in-scene `x`/`y` into `TooltipBehavior.inSceneX`/`inSceneY` (the in-scene path is the Plasma full-screen-host case; the standalone Window popup is still placed via `anchorMarker`). Three defects fixed: (1) the SIDE is now chosen by whether the tooltip's own width actually fits on the right (`spaceRight >= w + gap`), so a wide tooltip never lands half-off-screen; (2) `mapToGlobal()` is not a reactive binding dependency, so the side decision was computed against the ring's STALE global position after the widget moved — a `_placeNonce` bumped on every hover-enter re-reads it; (3) the grow-only width high-water mark is now applied to the Window popup only — on the in-scene path the box equals its content, so a marked surplus no longer leaves empty space on the ring-facing side (the `Layout.maximumWidth`-capped name column) and detaches the text from the ring when placed left. Vertically a short tooltip centres on the ring; a tall one is floored at a small top inset and clamped to the current monitor.

- fix(ui): ring tooltips close instantly instead of fading (#149). A fading-out `QQC2.ToolTip` lingers one frame as an overlay with its content already emptied (rows → 0 on hover-leave) — both an empty-tooltip flash on dismiss AND, overlapping the neighbour ring, a hover thief that made the next ring's tooltip (notably Disks) open then immediately re-close. Set `exit: Transition {}` on both tooltips so dismissal is immediate.

- fix(ui): disk tooltip no longer stuck on "Gathering…" in aggregate mode on Plasma. When no partition is selected the disk ring shows the `disk/all` aggregate and the per-partition selection is empty, so the tooltip had no ids to enumerate and stayed blank forever. New pure helper `DiskMetrics.tooltipPartitionIds(selectedIds, mountedAvailable)` falls back to the live mounted filesystems behind the aggregate (`MetricsBackend.mountedAvailablePartitions`, Plasma-only) when the selection is empty; `MainContent` feeds the tooltip `_diskTooltipIds` / `_diskTooltipColors` instead of the ring selection directly. Standalone is unaffected (its default selection is never empty). Covered by new `tooltipPartitionIds` cases in `tests/disk-metrics.test.mjs`.

## [0.14.0] — 2026-06-14

### Added

- Hover the RAM ring to see the **top-20 processes by memory** — each row shows the process name, resident size (KiB/MiB/GiB), and its share of total RAM. A footer shows overall used/total memory. Works on both the Plasma widget and the standalone app (#70).

### Fixed

- Standalone app: the ring tooltips (CPU, RAM, disk) now open **beside the ring, top-aligned** — on the side that keeps them on screen — instead of below-left of it, and no longer flicker on Wayland (#150).

### Technical

- RAM ring tooltip: top-20 processes by memory (RES + %MEM) with used/total footer, on both platforms (#70).

- fix(ui): anchor standalone ring tooltips beside the ring instead of compositing at default position. Tooltips (CPU #69, RAM #70, disk #68) on the standalone widget now open adjacent to the ring with their top edge level with the ring top, anchored to the window's interior-facing corner (left-anchored window opens tooltips to the right, right-anchored to the left). Implemented by anchoring the Window-type popup to a 1×1 marker item positioned at the ring's interior corner — a Window popup ignores its own `x`/`y`, so compositor anchoring to the marker's rect achieves the positioning. Fixed a Wayland hover-flicker (QTBUG-38084) by marking the popup window transparent-to-input so the pointer grab doesn't steal hover from the ring. Known limitation: X11/XWayland shows a faint first-show flash (window flags can't be set pre-map from QML). `ProcessTooltip.qml` + `DiskTooltip.qml` both apply this pattern (duplicated chrome kept in sync).

- fix(config): stage the partition-color map like the label cache (#134) —
  `MetricsBody._refreshColorMap` now prunes into a non-cfg `_stagedColorsJson`
  (read by `partitionColor`) flushed by `_flushColorMap` from user-gesture
  setters only (`_flushStaged` covers both staged maps), and the prune is
  gated on `partitionsReady` + non-empty `diskPartitions` so the
  `Component.onCompleted` run (discovery still async/empty) can no longer
  drop a discovered-but-unreferenced partition's saved color or dirty the
  KCM on dialog open. SCENARIO guards in the new
  `tests/qml/tst_MetricsBodyColorMap.qml`.

## [0.13.0] — 2026-06-12

### Added

- Standalone: choose which monitor the widget lives on — new "Screen"
  selector in Settings → Appearance ("Current screen" by default, which
  follows the window). Fixes the widget being stuck on the leftmost /
  primary monitor on multi-screen setups, including under GNOME (#142).

### Other

- Add `CHANGELOG.md` to the docs-only exclusion in the bump heuristic
  (`bump-label` skill + `finish-branch` check 4h-bis): the mandatory
  per-PR CHANGELOG entry made every docs-only PR a false `patch`
  (caught on PR #143).
- Route the `finish-branch` skill's delegation through the `orchestrate`
  skill (routing matrix, prompt contract, escalation rule); per-step
  tier mapping documented in the skill. No pipeline behavior change.
- Fix a dangling code-comment reference in `ProcessTooltip.qml`
  (`_useWindowPopup` → `_applyPopupType`); no behavior change.

### Fixed

- Hover tooltips (top processes on the CPU ring, per-partition on the disk
  ring) now open **beside** the ring with their top edge level with the ring
  top, instead of dropping below it. On the standalone build under a native
  Wayland compositor the tooltip still auto-places (a separate-surface popup
  can't be positioned there); everywhere else it sits beside the ring.

### Technical

- feat(standalone): window-screen pinning (issue #142). The standalone widget
  can now be pinned to a specific monitor via a "Screen" ComboBox in Settings →
  Appearance; leave it at "Current screen" (default) to follow the window's
  position. The new `windowScreen` config key (string, default `""`) is unused
  on Plasma (plasmashell positions the widget in its panel). `WindowPlacement.js`
  gained `pickScreen(screens, name)` to match monitor names, and `computeX11Origin`
  now takes trailing `screenX, screenY` params (virtual-desktop offsets) so X11
  anchoring compensates for multi-monitor layouts; Wayland path calls
  `window.screen = resolvedScreen` then reconfigures, and both re-anchor on
  hot-plug and setting change.
- style(plasma): rename `ProcessSampler.qml`'s `_load1/_load5/_load15`
  sensor ids to `load1Sensor/load5Sensor/load15Sensor` — leading-underscore
  QML `id`s trip the qmlformat 6.11 empty-output regression (root
  `CLAUDE.md` rule), which false-failed the finish-branch 1b audit on any
  dev box with Qt ≥ 6.11. No behavior change; CI (Qt 6.6) was unaffected.
- fix(ui): top-align the hover tooltips with the ring instead of dropping
  them below. The CPU (#69) and disk (#68) tooltips now open beside the ring
  with their top edge level with the ring top (flip side / clamp up on screen
  overflow). The placement uses item-relative `x`/`y`, which only an in-scene
  popup honors — a `Window`-type popup ignores `x`/`y` on Qt 6.11 and
  auto-places. So `popupType` is now chosen per-show in `_applyPopupType()`:
  `Window` only when the host window is too small to contain the popup in-scene
  (the standalone window), in-scene otherwise (the full-screen Plasma desktop
  view). `ProcessTooltip.qml` + `DiskTooltip.qml` (duplicated chrome, kept in
  sync); rationale in `contents/ui/core/CLAUDE.md`.

## [0.12.2] — 2026-06-07

### Fixed

- **Autostart survives an AppImage upgrade even without relaunching**
  (standalone). The previous fix (#126) refreshed the login entry when the
  new version was launched — but upgrading, deleting the old file, and
  re-logging in without ever running the new build still booted to nothing.
  The login and menu entries now point at a stable copy of the AppImage
  (`~/.local/bin/ring-monitor.AppImage`), so login always starts the widget;
  the copy is refreshed the next time you run a newer AppImage (#136).

### Technical

- fix(standalone): point the `.desktop` `Exec=` at a stable AppImage copy
  (#136) — `desktop_entry::stableExecPath()` =
  `~/.local/bin/ring-monitor.AppImage`, maintained by `ensureStableCopy()`
  (AppImage-gated, size+mtime freshness, atomic sibling-temp +
  `rename(2)`). The #126 launch-time self-heal couldn't cover an upgrade
  followed by a re-login without launching the new file: the
  version-stamped path was gone and login started nothing. Now login
  always starts the copy (worst case the previous version, refreshed on
  the next manual launch — the single-instance takeover already handles
  the cross-version handoff). Copy created when a toggle is enabled or a
  pre-copy entry migrates at startup; removed when both toggles are off
  (`removeStableCopyIfOrphaned()`). Entry paths centralised as
  `desktop_entry::autostartFilePath()` / `menuFilePath()`. Review
  hardening: the copy runs on a detached worker thread (the >100 MB
  `QFile::copy` froze the first post-upgrade launch when inline in the
  QML ctors; detached so a copy stuck on a hung mount can't wedge quit —
  statvfs precedent), with an atomic in-flight guard; on completion the
  worker re-renders both entries (Exec= converges to the stable path
  without waiting for the next launch) and re-runs the orphan check. A
  chmod failure aborts the swap (a non-executable copy = silent EACCES
  at login); every failure path `qWarning`s; the `.desktop` templates
  moved to `desktop_entry` (`autostartFileContent()` /
  `menuFileContent()`) so the worker renders them off-thread.
- fix(config): stage the partition-label cache instead of writing it on
  discovery (#132) — `MetricsBody._refreshLabelCache` now merges into a
  non-cfg `_stagedLabelsJson` (read by `stalePartitionList`) and a new
  `_flushLabelCache` persists it to the cfg-bridged `partitionLabelsJson`
  only from user-gesture setters, so opening the Metrics page no longer
  dirties the KCM ("Apply settings?") when the saved cache misses entries
  for referenced partitions. SCENARIO guards in the new
  `tests/qml/tst_MetricsBodyLabelCache.qml` (split file: `tst_MetricsBody.qml`
  is at the 500-line cap).
- fix(config): add the missing KDE-484541 placeholders on the About page
  (`cfg_partitionOptOut`, `cfg_diskPartitionColors` + `Default` variants) —
  #58/#67 introduced the keys without extending configAbout.qml, so every
  config-dialog open logged a "Setting initial properties failed" line per
  missing key. New `tests/config-pages-placeholders.test.mjs` drift-catcher
  derives the expected `cfg_*` set from `main.xml` for all three config pages.
- docs: root `CLAUDE.md` gains the "never `git push` without an explicit user
  request" working rule (finish-branch step 7 now asks before phase B); the
  finish-branch 4f exclusion list swaps the stale `configGeneral` for
  `configAbout`, removing a false-positive WARN on config-page placeholders.
- refactor(config): the per-page 484541 placeholder blocks (~160 duplicated
  lines across the three config pages) collapse into a single
  `platforms/plasma/PlaceholderKCM.qml` base that every page extends,
  overriding only its bridged keys with `property alias`. Review findings on
  this PR also hardened the guard test (page list derived from `config.qml`,
  `\s+`-tolerant key extraction shared with the config-store tests, sanity
  floor raised to 30) and aligned the remaining finish-branch auto-push
  passages with the new explicit-go gate.

## [0.12.1] — 2026-06-03

### Fixed

- **Autostart no longer launches the old version after an AppImage update**
  (standalone). The "Start on login" entry used to embed the exact versioned
  AppImage filename, so once you downloaded a newer build, login kept starting
  the old one. The widget now refreshes that path (and the application-menu
  entry) on every launch, so the current binary is what runs at login (#126).

### Technical

- fix(standalone): self-heal the autostart / menu launcher `Exec=` path so an
  AppImage update no longer keeps starting the old version at login (#126). The
  autostart entry embedded the versioned AppImage filename
  (`Ring_Monitor-0.8.0-x86_64.AppImage`); after updating, login still ran the
  stale binary. The `Autostart` constructor now calls
  `desktop_entry::refreshIfStale` (parity with `MenuEntry`) — and because the
  `SettingsDialog` (which holds both helpers) is constructed eagerly by both
  standalone roots, this self-heal runs on every startup. `refreshIfStale` is
  gated on a new `desktop_entry::runningAsAppImage()` predicate (extracted from
  `currentExecPath`) so a fixed-path dev / source build never rewrites the
  user's installed-AppImage launcher to point at the throwaway binary. Tests
  added to `desktop-entry` and `autostart`.

- style(disk): the disk-ring tooltip usage line now separates the percentage
  from the size figures with a middle dot (`12% · 56 GiB / 466 GiB`) instead of
  an em dash, matching the `mountpoint · fstype` sub-line's separator. Single
  `composeUsage` glyph swap in `core/DiskTooltipModel.js`; tests + docs updated.

## [0.12.0] — 2026-06-02

### Added

- **Disk ring tooltip** — hover the disk ring(s) to see one line per shown disk:
  a removable/fixed drive icon tinted to that ring's colour, the volume label
  with its mountpoint and filesystem type, the usage % with used / total size
  (e.g. `12% — 56 GiB / 466 GiB`), and the free space. When several disks are
  shown (your selection plus auto-shown removables) the tooltip tells you which
  ring is which and the exact figures, without cluttering the gauge. Works on
  both the Plasma widget and the standalone build (#68).

### Technical

- feat(disk): pure presentational logic for the disk-ring hover tooltip
  (issue #68, PR 1/3) — `core/DiskTooltipModel.js` with IEC-binary
  `formatSize` (`df -h` style), usage/free line composition, and
  `buildRows()` mapping a per-partition detail object to the view's row
  model (label, mountpoint·fstype sub-line, `12% — 56 GiB / 466 GiB`,
  free space, removable-vs-fixed icon). Defines the `partitionDetail(id)`
  contract the backends will satisfy in PR 2. Node-tested; no behaviour
  change yet.
- feat(disk): `partitionDetail(id)` backend surface for the disk-ring tooltip
  (issue #68, PR 2/3) — both `MetricsBackend` adapters now return
  `{id, label, mountpoint, fstype, usedPercent, totalBytes, freeBytes,
  removable}` (same shape; assembled by the shared
  `DiskMetrics.buildPartitionDetail`, which owns the defaulting + the single
  `isRemovableMount` rule). `usedPercent` is the gauge's own value, never
  recomputed. **Plasma:** `findmnt` gains `FSTYPE` (→ `MountInfo` exposes
  `fstype`); the per-partition Sensor wiring moved into a new
  `platforms/plasma/DiskPartitionSensors.qml` adapter that grew each partition
  from one ksysguard leaf (`usedPercent`) to three (`+ total` / `free` bytes) —
  the split keeps `MetricsBackend` under the 500-line cap, which it now
  *forwards* `partitionValue` / `partitionDetail` to. **Standalone:** fstype is
  threaded through `DiskDiscovery.buildPartitions`; bytes ride the same
  off-GUI-thread `statvfs` cache as `partitionValue` (`freeBytes` = df Avail),
  with an O(1) `_partForId` lookup. No user-facing change yet — the view lands
  in PR 3. Covered by `disk-metrics`, `disk-partition-sensors` (new text guard),
  `mount-info`, `disk-discovery`, `metrics-backend`, `standalone-metrics-backend`.
- feat(disk): disk-ring tooltip UI + wire-in (issue #68, PR 3/3 — the
  feature-completing PR). New `core/DiskTooltip.qml` renders one row per shown
  disk from `DiskTooltipModel.buildRows` — a `Kirigami.Icon` tinted to the ring
  colour (`isMask`), the label + dimmed `mountpoint · fstype`, the usage line
  and free space. `MainContent` arms it on the disk ring and computes `details`
  (the `metrics.partitionDetail(id)` list) ONLY while hovered, so the per-tick
  statvfs (standalone) / total-free reads (Plasma) don't run when no tooltip is
  up. Plasma gates the per-partition `total`/`free` Sensor subscriptions on a
  new `diskTooltipActive` flag (the `ProcessSampler` pattern; `usedPercent`
  stays always-on). Live-verified: ksysguard `disk/<uuid>/total` +`/free` report
  bytes (236 / 115 GiB on the btrfs root, ratio matched `usedPercent`). The
  popup chrome (Window-popup guard, grow-only width high-water mark, edge-aware
  placement, show-delay) is DUPLICATED from `ProcessTooltip`, not shared: an
  earlier `core/HoverTooltip.qml` base injected the body via a `contentComponent`
  Loader, but a Window-type QQC2 popup renders WRONG with a Loader `contentItem`
  (in-scene/clipped, not a floating surface — caught live on Qt 6.10, both
  rings). The body must be the popup's DIRECT `contentItem`, so each tooltip
  owns its chrome; keep them in sync (documented in both files + `core/CLAUDE.md`).
  Covered by `tst_DiskTooltip`, `disk-tooltip-model`, the unchanged
  `tst_ProcessTooltip`.

### Other

- chore(skills): `refresh-plasma-widget` now **copies** the source into a
  dedicated `ring-monitor_dev` install (distinct plugin Id + name) instead of
  relying on a symlink — lets the dev build coexist with the KDE Store version
  and stops widget-uninstall from deleting the repo source via the followed
  symlink. Skill rewritten in English.
- ci(release): `version.yml` now **promotes the CHANGELOG automatically** on
  every bump — `## [Unreleased]` → `## [X.Y.Z] — DATE` with a fresh empty
  `[Unreleased]` above — committed alongside the `metadata.json` bump. This was
  a manual step that kept getting forgotten, so releases shipped with their
  notes stranded under `[Unreleased]` and the GitHub Release body (which
  `release.yml` extracts per-version) came out empty. Also backfills the
  `[0.11.0]` and `[0.10.0]` sections that were missed this way.

## [0.11.0] — 2026-06-02

### Added

- **Disk I/O ring** — a new ring showing live disk **read/write throughput**
  (MB/s), alongside the existing DISKS ring that shows how *full* the disk is.
  Enable "DISK IO" in Settings → Metrics. By default it shows combined read +
  write as one arc; tick **"Split read / write"** under the metric to see read
  on the left half and write on the right. The arc auto-scales to the disk's
  recent activity (so it stays expressive whether you're idle or copying a
  large file), and the centre shows the real rate with a unit that scales
  automatically from B/s to GB/s. In split mode the read and write readouts
  stack diagonally (read toward the left arc, write toward the right) so the
  longer labels don't crowd. Works on both the Plasma widget and the standalone
  build (#77).

### Fixed

- Enabling a metric that was introduced in a newer version (e.g. the new Disk
  I/O ring, or the CPU/GPU temperature rings on an older config) now shows its
  ring immediately — previously a metric absent from your saved ring order
  stayed hidden until you drag-reordered the list once (#77).

### Technical

- feat(disk-io): UI + config wiring that ships the disk-I/O ring (issue #77, PR4
  — the feature-completing PR). Registers `diskIo` in the catalog
  (`METRIC_IDS` + label + `isRateMetric`, parallel to `isTempMetric`) and the
  `splitDiskIo` config key across all six touch-points (main.xml, both
  ConfigStores, configMetrics alias, configAppearance 484541 placeholders,
  standalone SettingsDialog `_bridgeMap`). `MainContent`'s delegate special-cases
  the rate metric like the disk multi-partition ring: the arc uses the backend
  `io` snapshot's auto-scaled `*Percent` (combined, or read|write via split
  mode), and the centre label is `DiskIoScale.formatRate(*Bps)` passed through
  two new `Ring` props — `valueOverride` / `splitValueOverride` (a preformatted
  string the `Math.round(rawValue)+unit` path can't express for an MB/s rate).
  A content-scope `Binding` drives `diskIoSamplingActive` from whether the ring
  is enabled, so the backend only polls while it's on screen. The split toggle
  is a `MetricsBody` `extraContent` checkbox on the diskIo row. The diskIo
  centre label renders the "MB/s" unit smaller and tight against the number
  (no leading space) so the rate gets the room — via a new `Ring.unitSmall`
  flag + a `<font size="1">` span (Qt's StyledText **ignores** a CSS
  `font-size:` span — measured — but honours `<font size>`); `formatRate` was
  split into `formatRateValue` (number) + the unit so the two render
  separately. Only diskIo opts in; other rings keep their full-size unit. The
  unit is **dynamic** — `DiskIoScale.scaleRate` picks B/s / KB/s / MB/s / GB/s
  (SI 10³ steps) keeping the number in 0–999; the ring `unit` binds to
  `formatRateUnit(bps)`. In split mode the read/write readouts **stack
  diagonally** instead of side-by-side (`Ring.splitStacked` + the pure
  `RingGeometry.splitReadoutOffset` → each readout an `{x,y}` centre offset,
  read up-left / write down-right); the temperature split keeps the flat
  side-by-side layout. `MainContent`'s
  enabled-list derivation now `mergeWithCatalog`s `metricOrder` before
  `filterByOrder`, so an enabled catalog id missing from a stale persisted order
  (upgraders, or a host default predating the metric) still renders without a
  manual drag — a latent gap diskIo was the first opt-in metric to expose; the
  standalone `metricOrder` default also gains `diskIo` to mirror `main.xml`.
  Covered by
  `metrics-catalog` (id + `isRateMetric`), `tst_Ring` (the override props),
  `tst_MainContent` (the sampling gate), and `tst_MetricsBody` (catalog count).

- feat(disk-io): Plasma adapter wiring for the disk-I/O ring (issue #77, PR3 of
  the sequence; adapter layer only, no user-facing change yet). New
  `platforms/plasma/DiskIoSampler.qml` mirrors the standalone sampler's surface
  (`active` / `io`) from ksysguard's `disk/all/{read,write}` byte/s sensors —
  which report the rate directly, so unlike the standalone `/proc/diskstats`
  path there's no sample delta; each tick reads `.value`, coerces an unread
  sensor to 0, and scales it onto the arc via `DiskIoScale`'s rolling peak.
  Sensors are `enabled: active` so the daemon isn't subscribed while the ring is
  off-screen. `MetricsBackend` forwards the reactive `io` property + the
  `diskIoSamplingActive` gate and flags `diskIo` available (a no-op until the UI
  PR registers the catalog id). Extracting the sampler keeps the adapter under
  the 500-line cap (484), same as `ProcessSampler`. Text-guarded by
  `plasma-disk-io-sampler` + `metrics-backend`.

- feat(disk-io): standalone adapter wiring for the disk-I/O ring (issue #77,
  PR2 of the sequence; adapter layer only, no user-facing change yet). New
  gated `platforms/standalone/DiskIoSampler.qml` (own `ProcReader` + 500 ms
  `Timer`, mirroring `ProcessSampler`) reads `/proc/diskstats` only while
  active, aggregates whole disks via `DiskStatsParser`, and scales read/write
  byte/s onto the arc via `DiskIoScale`'s rolling peak. `MetricsBackend`
  forwards a reactive `io` property + the `diskIoSamplingActive` gate and flags
  `diskIo` available (a no-op until the UI PR registers the catalog id). The
  sampler skips a transient empty `/proc/diskstats` read rather than seeding a
  zero baseline (which would spike the next tick and pin the rolling peak), and
  derives its Timer interval from the rate denominator so the two can't drift.
  The sampler split keeps `MetricsBackend.qml` at the 500-line cap; a few long
  comments duplicated in `standalone/CLAUDE.md` were reduced to pointers to
  make room. Text-guarded by `standalone-disk-io-sampler` +
  `standalone-metrics-backend`.

- feat(disk-io): pure scaling + parsing logic for the upcoming disk-I/O
  throughput ring (issue #77, first of a multi-PR sequence; no wiring yet).
  `core/DiskIoScale.js` maps an unbounded byte/s rate onto the 0-100% arc via
  an auto-scaling rolling peak (decay + floor so a one-off burst doesn't pin
  the ceiling and idle noise doesn't saturate the ring), combines read+write,
  and formats MB/s for the label — shared by both backends, so it's written
  once. `platforms/standalone/DiskStatsParser.js` turns `/proc/diskstats`
  sector counters into byte/s deltas, aggregating WHOLE physical disks only
  (drops partitions + virtual/stacked devices to avoid double-counting). Both
  are pure, Node-tested (`disk-io-scale`, `disk-stats-parser`), and added to
  the standalone `QML_FILES` manifest.

### Other

- docs(standalone): correct the `MemInfoParser._clampPercent` comment — it
  wrongly suggested extracting a shared `Numeric.js` once a 3rd module needed the
  `[0,100]` clamp. That's not extractable here: QML `.import` of a `.js` needs
  `.pragma library`, and both are Node-`require` syntax errors, so a shared
  module couldn't be Node-tested and every consumer's test would break. The
  duplication is the accepted dual-load trade-off (like `ProcParser.sumJiffies`);
  comment now says don't re-attempt. No code change.

## [0.10.0] — 2026-06-02

### Added

- Standalone: a **"Show in application menu"** toggle in Settings → About.
  A downloaded AppImage normally appears in no application launcher, and on
  XFCE / Thunar a double-click does nothing; ticking the box registers a
  launcher entry (under `~/.local/share/applications/`) so Ring Monitor shows
  up in your menu — no root, no system-wide change, untick to remove. The
  *first* launch still needs the executable bit set (`chmod +x`, or
  Properties → Permissions in your file manager), since a browser download
  strips it (#101 / #102).

### Fixed

- Standalone AppImage no longer crashes at launch on a Wayland session
  (KWin Plasma 6 and other wlr-layer-shell compositors). A missing Qt
  graphics plugin left the window with no GPU surface, so the app aborted
  the moment it tried to draw; the plugin is now bundled. Affected every
  Wayland user of the AppImage regardless of GPU — workaround was launching
  with `QT_QPA_PLATFORM=xcb` (#110).

### Technical

- feat(standalone): add a "Show in application menu" toggle in Settings →
  About (issues #101/#102). A downloaded AppImage shows up in no launcher,
  and on XFCE/Thunar a double-click does nothing (no default handler for
  `application/vnd.appimage`); the toggle writes/removes
  `~/.local/share/applications/dev.manuacl.ringmonitor.desktop` pointing
  `Exec=` at the AppImage — no root, no system-wide MIME default. New
  `MenuEntry` QML_ELEMENT (`standalone/menu_entry.{h,cpp}`) mirrors
  `Autostart`; the shared `Exec=` resolution (AppImage path + XDG quoting +
  the `env QT_QPA_PLATFORM=xcb` prefix) is extracted to
  `standalone/desktop_entry.{h,cpp}` so the two writers can't drift.
  `AboutBody` gates the row on `menuEntryAvailable` (standalone-only; Plasma
  gets a menu entry from the `.plasmoid` install). `desktop_entry` also owns
  the shared write plumbing: an atomic `QSaveFile` write (no truncated
  launcher on a crash mid-write), a `removeDesktopFile`, and a
  `refreshIfStale` self-heal that `MenuEntry`'s constructor calls so a moved /
  re-downloaded AppImage's launcher is rewritten to the current path instead
  of silently pointing at a dead one. Both writers' `setEnabled` emit
  `enabledChanged` even on a failed write, and both the menu-entry and
  autostart checkboxes drive `checked` through a `Binding` element, so a write
  failure un-ticks the box rather than leaving it claiming an entry exists. The
  menu `.desktop` carries
  `StartupWMClass=ring-monitor-standalone` for taskbar grouping. Bootstrap
  limit: the *first* launch still needs the executable bit (`chmod +x`) — the
  binary can't set its own `+x` before it runs (#101), so the README
  documents the manual step. Guarded by `desktop-entry` / `menu-entry` /
  `standalone-settings-dialog` Node tests + `tst_AboutBody.qml`.

- fix(standalone): bundle the `wayland-egl` client-buffer integration plugin
  in the AppImage so it no longer SIGABRTs at launch on a native KWin-Wayland
  session (#110). linuxdeploy-plugin-qt ships the wayland *platform* plugins
  but not `plugins/wayland-graphics-integration-client/`
  (`libqt-plugin-wayland-egl.so`); without it Qt enumerates zero client-buffer
  integrations and `QRhiGles2` can't create a GL context. `build-appimage.sh`
  now copies the dir into the AppDir, and `verify-wayland-bundling.sh` asserts
  the plugin is present so the gate stops being blind to it. Offscreen CI and
  `QT_QPA_PLATFORM=xcb` never exercised this path, which is why it shipped.

### Other

- docs(repo-stats): teach the `repo-stats` skill to pull KDE Store download
  counts (OCS `loadFiles` per-file totals incl. archived versions) — the
  Plasma widget's main install channel, which GitHub release-download numbers
  can't see. Maintainer tooling only; no change to the shipped widget.

- ci(release): fix the standalone AppImage release job — Qt 6.8 needs the
  `linux_gcc_64` aqt arch (renamed from `gcc_64` at Qt 6.7), so the v0.9.0
  release built the `.plasmoid` but failed to attach the AppImage; also make the
  `Create GitHub Release` step idempotent so the `workflow_dispatch` retry path
  can re-attach to an existing release.

## [0.9.0] — 2026-06-01

### Added

- Standalone: choose which screen corner the window anchors to — top-left,
  top-right, bottom-left or bottom-right — with independent horizontal and
  vertical margins, under Settings → Appearance. The window can now sit in
  any corner instead of only top-right, and the placement persists across
  launches (#98).
- **CPU ring tooltip — top processes.** Hover the CPU ring to see what's
  using the most CPU right now: up to the 20 heaviest processes, each with
  its CPU% and PID, plus a load-average footer. CPU% is the share of the
  whole machine (so the rows sum toward the ring's value). Works on both
  the Plasma widget and the standalone build. Process data is sampled
  **only while the tooltip is shown** — nothing runs in the background.

### Changed

- Standalone: the single "Screen margin" setting is replaced by an anchor
  corner plus horizontal/vertical margins. An existing custom margin is not
  migrated — re-set the position with the new controls after updating.

### Fixed

- Standalone: picking a custom text colour (light or dark) now takes effect —
  the colour swatch and the ring text update on confirm. Previously the
  selection was silently dropped and the swatch never changed.
- Standalone: launching the app while the same build is already running no
  longer stacks a second widget on the desktop — the extra launch is ignored.
  Launching a **different** build (e.g. opening a newer AppImage) replaces the
  running one, so the version you open is the version you see. If you launch
  with `--open-settings`, the already-running widget opens its own settings
  dialog, so the change applies immediately instead of needing a restart
  (#103, #104).
- Standalone: NVIDIA GPUs on the open-source `nouveau` driver (or any host
  without the proprietary driver installed) now show a GPU **temperature** ring
  instead of "not detected". GPU usage stays unavailable on nouveau — the
  driver exposes no usage counter without root (#106).

### Technical

- fix(standalone): single-instance guard + wake-up IPC (#103, #104). A new
  `QLocalServer`-based helper (`standalone/single_instance.{h,cpp}`, linked via
  the added `Qt6::Network`) lets the first widget process own a per-user
  socket; a later launch connects as a `QLocalSocket`, announces
  `"<intent> <version>\n"` (one newline-terminated frame, so reading up to the
  `\n` can't truncate the version), and obeys the primary's **explicit** reply —
  never a timeout, so
  a busy/wedged primary is never hijacked. Verdict: `--open-settings` (any
  version), a same-version `show`, or any unknown/garbled intent reply `"defer"`
  → the newcomer exits with no window (no pile-up, #103; an unknown intent never
  quits the widget); a *different*-version `show` replies `"takeover"` then the
  running widget quits and closes its server synchronously, and the newcomer
  claims the socket and shows its own build — "the AppImage you open is the one
  that runs", equality only (any mismatch hands over). Claiming is race-safe:
  `tryListen()` listens first and only clears a socket it has *proven* stale
  (re-probe), so two simultaneous launches can't both become primary (the loser
  gets `Busy` and re-probes into the defer path). `main.cpp` runs this
  probe-then-act loop before loading any QML root and only claims on the main
  path (not `--open-settings`). The `openSettingsRequested` route opens the
  IN-PROCESS `SettingsDialog`, whose writes go through the same `ConfigStore` the
  rings read — fixing the #104 live-reload symptom without a `QFileSystemWatcher`
  (`Qt.labs.settings` has no reload API). The separate `SettingsOnlyRoot` process
  is now strictly the recovery fallback for when no widget is running. Exposed to
  QML as the `SingleInstance` context property (not a module-URI singleton, which
  would clobber the auto-registered `ProcReader`/`NvmlReader` C++ elements);
  guarded by `tests/single-instance.test.mjs` and a live
  `scripts/test-single-instance.sh` (raw-socket verdict probe + a `--full`
  two-version takeover round-trip) for the parts the headless env can't reach.
- fix(standalone): nouveau GPU-temperature fallback (#106). `GpuDiscovery.js`
  no longer hard-excludes NVIDIA: vendor `0x10de` resolves to a temp-only
  `nouveau` source (hwmon `temp1_input` via the existing `_drmHwmonTempPath`,
  `busyPath` null). It's a lower-priority fallback than AMD/Intel — a hybrid
  nouveau+AMD host still picks AMD (usage + temp). Only reached when NVML is
  unavailable (`MetricsBackend` gates on `!nvml.available`), so proprietary-
  driver hosts are unaffected; the vendor-agnostic backend already maps
  `tempPath`-without-`busyPath` to `_gpuTempAvailable` without `_gpuAvailable`.
  Extends `tests/gpu-discovery.test.mjs` (nouveau temp, no-hwmon → null,
  AMD-preferred-over-nouveau).
- fix(standalone): ColorPicker dropped the user's selection because the
  dialog's `selectedColor` was permanently bound to `color` (`selectedColor:
  root.color`); the live binding re-pinned the selection to the old colour, so
  `onAccepted` re-read it and `color` never changed (the swatch never
  updated). Seed `selectedColor` imperatively on open instead. Adds
  `tests/qml/tst_ColorPicker.qml` (the `selectedColor`-not-live-bound guard
  fails on the old binding) plus accept→model→swatch round-trip tests for both
  text-colour pickers in `tst_AppearanceBody.qml` (shared core wiring, so the
  same path is exercised for the Plasma host).
- feat(standalone): configurable window placement (#98). Replaced the single
  `windowMargin` key with `windowAnchorCorner` (top-left / top-right /
  bottom-left / bottom-right, default top-right) + `windowMarginX` /
  `windowMarginY`, so the standalone window can anchor to any screen corner
  with a per-axis inset instead of being pinned top-right. The corner →
  origin (X11) and corner → anchor-edges (Wayland layer-shell) math is a new
  pure module `platforms/standalone/WindowPlacement.js`
  (`tests/window-placement.test.mjs`), shared as the single source
  of truth by both host paths. `Main.qml._anchor()` reads it for
  `WindowAnchor.setGeometry`; `wayland_layer_shell.cpp` `configure()` now
  takes the chosen edges + X/Y margins and maps them to LayerShellQt anchors.
  `AppearanceBody` swaps the screen-margin slider for an anchor-corner combo +
  two margin sliders, gated by the renamed `windowPlacementVisible`. Defaults
  reproduce the pre-#98 top-right anchor byte-for-byte. **Breaking (config):**
  a custom `windowMargin` is not migrated — re-set it via the new sliders.
- `core/ProcessRanking.js` — shared, platform-agnostic ranking + formatting
  (sort desc, top-20 cap, deterministic pid tiebreak, `formatCpuPercent` /
  `formatLoadAverages`). Carries an optional `rssKb` field as a forward hook
  for the companion RAM-ring tooltip to reuse the same enumeration.
- Standalone source `platforms/standalone/ProcessSampler.qml` + `ProcParser.js`:
  enumerates `/proc`, deltas `utime+stime` over the system-wide jiffy delta
  (intrinsically total-normalised), reads `/proc/loadavg`. `proc_reader.cpp`
  now allows `listDir` on the bare `/proc` root (cleanPath stripped the
  trailing slash) to discover pid dirs.
- Plasma source `platforms/plasma/ProcessSampler.qml`: `org.kde.ksysguard.process`
  `ProcessDataModel` (`enabledAttributes: name/pid/usage`, raw `Value` role).
  ksysguard's `usage` is per-core, so it divides by `coreCount` to match the
  total-normalised semantics; load averages from `cpu/loadaverages/loadaverage{1,5,15}`.
- Both `MetricsBackend`s forward `processSamplingActive` / `topProcesses` /
  `loadAverages`; sampling is gated on the tooltip's hover so neither `/proc`
  enumeration nor `ProcessDataModel` polls in the background.
- `core/ProcessTooltip.qml` (hover-driven `QQC2.ToolTip`, sampling starts on
  enter, shown after a 500 ms delay) wired onto the CPU `Ring` in `MainContent`.
  Generic over the ranked metric — `title` / `formatValue` / `footerText` are
  injected by the parent, so the companion RAM-ring tooltip can reuse it as-is.
- Tests: `process-ranking`, `proc-parser`, `proc-reader` (/proc root guard),
  `standalone`/`plasma`-`process-sampler` guards, backend surface mirrors,
  `tst_ProcessTooltip.qml`.
- Review hardening: load-average sensors gated on `active` (no background
  ksysguard subscription); `rankByCpu` coerces `pid` to a number (robust
  tiebreak) and carries `rssKb` only when present (preserves the not-sampled
  signal).
- Tooltip placement (standalone live-test): the tooltip is a `Window`-type
  popup (an in-scene popup is clipped to the tiny standalone window),
  edge-aware (flips side when it would run off the screen — the standalone
  anchors top-right), with a content-driven width bound to the content's
  implicit size (a Window popup doesn't auto-adopt it; capped per name).
- Tooltip width is a grow-only high-water mark (`_maxContentWidth`, reset on
  dismiss when `_displayed` = `armed && _show` goes false): the ranked list
  re-samples every 500 ms, so a width bound straight to live content yoyo'd
  wider/narrower tick-to-tick. The mark blocks shrinking; the binding is
  `max(mark, live implicitWidth)` so the first frame still sizes to content
  instead of rendering a one-char sliver.
- `popupType` (Qt 6.8+) is now set imperatively + guarded
  (`Component.onCompleted: if (tip.popupType !== undefined) …`) instead of
  declaratively — a declarative assignment is a hard load error on the project's
  Qt 6.6 floor that took the whole widget down (it's in `core/`), which the
  AppImage smoke-test (Qt 6.6) caught. On < 6.8 the component now loads with the
  in-scene fallback; the shipped AppImage bundles Qt 6.8 (`release.yml`) so
  standalone keeps the Window popup, and `ci.yml`'s smoke-test stays on Qt 6.6 to
  guard the fallback-load path.
- plasma `ProcessSampler`: `onActiveChanged` no longer double-samples (the Timer's
  `triggeredOnStart` is the single first-sample path, matching standalone).

### Other

- docs/tooling: lift the "bump only at Plasma milestones; standalone work is
  always `bump:none`" gate now that platform-scoped release tags (#89) target
  the update notifications — a standalone release tags `-s` and notifies only
  standalone users, so it no longer dead-ends Plasma KDE-Store users. Reworded
  `docs/releasing.md` § Cadence and the `finish-branch` 4h-bis comments; the
  KDE-Store-sync note narrows to Plasma-facing releases (upload still manual).
- ci: drop `ci.yml` from the `packaging` paths-filter — the AppImage build's
  logic lives in `scripts/build-*.sh` (still filtered); `ci.yml` only
  orchestrates them, so a CI-config tweak no longer triggers a wasteful ~6-min
  AppImage rebuild (companion to the earlier `release.yml` drop).
- docs(plasma-isolation): mark the standalone build (issue #7) complete in
  `plan.md` — the "Live status" prose still claimed AMD/Intel GPU sysfs and C2
  were outstanding, but #82/#84 (GPU), #87 (AppImage) and #88 (native Wayland
  layer-shell) all shipped through v0.8.0; fills in the C2 PR number and drops
  the stale `Closes #7`-waits-on note.
- ci(stats): new `traffic-stats.yml` workflow archives a daily GitHub-traffic
  snapshot (views, clones, per-day CI-run counts, cumulative release downloads)
  to a `stats` orphan branch as CSV, preserving the series past GitHub's 14-day
  window; plus a `repo-stats` skill that reports it and separates human interest
  from CI-driven clone noise.
- ci(release): the GitHub Release body now leads with the version's
  user-facing CHANGELOG summary (the `## [X.Y.Z]` Added/Changed/Fixed block,
  under a `## What's new` heading) above the PR list, GitHub's auto-generated
  `## What's Changed` heading is relabelled `## Pull requests`, and the manual
  "KDE Store upload" helper block was dropped from the body.
- ci: drop `release.yml` from the `packaging` paths-filter — the CI AppImage
  build runs `scripts/build-*.sh`, never `release.yml`, so a release-body tweak
  no longer triggers a wasteful ~6-min AppImage rebuild.
- chore(finish-branch): new check (4h-bis) — a bump-labelled (tagged) PR must
  add a user-facing `### Added`/`### Changed`/`### Fixed` CHANGELOG summary, not
  just `### Technical` (FAIL for minor/major, WARN for patch), so a release
  can't ship with its changes stranded under `[Unreleased]` — the gap that
  forced the v0.8.0 re-cut.

## [0.8.0] — 2026-05-31

### Added

- **Each disk can now have its own ring colour.** In Settings → Metrics, every
  disk partition row gets a colour swatch — give a disk a dedicated ring colour,
  or clear it to fall back to the widget's shared colour. One colour per disk;
  disks you don't customise keep following your light/dark theme.

### Changed

- **Update notifications now match your build.** The "update available" badge no
  longer pings you about a release that only changes the other build (Plasma vs.
  standalone) — you only hear about updates that actually affect the version
  you're running.

### Technical

- (#67) Per-partition disk ring colors. Each selected filesystem can be given
  its own ring color from the disk row's partition picker (a color swatch per
  row); clearing it returns that ring to the widget's shared color. One fixed
  color per disk (no light/dark pair) — partitions without an override still
  track the live light/dark scheme through the shared fallback. State is a JSON
  `diskPartitionColors` map (partition UUID → `#rrggbb`, empty = none). The map
  helpers (`colorFor`/`withColor`/`withoutColor`/`resolveRingColors`) live in
  `core/DiskMetrics.js` beside the label cache, sharing its generic
  `parseUuidMap`/`serializeUuidMap` primitives (the dual-load convention forbids
  a `.js` importing a sibling `.js`, so a shared module isn't possible — same
  reason `parseCsv` is duplicated). `Ring` gains an `equalColors` array aligned
  to `equalValues` (entry falls back to `ringColor`); `MainContent` hoists the
  shared color into `_ringColor` and computes `_diskColors` for the disk
  delegate. The disk picker was extracted from `MetricsBody` into its own
  `core/DiskPartitionPicker.qml` (stateless view delegating to the body as
  `controller`) to keep `MetricsBody` under the 500-line cap. The color map is
  bounded to `enabled ∪ order ∪ discovered` via `DiskMetrics.pruneMap`
  (`MetricsBody._refreshColorMap`), mirroring the label cache, so a color can't
  outlive its partition. The picker swatch's "inherited" preview uses the
  **actual** resolved shared color (`MetricsBody.sharedRingColor`, injected by
  each config wrapper) rather than the bare theme highlight, so it matches the
  real ring when `colorTheme != system`. Config plumbing follows the
  six-touch-point pattern: `main.xml`, both `ConfigStore` adapters, the
  `configMetrics` cfg_* bridge (+ 484541 placeholder on `configAppearance`), and
  the standalone `SettingsDialog` `_bridgeMap`; the `ColorPicker` is injected
  into `MetricsBody` on both hosts. The per-row swatch's color is driven by a
  `Binding` element (not an imperative `item.color = Qt.binding` in `onLoaded`),
  so clearing an override reverts the swatch even after the `ColorPicker`'s
  on-accept `color = selectedColor` self-assignment would otherwise have
  clobbered the binding.
- (Part of #7) Native Wayland window path via KDE's **layer-shell-qt** (PR C2).
  On wlroots / KWin Wayland the standalone widget is now a `wlr-layer-shell`
  **bottom-layer** surface (anchored top-right, `KeyboardInteractivityOnDemand`,
  exclusive zone 0) instead of the XWayland fallback — so it no longer shows in
  Alt+Tab and no longer captures clicks over its area, the two warts the
  `NORMAL`+`BELOW` X11 window can't shed. `standalone/desktop_hints.cpp` gains
  `decideWindowStrategy()`, a single selector returning X11Ewmh / WaylandLayerShell
  / Floating from the session env; GNOME/mutter (no wlr-layer-shell) and the X11
  path are untouched. The layer role is opted into **per window** via
  `LayerShellQt::Window::get()` — deliberately NOT the global
  `LayerShellQt::Shell::useLayerShell()`, which would turn the context menu and
  settings dialog into fullscreen layer surfaces too. Two choices were settled by
  live testing: the `bottom` layer (not `background`, which is occluded by Plasma's
  desktop containment on a desktop click) and `OnDemand` keyboard interactivity
  (the context menu's `xdg_popup` needs the surface to take seat focus for its grab
  to install). layer-shell-qt is an **optional** build dep
  (`find_package(LayerShellQt QUIET)` → `HAVE_LAYER_SHELL_QT`): without it the
  build is byte-for-byte the pre-C2 X11/XWayland behaviour, and the new
  `WaylandLayerShell` QML singleton degrades to a no-op. The AppImage gets the
  path via `scripts/build-layer-shell-qt.sh` (compiles layer-shell-qt from source
  into the Qt prefix, like Kirigami) plus wayland-plugin bundling in
  `build-appimage.sh`; CI asserts the wayland plugins land in the AppDir. Because
  the layer-shell role is assigned at `wl_surface` creation, `Main.qml` keeps the
  root hidden (`visible: !WaylandLayerShell.active`) until `_anchor()` configures
  the surface, then shows it.

- (Part of #7, #89) Platform-scoped update notifications. The Plasma widget and
  the standalone build share one version counter and one GitHub release stream,
  so the "update available" badge would otherwise ping a Plasma user for a
  standalone-only release and vice-versa. **Client:** `UpdateCheck.js` gains
  `releaseScope(tag)` (reads a `-p` / `-s` / no-suffix scope marker off the
  release tag — never `metadata.json`, so `parseSemver` is undisturbed) and
  `pickRelevantRelease(releases, platform)`; `shouldNotify` takes a `platform`
  and skips releases scoped to the other build. `UpdateChecker.qml` gains a
  `platform` property (wired `"plasma"` / `"standalone"` by each adapter) and
  queries the `/releases` **list** (`per_page=100`) instead of `/releases/latest`
  — with a shared counter the highest tag may be scoped to the other platform,
  hiding an intermediate release the running build actually needs. The Plasma
  config-sidebar "New release" gate (`config.qml`) is scope-filtered in lockstep
  with the badge. **Pipeline:** `version.yml` infers the release scope from the
  cumulative diff since the last tag (`scripts/infer-release-scope.sh`) and
  suffixes the git tag (`v0.8.0-p` / `-s` / none); `release.yml` strips the
  suffix back off so the `.plasmoid`, the title, and the KDE Store version stay
  clean `X.Y.Z`. Safety bias: a release is suffixed only when confident it is
  single-platform (anything touching shared `core/`, both platforms, or only
  neutral files stays unsuffixed → notifies both), since a wrong suffix would
  hide a real update while an extra notification is harmless.

- (Part of #7) AppImage packaging pipeline for the standalone build. CMake
  `install()` rules stage an AppDir (binary + `.desktop` + ring-themed SVG icon,
  both committed under `packaging/` so they never leak into the Plasma
  `.plasmoid`), and `scripts/build-appimage.sh` drives `linuxdeploy` +
  `linuxdeploy-plugin-qt` to emit `Ring_Monitor-<version>-x86_64.AppImage`. CI
  builds and offscreen-smoke-tests it on ubuntu-22.04 (glibc 2.35, for broad
  distro compatibility) with Qt 6.5 from aqtinstall; `release.yml` builds it via
  the same script, smoke-tests it, and attaches it to the same GitHub Release as
  the `.plasmoid`. Because `core/` imports `org.kde.kirigami` (which
  `linuxdeploy-plugin-qt` does not ship and neither aqt nor apt provides for
  Qt 6), `scripts/build-kirigami6.sh` compiles Kirigami 6 + ECM from source into
  the Qt prefix so it gets bundled. `main.cpp` now calls `setDesktopFileName` so
  Wayland compositors map the window to the installed desktop entry. The
  standalone build is now installable without a toolchain. Also corrects the
  stated Qt minimum to **6.6** (CMakeLists + README): the rings use
  `Shape.CurveRenderer`, added in Qt 6.6 — the old "6.5" claim was a latent
  inaccuracy the AppImage build (pinned to a clean Qt) surfaced.

- (Part of #7) Fix the standalone AMD/Intel GPU sysfs retry gate closing too
  early (#83): the two-path gate used `&&`, so it stopped retrying the moment
  *either* `gpu_busy_percent` or the hwmon temp file resolved — stranding the
  other path for the whole session. On an AMD host where `gpu_busy_percent`
  exists at boot but the `amdgpu` hwmon driver settles a few seconds later, the
  temperature ring never appeared. Changed to `||` so discovery keeps retrying
  while *either* path is still empty, stopping only once both resolve (or the
  30 s window closes).

- (Part of #7) Three correctness fixes to the AMD/Intel GPU sysfs path (found
  by code review of the initial implementation): (1) AMD/Intel sysfs reads now
  run ONLY when `nvml.available` is false — on a hybrid NVIDIA+AMD host a
  transient NVML failure no longer latches AMD paths and shadows NVML values
  for the rest of the session. (2) The retry gate switches from `!_gpuVendor`
  to `!_gpuBusyPath && !_gpuTempPath` (mirrors the `!_cpuTempPath` CPU-temp
  pattern), so a DRM card found without a hwmon entry (late-loading Intel i915
  driver) is re-walked until a real path lands within the 30 s window. (3)
  `_gpuAvailable`/`_gpuTempAvailable` now derive from this-tick read success
  (liveness model matching NVML's `available` flag), not from path non-emptiness
  — an AMD eGPU hot-unplug causes the ring to disappear within one tick instead
  of freezing at the last-good value.

- (Part of #7) Standalone backend gains AMD and Intel GPU support via sysfs.
  New `GpuDiscovery.js` module (pure JS, Node-tested, injected I/O like
  `CpuTempDiscovery.js`) walks `/sys/class/drm/card*` to detect the vendor and
  resolve the per-tick sysfs paths: `device/gpu_busy_percent` for AMD utilisation
  (kernel 4.19+) and `device/hwmon/hwmonN/temp1_input` for the junction/die
  temperature of AMD and Intel cards. Intel GPU utilisation is deferred (i915-perf
  requires elevated perms). NVIDIA is unchanged (NvmlReader / NVML path). The
  `availableMetrics` gating splits into `_gpuAvailable` (usage source — NVML or
  AMD busy path) and `_gpuTempAvailable` (temperature source — NVML, AMD, or Intel
  hwmon), so an Intel-only host shows a GPU temperature ring without a spurious
  usage ring. Discovery runs once on the first non-NVIDIA tick with the same
  bounded-retry pattern as CPU temp (~30s window for late-modprobed drivers).

- (#80) Standalone `DiskDiscovery.parseMounts` now filters the EFI System
  Partition — a FAT-family fstype (`vfat`/`msdos`/`fat`) on an EFI mountpoint
  (`/boot/efi`, `/efi`, or a no-xbootldr `/boot`) — so the standalone disk
  picker matches the Plasma/ksystemstats set, which omits the ESP (issue #66).
  Deliberately narrow: an ext4 `/boot` xbootldr and a FAT data disk mounted
  elsewhere both survive. Also de-branded the test fixtures + comments
  (`BAZZITE_MOUNTS`→`OSTREE_MOUNTS`, labels `bazzite`→`root`) per the new
  "distro-agnostic content" CLAUDE rule.

### Other

- Tooling: enforce the per-PR CHANGELOG policy — `finish-branch` check 4h now
  FAILs (was a WARN) if `CHANGELOG.md` is untouched, a CI `changelog` job
  mirrors it, and the skill's doc-consistency audit also flags `README.md`.

- Tooling: drop the nested-ternary check (3b) from the `finish-branch` skill —
  the `grep` heuristic false-positived on regex strings like `'a:b'` inside
  test files and had no CI mirror, so it was noise.

- Docs: (Part of #7) add a live progress tracker for the standalone build to
  `docs/plasma-isolation/plan.md` — the A–H sequence now shows merged-PR state,
  the top Status calls out that the MVP shipped in v0.6.0, and the 2 remaining
  stages (C2 native Wayland layer-shell, H AppImage packaging) are marked.

## [0.7.1] — 2026-05-29

### Added

- **Removable drives now auto-show a ring on the standalone build too.**
  Plug in a USB key or external disk and a ring appears within a couple
  of seconds — and disappears when you unplug it — exactly like the
  Plasma version (previously this was Plasma-only).

### Changed

- **The disk picker's checkbox now reflects whether the ring is shown.**
  A plugged removable's box is **ticked** (its ring is visible) instead
  of appearing unticked while the ring shows. Unticking it **hides** the
  ring (and remembers your choice, so it stays hidden until you tick it
  again); reticking brings it back. Fixed disks are unchanged. The
  behaviour is now identical on Plasma and standalone.

### Fixed

- **The "Ring size" slider no longer appears in the Plasma settings,
  where it did nothing.** On the Plasma desktop you size the widget by
  dragging its frame, which overrides the slider — so it only ever
  looked inert once the widget was placed. The slider stays in the
  standalone build, where the window auto-sizes to it and it works.
- **An unplugged disk no longer shows up as selectable in the Plasma
  disk picker.** A drive you'd removed used to still appear as a
  tickable filesystem in Settings (ksysguard keeps listing it for the
  rest of the session). It now drops out of the selectable list; if you
  had selected it, it appears as a greyed "no longer connected" row you
  can clean up, the same as any other disconnected disk.

### Technical

- New `partitionOptOut` config key (CSV of UUIDs) wired through all six
  config touch points + `MetricsBody.partitionOptOutCsv`; consumed by
  `DiskMetrics.resolveDiskRingIds` (the opt-out arg, previously hardcoded
  `[]`). The picker checkbox is `DiskMetrics.isPartitionShown` (new pure
  helper); `setPartitionEnabled` is dual — removable → opt-out list, fixed
  → manual selection. The standalone `MetricsBackend` exposes
  `removablePartitions` + `mountedPartitionIds` (derived from its existing
  `/proc/mounts` + `/dev/disk/by-uuid` discovery via the shared
  `DiskMetrics.isRemovableMount`), so `resolveDiskRingIds`'s auto-show path
  lights up there too (the `MainContent` guards already consumed them).
- `AppearanceBody` gains a `ringSizeVisible` gate (default `false`;
  the standalone `SettingsDialog` flips it on), mirroring
  `ringSpacingVisible` / `windowMarginVisible`. Unlike those two, the
  Plasma `ConfigStore` keeps `ringSize` **bound** rather than
  hardcoded — it's a legitimate frame-overridden implicit size, not an
  actively-wrong value to neutralise.
- The config picker's partition list is now gated on the live `findmnt`
  mount set via `MetricsBackend.mountedAvailablePartitions`
  (`DiskMetrics.filterToMounted(availablePartitions, mountedPartitionIds)`);
  `configMetrics.qml` turns `removableTrackingActive` on so the poll runs
  while the dialog is open. This corrects the prior assumption that a
  freshly-built `SensorTreeModel` omits an unplugged partition — the
  staleness is at the ksystemstats daemon level, so even a fresh backend
  lists it (#58).

## [0.7.0] — 2026-05-29

### Added

- **Removable drives now show a ring on their own.** Plug in a USB key
  or external disk and a ring appears within a couple of seconds — no
  need to open Settings and tick it. Unmount the drive, or just pull it
  out, and the ring goes away the same way. The fixed disks you picked
  by hand are left exactly as they are.
- **Metrics with no data source are hidden instead of showing an empty
  ring.** GPU rings no longer appear on machines without an NVIDIA card,
  swap is hidden when the system has none, and a temperature ring with
  no sensor is dropped — so you never get a dead ring stuck at 0%. In
  Settings, an unavailable metric is greyed out and tagged "not
  detected".
- **Disconnected disks can be cleaned up in Settings.** When a
  filesystem you'd selected is unplugged, it now shows in the disk
  picker as a greyed "no longer connected" row — keeping its last-known
  label — with a trash button to remove it for good, instead of
  lingering invisibly in the configuration.

### Fixed

- **A disk ring no longer lingers after its drive is unplugged.** It
  used to stay on screen frozen at its last reading; it now disappears
  with the drive.
- **Standalone build: a hung mount no longer freezes the widget.** Disk
  usage for a stuck mount (stale NFS/CIFS, a spun-down USB) is now read
  off the GUI thread, so that ring just holds its last value while every
  other ring keeps updating.

### Technical

- The rendered disk set is now `(manual selection) ∪ (mounted removable
  media)`, computed by a pure `resolveDiskRingIds` helper in
  `core/DiskMetrics.js` and gated on the live kernel mount table. The
  gate is what self-heals the stale ring (#58): the ksysguard sensor
  tree freezes on unmount (no signal, frozen value), so the rendered set
  is sourced from the mount table instead of trusted from the sensor.
- Mounts are probed with `findmnt` (kernel mount table — complete and
  freeze-free) rather than `lsblk`, whose block-device view misses
  btrfs-subvolume and network mounts and would drop a still-mounted
  disk. vfat UUIDs are lower-cased to match ksysguard's keys.
- The probe (`MountInfo`, via plasma5support's executable engine) only
  runs while the disk metric is enabled — no subprocess churn otherwise.
- Metric availability (#52): both `MetricsBackend` adapters expose
  `availableMetrics`; `MainContent` filters the enabled list through the
  pure `Catalog.filterByAvailable` once warm-up settles and before
  merged-temperature mode, and `MetricRow` gains an `available` axis that
  greys the picker row.
- Stale partitions (#49): a persisted `partitionLabels` JSON cache
  (UUID→label) lets a disconnected partition keep its name;
  `stalePartitionList` surfaces ids in `enabled ∪ order` not currently
  discovered, gated off during warm-up so the trash action can't race
  discovery.
- Standalone disk reads run on a detached worker thread (#48), deduped
  while in flight, so a blocking `statvfs` can't stall the GUI thread.
- Standalone parity for the auto-show feature is tracked under #7.

## [0.6.0] — 2026-05-28

### Added

- **The disk gauge can now show several rings — one per filesystem.**
  Instead of a single disk ring, you can render multiple
  equal-thickness concentric rings, one for each mounted filesystem
  you select. The number in the center shows their average usage.
  - Pick which partitions to show with **checkboxes in Settings**
    (under the disk metric), and **reorder them by drag-and-drop** —
    the one at the top becomes the outermost ring, the one at the
    bottom the innermost. Default order is alphabetical by volume
    label.
  - Each filesystem is labeled by its **volume label** (for example
    "bazzite"), the same in both the Plasma and standalone builds.
  - On Plasma, leaving the selection empty keeps the original single
    aggregate disk ring — the multi-ring view is opt-in.
- The metric label was renamed from **"DISK" to "DISKS"** to match the
  new multi-filesystem view.
- **The standalone build gained more metrics, catching up to the Plasma
  version.** It can now show **CPU temperature**, **GPU usage and
  temperature** (NVIDIA cards), and **swap usage** rings — on top of the
  CPU, RAM, and disk gauges it already had.
  - GPU readings come straight from the NVIDIA driver (no `nvidia-smi`
    process spawned each refresh); on non-NVIDIA machines the GPU rings
    simply stay empty.
  - Swap correctly reflects zram, which is the default on Bazzite.

### Fixed

- **Standalone disk usage is now correct on Bazzite and other
  rpm-ostree systems.** The standalone disk ring used to be stuck near
  100% because it measured the read-only system image instead of your
  real storage. It now defaults to the filesystem that holds your home
  directory and reports its actual usage.

## [0.5.3] — 2026-05-28

Consolidates the 0.5.1 → 0.5.3 work into one release. Two themes: a
brand-new **standalone Linux build**, and a **hardening + polish
pass** on both hosts.

### Added

- **Standalone build — run Ring Monitor without Plasma.** A native
  Linux binary renders the same rings as a Conky-style, always-on-the-
  wallpaper widget, with no Plasma shell required. Metrics come
  straight from `/proc` and `/sys`; settings live in the same dialog
  as the Plasma version.
  - CPU (aggregate + per-core), RAM, and disk gauges.
  - Right-click settings, a **start-on-login** toggle, window
    size / ring-spacing / screen-margin controls, and top-right
    screen-edge anchoring.
  - Always-on-bottom, sticky, and skip-taskbar/pager behaviour on
    X11 & XWayland.
  - An `--open-settings` recovery flag to reach the settings dialog
    if your compositor swallows the right-click on a desktop-type
    window.

### Fixed

- **Rings now fill the widget on the Plasma desktop.** The
  ring-spacing setting used to silently eat into the fixed widget
  frame (the rings shrank to make room for the gap); that space is
  reclaimed and the rings render edge-to-edge.
- **Disk usage matches `df`** (standalone): the filesystem's
  reserved blocks are excluded, so a freshly-formatted ext4 root no
  longer reports ~5% used.
- **Settings dialog placement** (standalone): the dialog opens
  centered on the monitor it's actually shown on (not always the
  primary) in multi-display setups, and keeps the spot you dragged
  it to across re-opens.
- **Correct version** in the About tab and `--version` — the
  standalone binary previously reported a stale number.
- More reliable window hinting on X11 / XWayland, with a clear log
  warning instead of a silently un-styled floating window when
  XWayland is missing.

## [0.5.0] — 2026-05-25

### Added

- **Update notification.** The widget now checks GitHub for a newer
  release once a day. When one is available, a small pulsing dot
  appears in the gap below the first ring. Clicking it opens the
  config dialog at a new **"New release"** page that shows the
  available version, installation methods, and a "Got it" button to
  dismiss the notification until the next version lands.
- **Release / About page** (visible at the bottom of the sidebar
  when no update is pending). Shows the current version, links to
  the KDE Store and the project page, and the
  **"Check for updates automatically"** opt-out toggle.
- Plasma's built-in About page is now populated with the project
  website, bug report URL, and copyright.

## [0.4.0] — 2026-05-25

### Added

- **CPU and GPU temperature metrics.** Two new metric IDs
  (`cpuTemp`, `gpuTemp`) — toggle them on from the Metrics config
  page like any other ring.
- **Merge mode.** A sub-option on each temperature metric ("Merge
  into the CPU/GPU ring") renders the temperature as the right half
  of the matching usage ring instead of as a separate gauge. The
  two halves grow bottom-up from the existing 90° gap and meet near
  the top, with a small symmetric gap so the rounded caps don't
  overlap.
- **Temperature unit.** A new "Temperature unit" choice on the
  Metrics page — `Follow system` (default, derived from the system
  locale's measurement setting), `Celsius`, or `Fahrenheit`. Applies
  to both the merged half-arc and the dedicated temperature rings.
- **Warming-up animation.** During the first second after the
  widget loads, every ring sweeps up to 100% and then animates
  smoothly down to the actual sensor readings, instead of starting
  flat at zero.
- The CPU cores ring layout now adapts to any core count (4, 8, 12,
  16+), keeping the visual envelope stable as the number of cores
  grows.

### Fixed

- GPU temperature and per-core CPU usage now work on any machine,
  not just the developer's reference hardware. Previous releases
  hard-coded `gpu/gpu1` and 6 CPU cores.

## [0.3.0] — 2026-05-25

### Added

- **Color theme picker** on the Appearance page. Seven choices:
  `System` (default), `Blue`, `Green`, `Orange`, `Violet`, `Red`,
  and `Custom` (with separate light and dark colors).
- **Mode override** (visible when a non-system theme is selected):
  `Follow system`, `Always light`, `Always dark` — useful on
  Plasma look-and-feel themes that don't broadcast scheme changes
  reliably.

### Fixed

- Live light/dark scheme detection now follows the system color
  scheme correctly even after the widget has been mounted (previously
  the panel's `Complementary` color set was sampled and never
  refreshed).

## [0.2.3] — 2026-05-24

### Fixed

- Ring arcs render smoothly again at small sizes (the curve
  renderer used to produce visible angular segments).

## [0.2.2] — 2026-05-24

### Fixed

- The ring label stays anchored to the visible ring's bottom even
  when the widget is stretched taller than wide.

## [0.2.1] — 2026-05-24

No user-visible changes.

## [0.2.0] — 2026-05-24

### Changed

- Ring labels moved to the bottom gap of each ring (instead of
  above), and the label font size was bumped for legibility.

## [0.1.0] — 2026-05-23

First public release. Plasma 6 widget rendering CPU, RAM, swap,
GPU, and disk usage as circular ring gauges with rounded caps.

[0.7.1]: https://github.com/manuacl/ring-monitor/releases/tag/v0.7.1
[0.7.0]: https://github.com/manuacl/ring-monitor/releases/tag/v0.7.0
[0.6.0]: https://github.com/manuacl/ring-monitor/releases/tag/v0.6.0
[0.5.3]: https://github.com/manuacl/ring-monitor/releases/tag/v0.5.3
[0.5.0]: https://github.com/manuacl/ring-monitor/releases/tag/v0.5.0
[0.4.0]: https://github.com/manuacl/ring-monitor/releases/tag/v0.4.0
[0.3.0]: https://github.com/manuacl/ring-monitor/releases/tag/v0.3.0
[0.2.3]: https://github.com/manuacl/ring-monitor/releases/tag/v0.2.3
[0.2.2]: https://github.com/manuacl/ring-monitor/releases/tag/v0.2.2
[0.2.1]: https://github.com/manuacl/ring-monitor/releases/tag/v0.2.1
[0.2.0]: https://github.com/manuacl/ring-monitor/releases/tag/v0.2.0
[0.1.0]: https://github.com/manuacl/ring-monitor/releases/tag/v0.1.0
