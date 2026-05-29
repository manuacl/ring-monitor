# Changelog

Each release leads with the **user-facing** changes (what changed for
someone running the widget), followed by a **Technical** section with the
implementation detail underneath. Entries before 0.7.0 are user-facing
only.

## [0.7.1] — 2026-05-29

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
