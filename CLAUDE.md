# Ring Monitor

Plasma 6 widget for system monitoring with circular ring gauges.
Built from scratch as a learning project (user knows React, not QML — so
explanations should map back to React concepts when introducing new QML
ones).

Target: KDE Plasma 6 Wayland on Bazzite.

## Where to look

This file is the short briefing. Deeper docs live in `docs/`:

- [`docs/architecture.md`](docs/architecture.md) — file roles, layering rule,
  data flow
- [`docs/logic-modules.md`](docs/logic-modules.md) — pure JS modules
  (`ReorderLogic`, `MetricsCatalog`, `RingGeometry`)
- [`docs/components.md`](docs/components.md) — `Ring.qml`, `DraggableList.qml`
- [`docs/config-dialog.md`](docs/config-dialog.md) — Plasma config gotchas
  (KDE bug 484541, SimpleKCM, AnchorChanges)
- [`docs/adding-a-metric.md`](docs/adding-a-metric.md) — step-by-step
- [`docs/testing.md`](docs/testing.md) — `node --test tests/`, when to add tests
- [`docs/development.md`](docs/development.md) — symlink, plasmashell restart,
  `plasmawindowed`, journal greps, QML tooling
- [`docs/releasing.md`](docs/releasing.md) — release flow
  (`version.yml` + `release.yml`), `BUMP_TOKEN` PAT rotation, KDE Store
- [`docs/plasma-isolation/plan.md`](docs/plasma-isolation/plan.md) —
  active 6-PR refactor isolating Plasma deps behind adapter layer

## Working rules

These are forced by the user's preferences, not by the tech stack:

- **Plasma isolation is mandatory.** `contents/ui/core/` is portable
  QML — **no `org.kde.*` imports** except `org.kde.kirigami` (which
  runs on any Qt 6 desktop). Plasma-specific code lives only in
  `contents/ui/platforms/plasma/` adapters (`Theme`, `ConfigStore`,
  `MetricsBackend`, `ThemedIcon`, …) and the three top-level wrappers
  (`main.qml`, `configMetrics.qml`, `configAppearance.qml`). Need a
  Plasma-only QML control inside a `core/` view? Wrap it in a new
  `platforms/plasma/X.qml` adapter first (pattern: `ThemedIcon.qml`
  wraps `Kirigami.Icon`). The seam exists so a future standalone
  build is just a sibling `platforms/standalone/` directory exposing
  the same property surface; smuggling a Plasma
  dependency into `core/` silently undoes that work. Enforced by
  `finish-branch` via `grep -r "import org.kde" contents/ui/core/`.
  Full rationale and inventory in
  [`docs/plasma-isolation/plan.md`](docs/plasma-isolation/plan.md).
- **Logic in dedicated files, views thin.** Pure logic goes in
  `contents/ui/core/*.js` (dual-loadable by QML and Node). QML files
  consume them.
- **All logic must be tested.** New `.js` module ⇒ matching
  `tests/*.test.mjs`. Use `SCENARIO:` tests to encode reported bugs as
  regression guards.
- **No nested ternaries.** `a ? x : b ? y : c ? z : d` → use a lookup
  map, a `switch`, or extract a named function. Single ternaries are OK.
- **English-only repo.** All committed files — code, comments,
  `docs/*.md`, `CLAUDE.md`, `README.md`, commit messages, PR
  titles/bodies, and `.claude/skills/*/SKILL.md` — are written
  exclusively in English. i18n source strings stay English (translation
  is a downstream concern). The conversation with the user can be in
  any language; only what lands in the repo is constrained.
