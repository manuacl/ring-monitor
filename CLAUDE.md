# Ring Monitor

Plasma 6 widget for system monitoring with circular ring gauges.
Built from scratch as a learning project (user knows React, not QML —
so explanations should map back to React concepts when introducing
new QML ones).

Target: KDE Plasma 6 Wayland on Bazzite.

## Where to look

This file is the cross-cutting briefing. **Per-layer `CLAUDE.md` files
hold the scoped rules** so an agent working on a subdir sees only what
matters there:

- [`contents/ui/core/CLAUDE.md`](contents/ui/core/CLAUDE.md) —
  portable QML layer (Ring, DraggableList, the `.js` modules). The
  plasma-isolation invariant lives there, plus the `Ring.value` vs
  `rawValue` rule and the Loader.rowModel forwarding pattern.
- [`contents/ui/platforms/plasma/CLAUDE.md`](contents/ui/platforms/plasma/CLAUDE.md) —
  Plasma adapter layer (KSysGuard, Plasmoid.configuration, Theme,
  KCM). KSysGuard quirks, tick-counter pattern, `Sensor.status` enum,
  config-dialog qmlcache, Qt.styleHints light/dark, KDE bug 484541.
- [`contents/ui/platforms/standalone/CLAUDE.md`](contents/ui/platforms/standalone/CLAUDE.md) —
  standalone adapter layer (no Plasma deps; `/proc` + sysfs +
  `Qt.labs.settings`). Same-surface contract with the Plasma
  adapters, Conky-style window flags per compositor, status of the
  PR B → H sequence.
- [`tests/CLAUDE.md`](tests/CLAUDE.md) — `node --test` + qmltestrunner
  layout, kebab-case filename convention, text-level Node guards for
  Plasma-import QML files, SCENARIO regression tests.
- [`docs/CLAUDE.md`](docs/CLAUDE.md) — long-form docs structure, how
  to keep `components.md` / `logic-modules.md` in sync with the code,
  the `CLAUDE.md` vs `docs/` line.

The deeper docs live in `docs/`:

- [`docs/architecture.md`](docs/architecture.md) — file roles, layering
  rule, data flow.
- [`docs/components.md`](docs/components.md) — `Ring.qml`,
  `DraggableList.qml`, `MetricRow.qml`, platform adapters.
- [`docs/logic-modules.md`](docs/logic-modules.md) — pure JS modules.
- [`docs/config-dialog.md`](docs/config-dialog.md) — Plasma config
  gotchas (KDE bug 484541, SimpleKCM, AnchorChanges).
- [`docs/adding-a-metric.md`](docs/adding-a-metric.md) — step-by-step.
- [`docs/testing.md`](docs/testing.md) — `node --test tests/`, when to
  add tests.
- [`docs/development.md`](docs/development.md) — symlink, plasmashell
  restart, `plasmawindowed`, journal greps, QML tooling.
- [`docs/releasing.md`](docs/releasing.md) — release flow
  (`version.yml` + `release.yml`), `BUMP_TOKEN` PAT rotation, KDE
  Store.
- [`docs/plasma-isolation/plan.md`](docs/plasma-isolation/plan.md) —
  active multi-PR refactor isolating Plasma deps.

## Working rules (cross-cutting)

These apply everywhere in the repo regardless of which layer you're
editing.

- **Never `git push` without an explicit user request.** A green
  audit, an open PR, or an invoked pipeline skill (`finish-branch`
  included) is NOT authorization — ask and wait for the user's go in
  the current conversation before any push, every time. Local commits
  are fine; publishing is the user's call.
- **English-only repo.** All committed files — code, comments,
  `docs/*.md`, every `CLAUDE.md`, `README.md`, commit messages, PR
  titles/bodies, and `.claude/skills/*/SKILL.md` — are written
  exclusively in English. i18n source strings stay English
  (translation is a downstream concern). The conversation with the
  user can be in any language; only what lands in the repo is
  constrained.
