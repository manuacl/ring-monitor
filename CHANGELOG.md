# Changelog

All notable user-facing changes to Ring Monitor. Internal refactors,
test additions, and tooling updates are intentionally omitted — the
git history covers those.

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

[0.5.0]: https://github.com/manuacl/ring-monitor/releases/tag/v0.5.0
[0.4.0]: https://github.com/manuacl/ring-monitor/releases/tag/v0.4.0
[0.3.0]: https://github.com/manuacl/ring-monitor/releases/tag/v0.3.0
[0.2.3]: https://github.com/manuacl/ring-monitor/releases/tag/v0.2.3
[0.2.2]: https://github.com/manuacl/ring-monitor/releases/tag/v0.2.2
[0.2.1]: https://github.com/manuacl/ring-monitor/releases/tag/v0.2.1
[0.2.0]: https://github.com/manuacl/ring-monitor/releases/tag/v0.2.0
[0.1.0]: https://github.com/manuacl/ring-monitor/releases/tag/v0.1.0