- **Qt docs before inventing.** For any QtQuick pattern (drag/drop,
  model/view, animations), start from
  [doc.qt.io](https://doc.qt.io/qt-6/) — especially the "Dynamic View
  Ordering" / "QML Cookbook" tutorials. No hand-rolled reimplementation
  while an official pattern exists. The drag-and-drop saga was a
  manual `mapToItem` + `_draggedY` reimplementation of what
  `MouseArea.drag.target` does natively.
- **Tests cover rendering too, not just logic.** `node --test` for the
  pure `.js` modules; `qmltestrunner-qt6` (via `tests/qml/`) for what
  depends on the QML runtime — assertions on `CheckBox.text`, `model`
  forwarding, signals. Pure Node tests didn't catch "empty labels"
  because the bug was in a QML binding.
- **500 lines max per source / test file.** Enforced by both the
  pre-commit hook and CI (`.github/workflows/ci.yml`'s `file-size`
  job) over `contents/ui/**/*.{qml,js}` and `tests/{*.test.mjs,qml/*.qml}`.
  When a file outgrows it: split — extract pure logic to a `.js`
  module, or pull a sub-component into its own `.qml` file (e.g. the
  `MetricRow` extraction from `configMetrics.qml`). Don't raise the
  cap. Docs (`docs/*.md`, `CLAUDE.md`) are intentionally not capped.

## Design principles (SOLID, QML-adapted)

QML has no nominal inheritance, so the SOLID grid rewrites slightly. The
shorthand: **stateless components, data via props, events via signals,
parents wire them together.**

| Letter | How it lands in QML | Concrete |
|---|---|---|
| **S** Single Responsibility | One `.qml` file = one role. | `MetricRow` renders a row, `DraggableList` owns drag mechanics, `Ring` is the gauge. Logic in `*.js`, not in views. |
| **O** Open/Closed | Extend via composition, not inheritance. | `property Component extraContent` on `MetricRow` lets configMetrics add the CPU-cores sub-row without touching `MetricRow.qml`. |
| **L** Liskov | N/A — QML has no nominal subtyping. | Skip this letter; don't force it. |
| **I** Interface Segregation | Keep public props + signals minimal. | `MetricRow` exposes 4 props + 1 signal, not a kitchen sink. Test hooks are `_`-prefixed to flag them as internal. |
| **D** Dependency Inversion | Leaf components don't reach into globals. | No `Plasmoid.configuration.X` or `page.isEnabled(...)` inside leaves. They take inputs as properties and emit signals; the parent (e.g. `configMetrics`) wires them. |

Smells to flag during review:
- Leaf component reading `Plasmoid.configuration` directly → DIP violation.
- A QML file doing layout + logic + config writes → SRP violation; extract
  pure logic to a `.js` module and tests.
- A component growing a long list of `Plasmoid.X` props → ISP violation;
  the parent should hold them, the leaf takes just what it renders.

## Stack reminder

| QML thing | React equivalent |
|---|---|
| `.qml` file with root `Item` | Component file |
| `property real foo: 0` | `useState` |
| `width: parent.width / 2` | JSX expression in attribute |
| `MouseArea { onClicked: ... }` | `onClick` handler |
| `Component.onCompleted`, `onValueChanged` | `useEffect` |
| `Connections { target: X; function onY() }` | `useEffect(() => { X.on('y', …); return () => X.off('y', …) })` — for signals from non-reactive singletons / context properties (e.g. `Qt.styleHints`) |
| `RowLayout` / `ColumnLayout` | flexbox |
| `visible: condition` or `Loader` | conditional render |

Bindings are automatic — when `cpuSensor.value` changes, anything
depending on it re-renders.

## Plugin id

`dev.manuacl.ringmonitor`

Symlink (dev workflow): `~/.local/share/plasma/plasmoids/dev.manuacl.ringmonitor → ~/projects/ring-monitor`

## Aesthetic

User-chosen: **"anneaux modernes épurés"** (clean modern rings).

- 270° sweep starting at 135° (90° gap at the bottom).
- Single color family per ring group via `Kirigami.Theme.highlightColor`
  + opacity variants. No rainbow gradients (the Conky Ring Graph look
  was explicitly rejected).
- Rounded caps on all arcs.
- `Font.Light` for big numbers. Smooth value transitions
  (`Behavior on value { NumberAnimation; OutCubic }`).

## Common pitfalls (quick reminders)

- `plasmawindowed` exits silently on QML parse errors → check the journal
  (filter out `breezerc`).
- Bind `PathAngleArc.centerX` to the **Shape's** width/2 (give the Shape
  an `id`).
- KSysGuard sensors don't error on bad IDs — value just stays at 0/NaN.
  Be defensive (`s.value || 0`).
- After `main.xml` changes, restart plasmashell.
- **Don't put `pragma ComponentBehavior: Bound` on a QML file that
  contains a ListView delegate.** It silently breaks the drag — the
  implicit `model`/`index` and `MouseArea.drag.target` don't coexist
  with `required property var model`. Apply the pragma only to
  delegate-free files (`main.qml`, `Ring.qml` are OK).
