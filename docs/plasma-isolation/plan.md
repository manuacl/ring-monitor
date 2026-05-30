# Plasma isolation refactor

## Status

**Phase 1 — Plasma-isolation refactor (PRs 1–6): ✅ complete.**
**Phase 2 — standalone build (issue #7, PRs A–H + C2): MVP shipped v0.6.0;
all roadmap stages now landed** — see the
[standalone progress tracker](#standalone-implementation-sequence) below.
Issue #7 itself stays open until AMD/Intel GPU sysfs support lands (the one
post-MVP item still outstanding); C2 was the last *window/build* stage.

| PR | Goal | State |
|---|---|---|
| 1 | Theme adapter (`platforms/plasma/Theme.qml` + `ThemedIcon.qml`) | merged (#8) |
| 2 | ConfigStore adapter (`platforms/plasma/ConfigStore.qml`) | merged (#10) |
| 3 | MetricsBackend extraction (`platforms/plasma/MetricsBackend.qml`) | merged (#11) |
| 4 | Body extraction (`MainContent`/`AppearanceBody`/`MetricsBody` + `cfg_*` bridges) | merged (#12) |
| 5 | FormLayout helper | **skipped** — `Kirigami.FormLayout` reads cleanly and Kirigami is usable outside Plasma on any Qt 6 desktop |
| 6 | File reorganization into `core/` + `finish-branch` invariant | merged (#15 file-reorg, #19 platforms namespace rename) |

Path notes from PR 6: the simpler variant was chosen — `core/`
holds the portable subset, `platforms/plasma/` holds the Plasma
adapters, and the three Plasma-host wrappers (`main.qml`,
`configMetrics.qml`, `configAppearance.qml`) stay flat under
`contents/ui/`. This avoids the unverified subdirectory-`source:`
discovery on `ConfigCategory`, without losing the seam invariant.

Naming follow-up: PR 6 originally landed the adapter directory as
`contents/ui/platform/`. It was renamed to `contents/ui/platforms/plasma/`
in a small follow-up refactor so a future standalone target lives as
a sibling `platforms/standalone/` instead of the asymmetric
`platform-standalone/` at the top level. The rest of this document
uses the post-rename paths.

The invariant enforced by `finish-branch` is **`core/` imports no
`org.kde.*` module except `org.kde.kirigami`** (allowlist, not
denylist — catches `org.kde.kquickcontrols`, `org.kde.plasma.*`,
`org.kde.kcmutils`, `org.kde.ksysguard.*`, and any future Plasma
module without needing the check to be updated). Kirigami is
intentionally allowed in `core/`: it's a KF6 framework that runs on
any Qt 6 desktop, and the standalone build can ship it as a runtime
dep. This is the same reasoning that led to skipping PR 5 (FormLayout
helper).

## Context

Follow-up to [issue #7](https://github.com/manuacl/ring-monitor/issues/7)
(standalone Qt/QML port for non-KDE desktops). Rather than dual-build
immediately, the strategy is to **refactor the current Plasma-only
codebase to isolate every Plasma touchpoint behind a swappable
adapter layer**, so a future standalone port reduces to "reimplement
the adapters".

This extends the existing [`CLAUDE.md` DIP rule](../../CLAUDE.md)
("leaves don't reach into globals") one level up: the **whole**
codebase only touches Plasma through a thin, well-named seam.

## Workflow contract

The refactor is delivered as **6 PRs**, developed strictly **one at
a time**. After each PR is opened, work stops and the user runs
manual tests before giving the explicit "go" to start the next PR.

Rationale: each PR must be validated in a real Plasma session before
the next one builds on it. Skipping ahead means a broken PR N
silently contaminates PR N+1's foundation.

## Verdict

Yes, the refactor is feasible. Mostly file moves + thin wrappers +
import rewrites. Each PR is non-destructive (adds indirection,
doesn't change behavior). The standalone port itself is **not**
delivered by this work — what's delivered is the seam that makes it
tractable.

## Plasma touchpoints inventory

| File | Plasma dependency | Replaceable how |
|---|---|---|
| `contents/config/config.qml` | `org.kde.plasma.configuration` (`ConfigModel`, `ConfigCategory`) | Plasma-specific tab registration; keep parallel versions per platform, don't unify. |
| `contents/ui/main.qml` (114 lines) | `PlasmoidItem` root, `Plasmoid.configuration.X` reads (5 sites), `PlasmaCore.Types.NoBackground`, `org.kde.ksysguard.sensors` (11 `Sensors.Sensor` instances) | Wrap pattern: `PlasmoidItem { MainContent {} }`. Body extracted to `MainContent.qml`. Sensors extracted to `MetricsBackend.qml` adapter. Config reads go through `ConfigStore` adapter. |
| `contents/ui/configAppearance.qml` (108 lines) | `KCM.SimpleKCM` root, `Kirigami.FormLayout`, `Kirigami.FormData.*`, `Kirigami.Units.gridUnit`, `i18n()` | Same wrap pattern. `AppearanceBody.qml` contains the form; Plasma file wraps it in `KCM.SimpleKCM`, standalone wraps in `Dialog`. |
| `contents/ui/configMetrics.qml` (142 lines) | `KCM.SimpleKCM` root, `Kirigami.Units.{smallSpacing,gridUnit}`, `i18n()`, the `cfg_*` magic property convention | Same wrap pattern + `cfg_*` properties move to the wrapper, body uses normal properties. |
| `contents/ui/Ring.qml` | 3× `Kirigami.Theme.{textColor,highlightColor}` | `Theme` adapter (Item, see "Hard case #1"). |
| `contents/ui/MetricRow.qml` | 3× `Kirigami.Units.{smallSpacing,gridUnit}` | Same adapter. |
| `contents/ui/DraggableList.qml` | 6× `Kirigami.{Units,Theme,Icon}` | Same adapter + tiny wrapper component `ThemedIcon.qml`. |
| `contents/ui/{MetricsCatalog,RingGeometry,ReorderLogic}.js` | None | Already pure. |

The real Plasma surface, once abstracted, comes down to four
adapters: **theme tokens**, **config storage**, **metrics backend**,
**shell roots**.

## Target structure (post-PR 6, actually landed)

```
contents/ui/
├── main.qml                       — PlasmoidItem host (3 adapters + Core.MainContent)
├── configMetrics.qml              — KCM.SimpleKCM wrapper (cfg_* aliases → Core.MetricsBody)
├── configAppearance.qml           — KCM.SimpleKCM wrapper (cfg_* aliases → Core.AppearanceBody)
├── core/                          — portable subset (no org.kde.* imports — enforced)
│   ├── MetricsCatalog.js
│   ├── RingGeometry.js
│   ├── ReorderLogic.js
│   ├── Ring.qml
│   ├── MetricRow.qml
│   ├── DraggableList.qml          (uses Platform.ThemedIcon via "../platforms/plasma")
│   ├── MainContent.qml            (body of the widget, no PlasmoidItem)
│   ├── AppearanceBody.qml
│   └── MetricsBody.qml
└── platforms/                     — host-specific adapter trees (one subdir per target)
    └── plasma/                    — Plasma adapters (single home of org.kde.* imports)
        ├── Theme.qml              (Item exposing textColor, highlightColor, backgroundColor, unit, smallSpacing, iconSize re-exported from Kirigami)
        ├── ConfigStore.qml        (Item — NOT singleton; see hard case #2)
        ├── MetricsBackend.qml     (Item with the 11 Sensors.Sensor instances)
        └── ThemedIcon.qml         (wraps Kirigami.Icon)
```

The 5-line `main.qml` shim variant from earlier drafts was dropped
in favour of keeping the top-level Plasma wrappers as-is. Reasons:
the `ConfigCategory.source:` subdirectory support wasn't worth
verifying for a single negligible win (each wrapper is ~40 lines and
makes the Plasma-specific intent visible at the top level), and
Plasma's hardcoded `contents/ui/main.qml` path already pins one
top-level file there.

A future standalone port would create `contents/ui/platforms/standalone/`
exposing the **same module surface** (same Item names, same property
shapes), backed by `/proc` reads, `Qt.labs.settings`, `Window`,
`Dialog`. `core/` stays shared verbatim.

## Hard cases — design decisions made up front

### 1. `Theme` adapter is an Item, not a singleton

A QML singleton can technically access `Kirigami.Theme.*`, but
properties on `Kirigami.Theme` depend on the `QQuickItem` they're
read from (the color depends on the item's color scheme — light /
dark, focus state, etc.). A free-floating singleton may read stale
or wrong values.

**Decision:** `Theme.qml` is an `Item` declared once in `Main.qml`,
exposed via `id: theme`. Children read `theme.textColor` via scope
chain. Compatible with how Kirigami values actually propagate.

### 2. `ConfigStore` is an Item, NOT a singleton

`Plasmoid` is a **context property** injected by the Plasma shell on
the QML root scope. Singletons live outside that scope, so
`Plasmoid.configuration.X` inside a singleton would resolve to
`undefined`.

**Decision:** `ConfigStore.qml` is an `Item` instantiated inside
`Main.qml` (where `Plasmoid` is visible via scope chain). Properties
look like `readonly property string orientation: Plasmoid.configuration.orientation`.
Children read `configStore.orientation`.

Standalone version reads from `Qt.labs.settings` via the same
property names.

### 3. `Kirigami.FormLayout` + `FormData`

Used in `configAppearance.qml` for label-on-left layout.
QtQuick.Controls has no direct equivalent.

**Decision:** `core/FormLayout.qml` based on `GridLayout` (~30
lines), replicating the label-on-left semantics. Lives in `core/`,
no Plasma dep, used by both platform variants.

Deferred to **PR 5** — only do this if `configAppearance.qml`
actually needs it after body extraction. If `RowLayout`-based forms
read cleanly enough, skip.

### 4. `i18n()` vs `qsTr()`

Plasma's `i18n()` and Qt's `qsTr()` both work in a Plasma session.
Translation extraction tools handle both.

**Decision:** use `qsTr()` everywhere. One-time replacement during
PR 4 (body extraction).

### 5. `metadata.json` requires `contents/ui/main.qml`

Plasma's `KPackageStructure: "Plasma/Applet"` discovers
`contents/ui/main.qml` by hardcoded convention.

**Decision:** keep `contents/ui/main.qml` as a 5-line shim:
`import "platforms/plasma" as P; P.Main {}`. Same trick for
`contents/config/config.qml`: the `source: "configMetrics.qml"`
paths inside `ConfigCategory` become
`source: "platforms/plasma/ConfigMetrics.qml"` (Plasma 6 supports
subdirectory sources — to be verified on a throwaway branch before
PR 6 lands).

### 6. The `cfg_*` magic in config pages

`property alias cfg_textOpacity: textSlider.value` binds Plasma's
config write to the slider's value. When `textSlider` moves into a
body component, the alias has to either follow it (across files —
QML doesn't allow this) or be rewritten as a two-way binding.

**Decision:** in the wrapper, `property real cfg_textOpacity:
appearanceBody.textOpacity` (read); the body emits
`textOpacityChanged(value)`, the wrapper has `onTextOpacityChanged:
cfg_textOpacity = value` (write). Two lines of bridge per setting.
**This is the riskiest mechanism** — see PR 4 below.

## Risk per PR

| PR | Goal | Risk | Manual test required |
|---|---|---|---|
| 1 | Theme adapter (3 leaves migrated) | **Near zero** — same color/unit values reforwarded. | Visual: widget pixel-identical. |
| 2 | ConfigStore Item (main.qml reads only — config pages untouched) | **Low** if implemented as Item, not singleton. | Toggle orientation in config → widget reflects it; change opacity → reflected. |
| 3 | MetricsBackend extraction (11 Sensors out of main.qml) | **Low** — sensor values are scalars, parent change is inert. | All rings show correct values; CPU cores light up; per-core ring works. |
| 4 | Body extraction (3 files: MainContent, AppearanceBody, MetricsBody) + `cfg_*` bridge | **Medium-high.** `cfg_*` magic + bridge is the touchy spot. Plasma's config save timing (KDE bug 484541) has bitten before. | Change every setting, restart plasmashell, verify all settings persisted. Verify "Reset to defaults" still works. Test reorder, CPU cores toggle, all 3 opacity sliders, orientation switch. |
| 5 | FormLayout helper (optional) | **Near zero** — pure layout. | Visual on config page. |
| 6 | File moves into `core/` + `platforms/plasma/`, update metadata.json path discovery, add finish-branch invariant | **Low** if shim verified on throwaway branch first. Touches imports across tests too. | Install widget fresh (`kpackagetool6 -i .`), test config dialog opens, test edit-mode shows widget in "Add Widgets". |

**The honest soft spot is PR 4.** Keep PR 4 as a draft for 2-3 days
of real use before merging.

## PR sequence

Each PR stops + waits for the user's explicit "go" before starting
the next.

### PR 1 — Theme adapter

Create `platforms/plasma/Theme.qml` Item. Instantiate in `main.qml` once.
Migrate `Ring.qml`, `MetricRow.qml`, `DraggableList.qml` to use
`theme.X`. Files stay in place (no `core/` move yet). ~150 lines
touched.

### PR 2 — ConfigStore adapter

Create `platforms/plasma/ConfigStore.qml` Item. Instantiate in `main.qml`.
Migrate 5 config reads in `main.qml`. Config pages untouched (still
use `cfg_*` magic). ~50 lines touched.

### PR 3 — MetricsBackend extraction

Move 11 `Sensors.Sensor` instances + `sensorMap` + `coreValues`
from `main.qml` to `platforms/plasma/MetricsBackend.qml`. `main.qml` becomes
~30 lines. ~80 lines touched.

### PR 4 — Body extraction (riskiest)

Pull `MainContent.qml`, `AppearanceBody.qml`, `MetricsBody.qml` out
of the three top-level QML files. Wrappers become 15-25 lines each,
holding `cfg_*` magic + bridge to body properties. Migrate `i18n()`
→ `qsTr()` as part of this PR. ~300 lines touched.

### PR 5 — FormLayout helper (optional)

Skip if PR 4 result already reads well.

### PR 6 — File reorganization + invariant

Move files into `core/` and `platforms/plasma/`. Update
`contents/config/config.qml` paths. Add `metadata.json` shim
verification on a throwaway branch first. Update `finish-branch`
skill: rewrite hardcoded path greps + add
`grep -r "import org.kde" contents/ui/core/` invariant check
(must return zero matches). Update tests'
`import "../contents/ui/..."` paths.

## Risks not specific to a single PR

- **DraggableList drag regression.** `CLAUDE.md` warns against
  `pragma ComponentBehavior: Bound` on delegate files +
  context-property propagation through `Loader`. Touching this file
  is risky — add extra QML test coverage
  (`tests/qml/tst_DraggableList.qml`) before any refactor.
- **`refresh-plasma-widget` skill** clears 3 qmlcaches. After each PR, run
  it before manual testing to avoid stale-symbol false positives.
- **finish-branch skill greps hardcoded paths** today
  (`grep -n "Plasmoid\.configuration" contents/ui/Ring.qml ...`).
  Throughout PRs 1-5 these still work (files stay in place). PR 6
  rewrites them to point at `core/`.

## Standalone target — backend choice

**Scope.** The standalone target is **Linux, all distributions** —
not Windows, not macOS. The architecture decisions below assume that
constraint.

### Window model (Conky-style desktop widget)

The standalone window is **frameless, transparent, always on the
wallpaper layer**, on all workspaces, no taskbar/pager entry. Input
model: **left-click captured but inert** (no action), **right-click
and hover captured** by the app (right-click → settings menu, hover
reserved for a future feature).

Per-compositor implementation:

| Compositor | Mechanism |
|---|---|
| **X11** (Xorg or XWayland-only sessions) | `_NET_WM_WINDOW_TYPE_NORMAL` + EWMH hints `sticky + below + skip_taskbar + skip_pager + undecorated` |
| **KWin-Wayland** (KDE Plasma) | `wlr-layer-shell-unstable-v1`, `layer: background`, anchor + margin |
| **sway / Hyprland / wlroots-Wayland** | Same as KWin (`wlr-layer-shell` is the wlroots-native protocol) |
| **mutter (GNOME-Wayland)** | **No native path.** Force XWayland (`QT_QPA_PLATFORM=xcb` injected by our binary) + Conky-style hints: `own_window_type=normal` equivalent + `sticky,below,skip_taskbar,skip_pager,undecorated`. Best-effort: known glitches (raise/hide on desktop click, Activities mode breaks ordering) — same trade-off Conky's users accept. |

The mutter case is a deliberate "imitate Conky" fallback because
GNOME has refused to implement `wlr-layer-shell`
([mutter#973](https://gitlab.gnome.org/GNOME/mutter/-/work_items/973))
and provides no equivalent xdg-shell extension for third-party
desktop widgets. The only "proper" GNOME path is a gjs/Clutter
shell extension, which is out of scope (it would require
reimplementing the entire QML rendering layer in JavaScript).

### Distribution format

**AppImage, single artifact**, hosted on GitHub Releases alongside
the existing Plasma `.plasmoid` build. Rationale:

- Works on every Linux distribution without per-distro packaging.
- Embeds Qt 6 + Kirigami 6 so the user has zero runtime
  dependencies to install — important because Kirigami isn't
  installed by default outside KDE distros.
- No sandbox, which keeps the direct `/proc`, `/sys/class/hwmon`,
  `/sys/class/drm` reads simple and lets us subprocess
  `nvidia-smi` without manifest gymnastics.
- The user downloads one file, `chmod +x`, runs. Updates are
  handled by the existing `UpdateChecker` (the GitHub Releases API
  already powers it).

Flatpak / native packages (RPM + DEB via OBS) are deferred — they
add packaging maintenance overhead for marginal gain over AppImage
as a v1 strategy. Revisit once the standalone build has real
adoption.

### MVP scope

The first standalone version ships **a single fixed window with
CPU, RAM, and disk** — no GPU, no temperatures, no swap.

Sources:
- CPU usage (total + per-core) via `/proc/stat` deltas
- RAM via `/proc/meminfo` (`MemTotal`, `MemAvailable`)
- Disk via `statvfs(3)` on the mount root

Goal: validate the end-to-end loop — window creation, layer-shell /
XWayland integration per compositor, Qt+QML lifecycle outside
Plasma, `/proc` sampling cadence, ring animation. Once that loop is
solid, GPU (sysfs + `nvidia-smi`), temperatures (hwmon), and swap
are added as follow-up PRs.

### Repository structure

Same repo, single source tree. The standalone adapter sits at
`contents/ui/platforms/standalone/` next to `platforms/plasma/`,
sharing all of `contents/ui/core/`. The release pipeline produces
two artifacts: the existing `.plasmoid` and the new AppImage.
Splitting the repo would defeat the "maximize shared code" rule
that drives the whole isolation refactor.

### Standalone implementation sequence

Eight PRs, delivered one at a time. Each one stops and waits for
manual validation before the next starts. The Plasma build must keep
working at every step.

**Live status (updated 2026-05-30):** the MVP (A–G) shipped in **v0.6.0**,
every post-MVP metric is done, the AppImage pipeline (H) landed, and
**C2 (native Wayland layer-shell) is done** — so all A–H + C2 window/build
stages are complete. Issue #7 stays open only for **AMD/Intel GPU sysfs**
support (the last post-MVP metric); per `feedback-part-of-7-on-standalone-prs`,
`Closes #7` waits for that.

| Stage | State |
|---|---|
| A — picking helper | ✅ #25 |
| B — build infrastructure | ✅ #26 |
| C — window integration (X11 / XWayland subset) | ✅ #27, #63 |
| D — CPU backend (`/proc/stat`) | ✅ #29 |
| E — RAM + disk backend | ✅ #30 |
| F — config store + Settings dialog | ✅ #31, #32 |
| G — right-click menu + lifecycle + autostart | ✅ #35 |
| post-MVP — GPU (NVML + sysfs) / CPU temp / swap / multi-partition disk | ✅ #43, #44, #46, #47, #50, #82, #84 |
| **C2 — native Wayland layer-shell** (split out of C) | ✅ #<PR> |
| H — release pipeline (AppImage) | ✅ #87 |

The detailed A–H breakdown below is the original plan (historical reference);
the C row there bundled the Wayland-native path that's now tracked as C2.

| # | Goal | What changes | Risk |
|---|---|---|---|
| **A** | Extract reusable picking helper | `core/SensorPicking.js` (new) with `pickFirstReadyValue(candidates)`. Replaces the two duplicated "first Ready sensor wins" blocks in `MetricsBackend.qml` (`_gpuUsageValue`, `_gpuTempValue`). Pure helper, fully testable in Node. **No standalone work yet — this is pre-work that benefits the Plasma build too.** | Near-zero. Refactor of existing logic, behaviour identical. |
| **B** | Standalone build infrastructure | `CMakeLists.txt` at repo root, `standalone/main.cpp` that loads `contents/ui/platforms/standalone/Main.qml` and creates a frameless transparent Window. AppImage build script (`linuxdeploy` + `linuxdeploy-plugin-qt`). Plasma `.plasmoid` build untouched. Binary opens an empty window — no metrics yet. | Low. Pure infrastructure, doesn't touch Plasma. |
| **C** | Window integration per compositor | Detect display server (X11 vs Wayland), under Wayland detect `wlr-layer-shell` (via `layer-shell-qt` if available, falls back to plain `xdg-toplevel`), set window flags per the table above. Force `QT_QPA_PLATFORM=xcb` under mutter (Conky-style fallback). Test on Plasma-X11, KWin-Wayland, sway, mutter. | Medium. The compositor matrix is where edge cases hide. |
| **D** | Standalone `MetricsBackend` — CPU only | `platforms/standalone/MetricsBackend.qml` exposing the same surface as the Plasma adapter. Backend = `Timer` polling `/proc/stat` at 1 Hz, computing deltas. Per-core values populated. Hook the existing `core/MainContent.qml` view stack to this backend. | Medium. First time `core/` is consumed by something other than Plasma. |
| **E** | Add RAM + disk to standalone backend | `/proc/meminfo` for RAM, `statvfs(3)` for disk. MVP is feature-complete at this point: CPU + cores + RAM + disk. Other metrics (gpu, swap, temp) return 0/null. | Low. Same pattern as PR D. |
| **F** | Standalone `ConfigStore` + Settings dialog | `platforms/standalone/ConfigStore.qml` backed by `Qt.labs.settings` (INI file at `~/.config/dev.manuacl.ringmonitor/config.ini`). Settings dialog = a normal `Dialog` wrapping `core/MetricsBody.qml` and `core/AppearanceBody.qml` (already in `core/`, so this is mostly wiring). | Low-medium. The bodies are reusable, the writer side needs careful symmetric naming. |
| **G** | Right-click menu + lifecycle | Right-click anywhere on the widget → context menu (Settings, About, Quit). System tray icon? Probably not for v1 (too DE-dependent). Autostart `.desktop` file optionally written by the app on first run. | Low. UI plumbing. |
| **H** | Release pipeline | GitHub Actions: on a release tag, build the AppImage and attach it to the release. Update `docs/releasing.md`. The existing `UpdateChecker` in `core/` already polls GitHub Releases so update notifications work out of the box. | Low. Mostly CI YAML. |

**Post-MVP** (separate PRs after H ships): GPU usage (DRM sysfs +
`nvidia-smi`), CPU temperature (hwmon `coretemp` / `k10temp`), GPU
temperature (hwmon attached to the DRM card, NVIDIA via
`nvidia-smi`), swap.

The deferred questions — **5. settings dialog opener UX** (tray icon
vs right-click vs CLI) — get answered concretely in PR F/G.



**Guiding principle: maximize what lives in `core/`.** Every line of
logic that ends up duplicated between `platforms/plasma/` and the
future `platforms/standalone/` is a line that has to be re-written,
re-tested, and re-fixed twice. When in doubt, push the pure part of
a Plasma-adapter file down into a `core/*.js` helper and let the
adapter stay a thin wiring layer over the platform API. The `core/`
import invariant (no `org.kde.*` except `org.kde.kirigami`) is the
mechanised floor of this rule; the rule itself goes further — even
inside what's allowed in `platforms/`, prefer to keep it small.

**Backend.** The standalone `MetricsBackend.qml` will **not** depend
on `libksysguard` / `org.kde.ksysguard.sensors`. It reads kernel and
driver surfaces directly:

| Metric | Source |
|---|---|
| CPU usage (total + per-core) | `/proc/stat` — sample `cpuN` lines, compute deltas between ticks |
| RAM / swap | `/proc/meminfo` (`MemTotal`, `MemAvailable`, `SwapTotal`, `SwapFree`) |
| CPU temperature | `/sys/class/hwmon/hwmon*/temp*_input` — pick the `coretemp` / `k10temp` package sensor by label |
| GPU usage / VRAM / temperature (AMD, Intel) | `/sys/class/drm/cardN/device/gpu_busy_percent`, `mem_info_vram_used/total`, hwmon attached to the DRM node |
| GPU usage / VRAM / temperature (NVIDIA) | subprocess `nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits` |
| Disk usage | `statvfs(3)` on the mount root |

**Rationale.** A Plasma widget user already has `ksystemstats`
running. A standalone user on GNOME / sway / Hyprland may not, and
pulling `libksysguard6` + half of kf6 as a dependency just to read
sensors is disproportionate. Reading `/proc` and `/sys` directly
keeps the standalone build's footprint to **Qt 6 + Kirigami 6** only
— which Kirigami already is.

**Cost.** The discovery code currently provided for free by
`SensorTreeModel` (per-core enumeration, GPU index probing, hwmon
label classification) has to be reimplemented. Estimate: 2-3 weeks
of focused work for the backend alone. Acceptable price for keeping
the standalone build dep-clean.

**Out of scope for now.** The work isn't scheduled yet — this
section records the *decision*, not a commitment. When the
standalone effort starts, the contract is: same `MetricsBackend.qml`
property surface as the Plasma adapter, swappable at the
`platforms/<host>/` seam, zero impact on `core/`.

## What this refactor does NOT solve

- **Shipping a standalone build.** Still requires writing
  `platforms/standalone/` from scratch — the work issue #7 proposes.
- **"Add Widgets" mode on non-KDE desktops.** Still impossible —
  KDE's applet enumeration is bound to
  `KPackageStructure: "Plasma/Applet"`.
- **Cross-platform metric semantics.** KSysGuard IDs
  (`cpu/cpu0/usage`) don't map 1:1 to `/proc/stat` fields. The
  standalone `MetricsBackend.qml` needs the translation layer
  described above (`/proc`, `/sys`, `nvidia-smi`).
