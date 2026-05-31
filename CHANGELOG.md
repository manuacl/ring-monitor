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

### Other

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