- **No nested ternaries.** `a ? x : b ? y : c ? z : d` → use a lookup
  map, a `switch`, or extract a named function. Single ternaries are
  OK.
- **No leading-underscore QML `id`s** (`id: _x`). qmlformat 6.11 exits 1
  with empty output on any file containing one (Qt regression), which
  false-fails format audits on newer dev boxes. `_`-prefixed *properties*
  are fine (the internal-test-hook convention); only `id:` is affected.
- **500 lines max per source / test file.** Enforced by both the
  pre-commit hook and CI over `contents/ui/**/*.{qml,js}` and
  `tests/{*.test.mjs,qml/*.qml}`. When a file outgrows it: split —
  extract pure logic to a `.js` module, or pull a sub-component into
  its own `.qml` file (e.g. the `MetricRow` extraction from
  `configMetrics.qml`). Don't raise the cap. Docs (`docs/*.md`, every
  `CLAUDE.md`) are intentionally not capped. Beware the cap × qmlformat
  interaction on **source** `.qml`: qmlformat (pre-commit + CI) expands
  an inline JS object-literal array to one property per line, so a
  `readonly property var m: [{ value: …, text: … }, …]` model balloons
  ~3× and can breach the cap. Near the cap, back a `ComboBox` with a
  flat string array (`[qsTr("A"), qsTr("B")]` — qmlformat keeps those
  inline) plus a parallel value array, not an object `{value,text}`
  model. (The inverse fixture rule — *don't* `qmlformat -i` test
  fixtures — is in `tests/CLAUDE.md`.)
- **Comments: why, not what — and not a third copy.** A comment that
  restates what the code does (or paraphrases a self-evident binding)
  is noise; delete it and let the code + the symbol name carry it. Keep
  comments that encode a *why the reader can't deduce*: a `SCENARIO:`
  bug trace, a KDE/Qt bug number, a platform gotcha, a non-obvious
  invariant. When the rationale runs longer than ~4 lines it's
  explanation, not a rule — move it to `docs/` and leave a one-line
  pointer (`// availability axis: see docs/components.md`), so the same
  prose doesn't live in three places (code + `docs/` + `CLAUDE.md`).
  This also relieves the 500-line cap above without deleting tests or
  splitting a file.
- **Qt docs before inventing.** For any QtQuick pattern (drag/drop,
  model/view, animations), start from
  [doc.qt.io](https://doc.qt.io/qt-6/) — especially the "Dynamic View
  Ordering" / "QML Cookbook" tutorials. No hand-rolled
  reimplementation while an official pattern exists. The drag-and-
  drop saga was a manual `mapToItem` + `_draggedY` reimplementation
  of what `MouseArea.drag.target` does natively.
- **All logic must be tested.** New `.js` module ⇒ matching
  `tests/*.test.mjs`. New QML component with public surface ⇒
  `tests/qml/tst_<Name>.qml`. Use `SCENARIO:` tests to encode
  reported bugs as regression guards. Layout, naming and patterns:
  [`tests/CLAUDE.md`](tests/CLAUDE.md).
- **No hardcoded absolute paths to executables.** Invoke external
  tools by bare name (`lsblk`, not `/usr/bin/lsblk`) and let `PATH`
  resolve them — pinning a binary dir breaks on distros that install
  it elsewhere, and the widget must install on **any** Linux. Absolute
  paths to *kernel / FHS interfaces* (`/proc`, `/sys`, `/run/media`,
  `/dev`) are fine — those are stable across distros. Motivating case:
  `MountInfo.qml`'s plasma5support `lsblk` call (the executable engine
  inherits the session `PATH`, so bare resolves). Enforced by
  `finish-branch` (grep for `/usr/bin/`, `/sbin/`, … in source).
