# `contents/ui/core/` — portable QML layer

Everything in this directory is the **portable** body of the widget:
the views, the gauges, the reorderable list, and the pure JS logic
modules. It targets any Qt 6 desktop, not Plasma in particular.

The platform-specific shell lives in `../platforms/plasma/` (and a
future `../platforms/standalone/`) — both expose the **same property
surface** so the same `core/` files render unchanged on either.

## Plasma isolation is the load-bearing invariant

**No `org.kde.*` imports except `org.kde.kirigami`.** Kirigami is a KF6
framework that runs on any Qt 6 desktop, so a standalone build can
ship it as a runtime dep. Anything else under `org.kde.*`
(`kquickcontrols`, `plasma.*`, `kcmutils`, `ksysguard.*`,
`kcoreaddons`, `kio`, …) is host-bound and must live behind an
adapter in `../platforms/plasma/`.

Pattern to extend the seam:
- Need a Plasma-only QML control inside a `core/` view? Wrap it first
  in a new `../platforms/plasma/X.qml` adapter exposing the property
  surface `core/` will consume. Examples:
  - `ThemedIcon.qml` wraps `Kirigami.Icon` (just for the import seam).
  - `ColorPicker.qml` wraps `org.kde.kquickcontrols.ColorButton`.
  - `ConfigStore.qml` wraps `Plasmoid.configuration` reads.
  - `MetricsBackend.qml` wraps `org.kde.ksysguard.sensors`.

Then have `core/` import `"../platforms/plasma" as Platform` and use
`Platform.X`. Enforced by `finish-branch` via
`grep -rE 'import org\.kde\.' contents/ui/core/` filtered on the
Kirigami allowlist.

Full rationale and the file-by-file inventory:
[`docs/plasma-isolation/plan.md`](../../../docs/plasma-isolation/plan.md).

## Logic in dedicated `.js` files, views thin

Pure logic lives in dual-loadable `.js` modules (QML + Node — no
`pragma library` so the Node-side `module.exports` shim at the bottom
works). QML files consume them via `import "X.js" as X` and act as
thin views.

**Placement follows usage, not just purity** (the dead-code rule):

- **Shared by both platforms → `core/`.** A module imported by a
  `core/*.qml` view (or by both backends) belongs here. Current:
  - `MetricsCatalog.js` — metric ids, labels, sensor mapping, helpers.
  - `ColorThemes.js` — theme registry + color resolution.
  - `ReorderLogic.js` — drag-and-drop array transforms.
  - `RingGeometry.js` — sweep / radius / nested-ring layout math.
  - `UpdateCheck.js` — update-check version compare + TTL.
- **Used by only one platform → that platform's `../platforms/<p>/`
  directory, beside its adapter.** Keeping platform-specific logic in
  `core/` ships it as dead weight to the other artifact (the `.plasmoid`
  zip, or the standalone CMake-compiled module). So:
  - `../platforms/standalone/{ProcStatParser,MemInfoParser,CpuTempDiscovery}.js`
    — only the standalone `MetricsBackend` reads `/proc` + sysfs.
  - `../platforms/plasma/SensorPicking.js` — only the Plasma
    `MetricsBackend` picks among KSysGuard sensor candidates.

Always tested regardless of directory: every `.js` (here or under
`platforms/`) has a matching `tests/<kebab-case>.test.mjs`. See
[`tests/CLAUDE.md`](../../../tests/CLAUDE.md) for the naming and
patterns.

**QML list properties are NOT JS Arrays.** A dual-loaded module that
takes a list QML obtains from the engine (`Qt.application.screens`,
a `list<T>` property) must guard with array-likeness
(`typeof x.length === "number"` + index access), never
`Array.isArray()` — the QML side passes a `QQmlListProperty` wrapper,
for which `Array.isArray()` is `false` and Array methods (`.map`…) are
not guaranteed. Node tests pass real Arrays, so an `Array.isArray`
guard passes every unit test and still returns the fallback on every
live QML call (live bug in #142's `pickScreen`: the screen pin
silently never applied). Add an array-like-object case to the
module's tests to pin the guard.

## Component-side gotchas

### `Ring.qml`: non-percent metrics decouple sweep input from display

`Ring.value` is always treated as 0-100 for the sweep angle math.
When the metric is a temperature (or any non-percent — future:
network rate, NVMe temp), the parent maps the raw reading to a
percent for `value` AND passes the raw value via `rawValue` (with the
matching `unit`, e.g. `"°C"`). The centre text reads
`Math.round(rawValue) + unit` when finite, falls back to
`value + unit` otherwise. Split mode applies the same dual-prop trick
via `splitValue` (0-100 for the sweep) and `splitRawValue` (raw for
the text). Don't cram a non-percent value into `value` directly —
the sweep math would be wrong.

