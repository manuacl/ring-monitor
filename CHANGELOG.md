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
