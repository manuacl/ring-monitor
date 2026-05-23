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

## Working rules

These are forced by the user's preferences, not by the tech stack:

- **Logic in dedicated files, views thin.** Pure logic goes in
  `contents/ui/*.js` (dual-loadable by QML and Node). QML files
  consume them.
- **All logic must be tested.** New `.js` module ⇒ matching
  `tests/*.test.mjs`. Use `SCENARIO:` tests to encode reported bugs as
  regression guards.
- **No nested ternaries.** `a ? x : b ? y : c ? z : d` → use a lookup
  map, a `switch`, or extract a named function. Single ternaries are OK.
- **i18n keys in English.** Source strings stay English; translation is a
  downstream concern.
- **`pragma ComponentBehavior: Bound` on every QML file.** All scope
  accesses must be explicit (`row.index` not `index`,
  `root.someProperty` works from nested Components thanks to Bound).
  Delegate scopes declare `required property var model` /
  `required property int index`.
- **`qmlformat`/`qmllint` run on commit** via `.githooks/pre-commit`.
  Enable per clone: `git config core.hooksPath .githooks`.

## Stack reminder

| QML thing | React equivalent |
|---|---|
| `.qml` file with root `Item` | Component file |
| `property real foo: 0` | `useState` |
| `width: parent.width / 2` | JSX expression in attribute |
| `MouseArea { onClicked: ... }` | `onClick` handler |
| `Component.onCompleted`, `onValueChanged` | `useEffect` |
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

For the deeper "why" on each pitfall and the drag-and-drop saga, see
`docs/`.