### `Ring.qml`: `PathAngleArc.centerX` binds to the Shape's `width/2`

Give the `Shape` an `id` and reference it explicitly. The default
implicit binding through `parent` resolves to the wrong item in some
QML render scopes — the arc ends up drawn off-centre.

### `Text.StyledText` ignores a CSS `font-size:` span — use `<font size="N">`

To make part of a `Text` a different size (e.g. `Ring.unitSmall` shrinks
the disk-I/O "MB/s" suffix), `textFormat: Text.StyledText` **silently
ignores** `<span style="font-size:Npx">` — the markup parses but the size
is unchanged (verified: identical `paintedWidth`). Use the HTML
`<font size="N">` tag instead (relative 1–7, default 3; `1` is smallest).
It's coarse (no px control), so when you need an exact pixel size, render
the segment as a separate `Text` with its own `font.pixelSize`. Cost ~2
live iterations on #77 (the span no-op'd → no visible change). Canonical:
`Ring._composeReadout`.

### `DraggableList.qml`: forward row data via `parent.rowModel`, not the scope chain

Inside a `Loader` that hosts a user-provided `Component`, declare
`property var rowModel: model` on the Loader; the loaded root reads
`parent.rowModel`. QML's implicit context-property propagation
through `Loader` is flaky across Qt versions / KCM containers — the
"empty labels" regression was caused by relying on bare `model.X`.
Regression-tested by `DraggableListForwarding.test_*` in
`tests/qml/tst_DraggableList.qml`.

### `DraggableList.qml`: no `pragma ComponentBehavior: Bound` on a ListView delegate file

It silently breaks the drag — the implicit `model`/`index` and
`MouseArea.drag.target` don't coexist with `required property var
model`. Apply the pragma only to delegate-free files (`main.qml`,
`Ring.qml` are OK).

### `DraggableList.qml`: nested lists are drag-scoped via `dragKey` (auto-unique by default)

An unkeyed `DropArea` accepts events from **any** drag source (Qt docs),
so two unscoped `DraggableList`s would cross-fire: nest the disk-partition
picker inside the metrics list and dragging an inner row floats fine but
never reorders — the outer list's `DropArea`s swallow the drop, the inner
`_dropTarget` never updates, the row snaps back. `DraggableList.dragKey`
(applied to every row's `Drag.keys` + each `DropArea.keys`) **defaults to a
unique-per-instance value**, so nesting is safe with no action. Only set
`dragKey` explicitly to deliberately make two lists share one drop scope.

### Don't reuse a property name as an `id` when passing it down

Pattern that bites — typically inside a `Component` template like
`fullRepresentation: X { ... }`:

```qml
Platform.Theme { id: theme }
MainContent { theme: theme }   // ← RHS resolves to MainContent.theme,
                                //   which is undefined at binding time