- **Pure-logic placement follows usage, not just purity.** Shared by
  both platforms ⇒ `core/*.js`. Used by one platform only ⇒ that
  platform's `platforms/<p>/` dir, beside its adapter — keeping
  platform-only logic in `core/` ships it as dead code in the other
  artifact (the `.plasmoid` zip, or the standalone CMake module).
  Don't default everything to `core/`. Full rule + the current split:
  [`contents/ui/core/CLAUDE.md`](contents/ui/core/CLAUDE.md) §
  "Logic in dedicated `.js` files".
- **Distro-agnostic content.** The widget installs on **any** Linux — so
  don't name a specific distro in code, comments, or test fixtures when
  the underlying *technology* is the real subject (`composefs` /
  `rpm-ostree` / `zram`, not "Bazzite"; a root volume label is `root`, not
  a distro name). A distro name is acceptable only as *one example among
  several*, or in `docs/development.md` documenting the maintainer's actual
  dev box. Same "runs on any Linux" spirit as the no-absolute-paths rule
  above.

## Design principles (SOLID, QML-adapted)

QML has no nominal inheritance, so the SOLID grid rewrites slightly.
The shorthand: **stateless components, data via props, events via
signals, parents wire them together.**

| Letter | How it lands in QML | Concrete |
|---|---|---|
| **S** Single Responsibility | One `.qml` file = one role. | `MetricRow` renders a row, `DraggableList` owns drag mechanics, `Ring` is the gauge. Logic in `*.js`, not in views. |
| **O** Open/Closed | Extend via composition, not inheritance. | `property Component extraContent` on `MetricRow` lets configMetrics add the CPU-cores sub-row without touching `MetricRow.qml`. |
| **L** Liskov | N/A — QML has no nominal subtyping. | Skip this letter; don't force it. |
| **I** Interface Segregation | Keep public props + signals minimal. | `MetricRow` exposes 4 props + 1 signal, not a kitchen sink. Test hooks are `_`-prefixed to flag them as internal. |
| **D** Dependency Inversion | Leaf components don't reach into globals. | No `Plasmoid.configuration.X` or `page.isEnabled(...)` inside leaves. They take inputs as properties and emit signals; the parent (e.g. `configMetrics`) wires them. |

Smells to flag during review:
- Leaf component reading `Plasmoid.configuration` directly → DIP
  violation.
- A QML file doing layout + logic + config writes → SRP violation;
  extract pure logic to a `.js` module and tests.
- A component growing a long list of `Plasmoid.X` props → ISP
  violation; the parent should hold them, the leaf takes just what it
  renders.

## Stack reminder (QML ↔ React)

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

Symlink (dev workflow):
`~/.local/share/plasma/plasmoids/dev.manuacl.ringmonitor → ~/projects/ring-monitor`.

## Aesthetic

User-chosen: **"anneaux modernes épurés"** (clean modern rings).

- 270° sweep starting at 135° (90° gap at the bottom).
- Split mode: the same sweep scinded at 12 o'clock into two half-arcs
  growing bottom-up, with an 8° symmetric gap at the top so the
  RoundCap endpoints don't crush each other.
- Single color family per ring group via
  `Kirigami.Theme.highlightColor` + opacity variants. No rainbow
  gradients (the Conky Ring Graph look was explicitly rejected).
- Rounded caps on all arcs.
- `Font.Light` for big numbers. Smooth value transitions
  (`Behavior on value { NumberAnimation; OutCubic }`).

## Where the rest lives

- **Layer-scoped rules** — see "Where to look" above. Each subdir's
  `CLAUDE.md` is loaded automatically when an agent works inside it,
  so layer-specific gotchas don't pollute the cross-cutting briefing.
- **Long-form rationale** — `docs/*.md`. The `CLAUDE.md` family is
  scanned (rule-shaped, "don't do X"); `docs/` is read on demand
  (explanation-shaped, "the trade-off was…"). See
  [`docs/CLAUDE.md`](docs/CLAUDE.md) for the dividing line.