- **Forward row data to rowContent via a property on the Loader, not
  via QML scope chain.** Inside a Loader that hosts a user-provided
  Component, declare `property var rowModel: model` on the Loader; the
  Component reads `parent.rowModel`. QML's context-property
  propagation through Loader is flaky across Qt versions / KCM
  containers — relying on bare `model.X` was the cause of the "empty
  labels" regression.
- **Plasma's config dialog has its own qmlcache.** If a QML change to
  a config page doesn't seem to take effect after restarting
  plasmashell, clear `~/.cache/{plasmashell,kcmshell6}/qmlcache/` and
  restart again.
- **Don't reuse a property name as an `id` in the same QML file when
  passing it down to a child Component.** Pattern that bites:
  `Platform.Theme { id: theme }` followed by `MainContent { theme: theme }`.
  The RHS `theme` resolves to the new component's own `theme`
  property (which is undefined at binding time) instead of the outer
  id — the child ends up with undefined props and the binding errors
  go to the journal, not the QML compiler. Fix: suffix the outer id
  (`themeAdapter`, `configStoreAdapter`, …) so the names don't
  collide. Especially dangerous inside `fullRepresentation: X { ... }`
  Component templates where the error is silent until runtime.
- **Live light/dark scheme detection in a panel widget: via
  `Qt.styleHints`, not via Kirigami.** `Kirigami.Theme.backgroundColor`
  reflects the panel's `Complementary` colorSet (fixed regardless of
  the user's System Settings → Colors choice). Even a probe Item with
  `inherit: false; colorSet: Window` does not actually re-evaluate
  live in plasmashell. The canonical KDE signal since KF 6.22 is
  `Qt.styleHints.colorScheme` (Qt 6.5+). Critical: the property has
  **no NOTIFY** (warning explicit in Qt's own doc) — binding it would
  never re-evaluate. Subscribe to the `colorSchemeChanged` signal via
  `Connections`, write the new value into an intermediate regular
  property, and let the public `readonly` API bind to that. Canonical
  pattern in `contents/ui/platforms/plasma/Theme.qml` (`_qtScheme` →
  `isDarkMode`). Caveat: some setups (third-party look-and-feel
  themes like Vapor) do not emit the signal live inside plasmashell;
  always expose an explicit Light/Dark override for the user.
- **Binding a `readonly property var` to a dynamic collection of
  properties: use a tick counter, not direct enumeration.** When
  `Sensors.Sensor` (or any QObject) instances are created via
  `Instantiator` (`model: array of ids`), the natural binding
  `[obj0.value, obj1.value, …]` only tracks dependencies at the
  initial evaluation — model adds / removes re-evaluate, but `.value`
  changes inside an already-instantiated delegate do NOT. Workaround:
  each delegate bumps `backend._tick++` in its `onValueChanged`, and
  the readonly property reads `backend._tick;` as its first line
  (tracked dependency). Then iterates `instantiator.objectAt(i)` to
  build the array. Canonical pattern in
  `contents/ui/platforms/plasma/MetricsBackend.qml` (`_coreTick`,
  `_gpuTempTick`, `_gpuUsageTick`).
- **Use `Sensors.Sensor.status` to know if a sensor id actually
  resolved.** Enum values: `Unknown`, `Loading`, `Ready`, `Error`,
  `Removed`. Before the first reading, `.value` is `undefined` / `NaN`
  (the defensive `|| 0` covers that on the rendering side). For
  probe-then-pick patterns (try several candidate ids, use the first
  that exists) and for "loading" warm-up animations, query `.status
  === Sensors.Sensor.Ready` rather than guessing from `.value`.
  Canonical use in `MetricsBackend.qml` (`loading` property,
  `_gpuTempValue` / `_gpuUsageValue` helpers).
- **Non-percent metrics decouple sweep input from display value.**
  `Ring.value` is always treated as 0-100 for the sweep angle math.
  When the metric is actually a temperature (or any non-percent —
  future: network rate, NVMe temp), the parent maps the raw reading
  to a percent for `value` AND passes the raw value via `rawValue`
  (with the matching `unit`, e.g. `"°C"`). The centre text reads
  `Math.round(rawValue) + unit` when finite, falls back to
  `value + unit` otherwise. The split arc applies the same dual-prop
  trick via `splitValue` (0-100 percent for the sweep) and
  `splitRawValue` (raw value for the text). Don't cram a non-percent
  value into `value` directly — the sweep math would be wrong.

For the deeper "why" on each pitfall and the drag-and-drop saga, see
`docs/`.
