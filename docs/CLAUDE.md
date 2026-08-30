# `docs/` — long-form documentation

Where the depth lives. The root `CLAUDE.md` and the layer-specific
`CLAUDE.md` files are the briefings; this directory holds the
walkthrough explanations, file inventories, and refactor plans.

## Documents

- [`architecture.md`](architecture.md) — file roles, layering rule
  (core → platforms), data flow.
- [`components.md`](components.md) — the visual components: `Ring.qml`,
  `DraggableList.qml`, `MetricRow.qml`, and the platform adapters
  (`Theme.qml`, `ConfigStore.qml`, `MetricsBackend.qml`,
  `ThemedIcon.qml`, `ColorPicker.qml`).
- [`logic-modules.md`](logic-modules.md) — pure JS modules
  (`MetricsCatalog`, `ReorderLogic`, `RingGeometry`, `ColorThemes`)
  with their public APIs.
- [`config-dialog.md`](config-dialog.md) — Plasma config-dialog
  gotchas (KDE bug 484541, `SimpleKCM`, `AnchorChanges`, the qmlcache
  reload pattern).
- [`adding-a-metric.md`](adding-a-metric.md) — step-by-step: catalog
  entry, sensor instance, description, optional sub-option,
  schema default. Also the canonical example for the
  "non-percent sensors" caveat (temperature split-mode + dedicated
  temp ring).
- [`testing.md`](testing.md) — `node --test` / `qmltestrunner-qt6`
  layouts, the kebab-case test filename convention, when to add a
  test.
- [`development.md`](development.md) — copy-based dev install for the
  Plasma workflow, restarting plasmashell, `plasmawindowed`
  standalone preview, journal greps, QML tooling.
- [`releasing.md`](releasing.md) — release flow
  (`version.yml` + `release.yml`), `bump:*` PR labels, KDE Store
  upload.
- [`plasma-isolation/plan.md`](plasma-isolation/plan.md) — active
  multi-PR refactor isolating Plasma deps behind the
  `platforms/plasma/` adapter layer.
- [`battery-ring/spec.md`](battery-ring/spec.md) — scoping spec for the
  battery ring (#94 / PR #158). Working document: delete it when the PR
  merges, moving the durable parts into `components.md` and
  `logic-modules.md`.

## Rules for editing docs

### English-only

Every doc file is written in English. This is the project-wide rule
(also in the root `CLAUDE.md`) but worth repeating here because docs
are where the temptation to lapse into French is highest — keep
the chat in French, but anything that lands in `docs/` is committed
code and stays English.

### Keep docs in sync with code

A change in `contents/ui/` often implies a doc update — `finish-branch`
catches the obvious cases (new `.qml` component → stub in
`components.md`; new `.js` module → stub in `logic-modules.md`; new
public prop on a documented component → its section in
`components.md` must be touched) and creates a stub when missing.
Stubs are fine; placeholder TODO sections are the worst outcome and
finish-branch will flag them in the audit summary.

When in doubt, the breakdown:
- **`components.md`** — anything in `contents/ui/core/*.qml` or
  `contents/ui/platforms/plasma/*.qml` with a public surface (props /
  signals worth describing).
- **`logic-modules.md`** — anything in `contents/ui/core/*.js`.
- **`adding-a-metric.md`** — anything that changes the
  metric-addition workflow (catalog shape, sensor pattern, sub-option
  convention).
- **`config-dialog.md`** — anything that changes how the config
  dialog works (new SimpleKCM gotcha, new bridging convention).
- **`development.md`** — anything that changes the dev workflow (new
  tool, new restart procedure, new dev-install layout).

### Don't duplicate `CLAUDE.md`

The `CLAUDE.md` family (root + sub-dirs) is the **scannable briefing
loaded into every agent context**. Anything load-bearing for an
agent's decision-making goes there. `docs/` is the **read-on-demand
explanation** — the *why*, the historical context, the file
inventories, the deeper trade-offs.

If a section feels rule-shaped ("don't do X", "always do Y"), it
belongs in a `CLAUDE.md`. If it's explanatory ("the drag-and-drop
saga went through three iterations because…"), it belongs here.

## See also

- Where the rules per layer live:
  - root [`/CLAUDE.md`](../CLAUDE.md) for cross-cutting.
  - [`../contents/ui/core/CLAUDE.md`](../contents/ui/core/CLAUDE.md)
    for the portable layer.
  - [`../contents/ui/platforms/plasma/CLAUDE.md`](../contents/ui/platforms/plasma/CLAUDE.md)
    for the Plasma adapters.
  - [`../tests/CLAUDE.md`](../tests/CLAUDE.md) for the test layout.