```

The RHS `theme` resolves to the new component's own `theme` property
(undefined at binding time) instead of the outer id. Errors land in
the journal, not in the QML compiler. Fix: suffix the outer id
(`themeAdapter`, `configStoreAdapter`, …). Same trap applies to any
parent → child id reuse inside templates.

### Binding a Loader-injected child that also self-assigns → use a `Binding` element

When you bind a property on a `Loader`-injected / platform child that the
child may **self-assign**, drive it with a declarative
`Binding { target; property; value; when: loader.item }` — NOT an imperative
`item.prop = Qt.binding(...)` in `onLoaded`. The platform `ColorPicker` writes
`color = selectedColor` on accept, which **clobbers** an imperatively-installed
binding, so a later external change (a partition "clear" button, or any
programmatic source change) stops reaching the swatch. A `Binding` element
re-applies on every value change and survives the self-assign. Canonical use:
`PartitionRow.qml` + `AppearanceBody.qml`'s color swatches (the latter masked
the bug only because it had no external change). Regression-guarded by the
`SCENARIO_swatch_*` tests in `tst_DiskPartitionPicker.qml` / `tst_AppearanceBody.qml`.

### cfg-bridged properties: never written from a housekeeping path

Never write a property bridged to `cfg_*` (or to the standalone
settings bridge) from a discovery / housekeeping path — it dirties the
KCM ("Apply settings?") with no user action, even past an
unchanged-map guard, when the recompute *adds or removes* entries.
Stage the recomputed value in a non-`cfg` property; flush it into the
bridged property from user-gesture setters only (the page is
legitimately dirty there). Canonical:
`MetricsBody._stagedLabelsJson` / `_flushLabelCache` (issue #132) and
its color sibling `_stagedColorsJson` / `_flushColorMap` (issue #134);
`_flushStaged` is the single gesture-side flush point. Corollary: a
*prune* whose keep-set depends on async discovery must also gate on
the readiness flag (`partitionsReady`) — run it before discovery
settles and the keep-set lacks its discovered half, silently dropping
saved user input (#134's color-loss case).
Sanctioned exception: seeding an *empty* bridged property with a
computed default (`MetricsBody._seedDefaultIfEmpty` — empty means
"use the default" by design, so re-seeding while empty never
overwrites a user-chosen state).

### Reactive argless data: expose as a `property`, not a `function`

When a component publishes data a view binds to (a list, a snapshot) and
the getter takes **no argument**, expose it as a `readonly property`, not
a `function foo()`. A function call is **not a tracked dependency** in a
QML binding — `model: backend.foo()` evaluates once and never re-runs
when the underlying data changes, so the view silently freezes. A
property (even one forwarding a child's property) carries NOTIFY, so the
binding updates. Bit the #69 tooltip: `topProcesses()` as a function left
the list frozen; switching it to `readonly property var topProcesses`
fixed it. Argument-taking getters (`metricValue(id)`) stay functions —
the caller re-invokes them from a binding that already tracks the arg.

### One backend gate, several hover sources → content-scope bools + a single Binding

Never point two `when:`-gated `Binding`s at the same target property
(e.g. `metrics.processSamplingActive`): both delegates' Bindings stay
active simultaneously and the inactive one's `false` clobbers the
hovered one's `true`. Route each tooltip's hover into its own
content-scope bool (`_cpuTooltipHovered`, `_memTooltipHovered` — the
`when:` keeps exactly one delegate driving each), OR-ed by ONE Binding
onto the backend property. Canonical: `MainContent.qml` (#70). The GPU
tooltip (#71) adds its third source the same way.

### A QQC2 popup over the widget needs `popupType: Window` + a `width` bound to `implicitWidth`

A `QQC2.ToolTip` / `Popup` raised from a ring (the #69 process tooltip,
`ProcessTooltip.qml`) has two traps — both only bite on the **standalone**
host, whose window is sized to the rings (tiny); on Plasma the overlay is
large. Cost ~4 live iterations:

- **`popupType: QQC2.Popup.Window` only when the host window is too small to
  contain the popup in-scene — NOT unconditionally, and NOT declaratively.** Two
  forces pull opposite ways:
  - An in-scene (`Item`) popup — the pre-6.8 default — is clipped to the host
    window's rect, so over the tiny standalone window only a sliver shows. A
    `Window`-type popup is a separate surface that escapes the clip.
  - A `Window`-type popup **ignores the popup's own `x`/`y`** on Wayland
    (Qt 6.11, verified live). BUT placement is still controllable: the
    compositor anchors the popup to the **parent-item's bounding rect** via
    `xdg_positioner`. Empirical gravity: the popup's **top-right corner lands
    at the anchor rect's (left, bottom)** and grows left+down; the compositor
    flips the grow direction at the screen edge. Parenting `tip` to a 1×1
    `anchorMarker` `Item` positioned at the ring's interior-facing top corner
    therefore gives beside-the-ring, top-aligned placement on both hosts. An
    in-scene popup still honors item-relative `x`/`y` on the same marker —
    no change to the Plasma path.

  Side selection: `MainContent.windowAnchorCorner` (standalone; `""` on
  Plasma) maps to `_tooltipOpenRight`, forwarded as `openRight` to each
  tooltip. Left-anchored widget → `openRight: true` → marker at `x: root.width`
  (ring's right edge), popup grows right. Right-anchored → `openRight: false`
  → marker at `x: 0` (ring's left edge), popup grows left. Either way the
  tooltip grows into the screen, beside the ring, top-aligned.

  Decide per-show: Window only when the host clips (the standalone window,
  sized to the rings); in-scene otherwise (the full-screen Plasma desktop view,
  which doesn't clip). Heuristic in `root._applyPopupType()`, called from
  `onSamplingActiveChanged` on hover-enter (while hidden, so the type is
  stable before open):
  `hostTooSmall = !win || win.width < Screen.width*0.6 || win.height < Screen.height*0.6`.

  Still **guard** the assignment — `popupType` is **Qt 6.8+** and the floor is
  **Qt 6.6** (`CMakeLists.txt`); a *declarative* `popupType:` is a hard load error
  on < 6.8 ("Cannot assign to non-existent property") that takes the **whole
  widget** down (this file is `core/`, loaded by both hosts). `_applyPopupType()`
  early-returns when `tip.popupType === undefined` (< 6.8 → in-scene default, fine
  on Plasma's large overlay, clipped on the small standalone window). The shipped
  AppImage bundles Qt ≥ 6.8 (`release.yml`); `ci.yml`'s smoke-test stays pinned to
  6.6 to guard the fallback-load path. Don't "tidy" it to a declarative or
  unconditional assignment. Canonical: `ProcessTooltip.qml` / `DiskTooltip.qml`.
- **Bind `width` to the content's `implicitWidth` — don't rely on
  auto-sizing, and don't hardcode a fixed width.** A `Window`-type popup
  does **not** adopt its `contentItem`'s `implicitWidth` the way an
  in-scene popup does, so a Layout content (rows using `Layout.fillWidth`,
  which report a ~0 minimum) collapses to a sliver and names elide to
  "k…"; setting row `preferredWidth` doesn't lift it. Use `width:
  <content>.implicitWidth + leftPadding + rightPadding` — still
  content-driven (grows to the widest row), just bound explicitly because
  the popup won't. Cap one field (the name's `Layout.maximumWidth`) so an
  outlier can't stretch it.
- **If the content re-samples on a timer, make the width a grow-only
  high-water mark, reset on hide, bound as `max(mark, implicitWidth)`.** The
  process tooltip refreshes every 500 ms, so the widest row keeps changing —
  a bare `implicitWidth` bind makes the popup yoyo wider/narrower every
  sample. Track a grow-only `_maxContentWidth` (a narrower sample is ignored;
  reset to 0 on dismiss via `on_ShowChanged` so a one-off wide sample doesn't
  pin every later hover). Bind to `max(mark, implicitWidth)`, not the mark
  alone: the mark starts at 0 and the tracker only updates it on a *change*,
  so a bare-mark bind renders a one-char sliver on the first frame until the
  next layout tick. Canonical: `ProcessTooltip._maxContentWidth`.
- **Place it edge-aware** (in-scene / Plasma path): the `tip` item-relative
  `x`/`y` bind beside the ring (`x: root.width`, `y: 0` → top-aligned),
  flipping side (`-width`) / clamping up on screen overflow.
  `mapToGlobal()` + `Screen.virtualX/Y` + `Screen.width/height` (plain
  QtQuick, no Plasma dep) feed only the overflow *test*, not the returned
  coordinate. Window-popup placement is handled instead by the `anchorMarker`
  parent (see above). Canonical: `ProcessTooltip.qml`'s `x`/`y` bindings.
- **Flicker fix — mark the Window popup transparent-for-input.** A Window-type
  QQC2 popup takes an `xdg_popup` pointer grab on open and steals the pointer
  from the ring's `HoverHandler` → hover drops → popup hides → reopens →
  flicker (QTBUG-38084). The tooltip is non-interactive, so dropping input is
  safe. In the `contentItem`'s `onWindowChanged`, when the content's window
  differs from the host's window (i.e. the separate popup surface just
  appeared), set `Qt.WindowTransparentForInput` on it:
  `w.flags = w.flags | Qt.WindowTransparentForInput`. Also set
  `closePolicy: QQC2.Popup.NoAutoClose` (hover-driven only). Canonical:
  `ProcessTooltip.qml` `contentItem.onWindowChanged`.
- **Known limitation — X11/XWayland first-show flash.** The transparent-for-input
  flag is set post-creation in `onWindowChanged`. Wayland re-reads it cleanly
  (no flicker). X11/XWayland does NOT: window flags are fixed at creation, and
  no QML hook fires before Qt maps the popup, so a faint flash on first show
  remains. The 500 ms show-delay absorbs most of it. A full X11 fix requires
  setting the flag pre-map in the C++ platform layer (future work).
- **The body must be the popup's DIRECT `contentItem` — never a `Loader`.**
  Tempting to factor this chrome into a shared `HoverTooltip` base that takes
  the body as a `Component` and hosts it in a `Loader` `contentItem` (a
  default-property slot captures the base's own `HoverHandler`, so a Loader
  looks like the only seam). But a `Window`-type popup renders WRONG with a
  Loader `contentItem`: in-scene / clipped instead of a floating surface —
  caught live on Qt 6.10, on BOTH the CPU and disk tooltips, and identically on
  standalone. So `ProcessTooltip` and `DiskTooltip` each DUPLICATE the chrome
  (direct `ColumnLayout` `contentItem`) rather than share a base. Fix-twice
  debt, accepted: keep the two in sync. Don't re-attempt the extraction.

## Where the platform adapters live

For Plasma-specific concerns (KSysGuard, KConfig, plasmashell quirks,
config-dialog gotchas): [`../platforms/plasma/CLAUDE.md`](../platforms/plasma/CLAUDE.md).

Cross-cutting rules (English-only, 500-line cap, no nested ternaries,
SOLID grid, QML↔React stack reminder): root
[`/CLAUDE.md`](../../../CLAUDE.md).
