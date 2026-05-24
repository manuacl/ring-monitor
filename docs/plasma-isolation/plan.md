# Plasma isolation refactor

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

## Target structure (post-PR 6)

```
contents/ui/
├── main.qml                       (5-line shim: import "platform" as P; P.Main {})
├── core/                          (no org.kde.* imports — enforced by finish-branch)
│   ├── MetricsCatalog.js
│   ├── RingGeometry.js
│   ├── ReorderLogic.js
│   ├── Ring.qml                   (uses Theme adapter)
│   ├── MetricRow.qml
│   ├── DraggableList.qml          (uses ThemedIcon)
│   ├── MainContent.qml            (body of today's main.qml, no PlasmoidItem)
│   ├── AppearanceBody.qml
│   └── MetricsBody.qml
└── platform/                      (single home of org.kde.* imports)
    ├── qmldir
    ├── Theme.qml                  (Item exposing textColor, highlightColor, backgroundColor, unit, smallSpacing, iconSize re-exported from Kirigami)
    ├── ConfigStore.qml            (Item — NOT singleton; see hard case #2)
    ├── MetricsBackend.qml         (Item with the 11 Sensors.Sensor instances)
    ├── ThemedIcon.qml             (wraps Kirigami.Icon)
    ├── Main.qml                   (PlasmoidItem { MetricsBackend {}; ConfigStore {}; Theme {}; MainContent { ... } })
    ├── ConfigAppearance.qml       (KCM.SimpleKCM { AppearanceBody { ... } })
    └── ConfigMetrics.qml          (KCM.SimpleKCM { MetricsBody { ... } })
```

A future standalone port would create
`contents/ui/platform-standalone/` exposing the **same module
surface** (same Item names, same property shapes), backed by `/proc`
reads, `Qt.labs.settings`, `Window`, `Dialog`. `core/` stays shared.

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
`import "platform" as P; P.Main {}`. Same trick for
`contents/config/config.qml`: the `source: "configMetrics.qml"`
paths inside `ConfigCategory` become
`source: "platform/ConfigMetrics.qml"` (Plasma 6 supports
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
| 6 | File moves into `core/` + `platform/`, update metadata.json path discovery, add finish-branch invariant | **Low** if shim verified on throwaway branch first. Touches imports across tests too. | Install widget fresh (`kpackagetool6 -i .`), test config dialog opens, test edit-mode shows widget in "Add Widgets". |

**The honest soft spot is PR 4.** Keep PR 4 as a draft for 2-3 days
of real use before merging.

## PR sequence

Each PR stops + waits for the user's explicit "go" before starting
the next.

### PR 1 — Theme adapter

Create `platform/Theme.qml` Item. Instantiate in `main.qml` once.
Migrate `Ring.qml`, `MetricRow.qml`, `DraggableList.qml` to use
`theme.X`. Files stay in place (no `core/` move yet). ~150 lines
touched.

### PR 2 — ConfigStore adapter

Create `platform/ConfigStore.qml` Item. Instantiate in `main.qml`.
Migrate 5 config reads in `main.qml`. Config pages untouched (still
use `cfg_*` magic). ~50 lines touched.

### PR 3 — MetricsBackend extraction

Move 11 `Sensors.Sensor` instances + `sensorMap` + `coreValues`
from `main.qml` to `platform/MetricsBackend.qml`. `main.qml` becomes
~30 lines. ~80 lines touched.

### PR 4 — Body extraction (riskiest)

Pull `MainContent.qml`, `AppearanceBody.qml`, `MetricsBody.qml` out
of the three top-level QML files. Wrappers become 15-25 lines each,
holding `cfg_*` magic + bridge to body properties. Migrate `i18n()`
→ `qsTr()` as part of this PR. ~300 lines touched.

### PR 5 — FormLayout helper (optional)

Skip if PR 4 result already reads well.

### PR 6 — File reorganization + invariant

Move files into `core/` and `platform/`. Update
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
- **`refresh-widget` skill** clears 3 qmlcaches. After each PR, run
  it before manual testing to avoid stale-symbol false positives.
- **finish-branch skill greps hardcoded paths** today
  (`grep -n "Plasmoid\.configuration" contents/ui/Ring.qml ...`).
  Throughout PRs 1-5 these still work (files stay in place). PR 6
  rewrites them to point at `core/`.

## What this refactor does NOT solve

- **Shipping a standalone build.** Still requires writing
  `platform-standalone/` from scratch — the work issue #7 proposes.
- **"Add Widgets" mode on non-KDE desktops.** Still impossible —
  KDE's applet enumeration is bound to
  `KPackageStructure: "Plasma/Applet"`.
- **Cross-platform metric semantics.** KSysGuard IDs
  (`cpu/cpu0/usage`) don't map 1:1 to `/proc/stat` fields. Future
  `MetricsBackend-standalone` needs translation per-platform.
