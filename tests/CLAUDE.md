# `tests/` — Node + QML test layout

Two test runners cover two layers:

- **`tests/*.test.mjs`** — Node tests for pure JS (`contents/ui/core/*.js`
  modules) and text-level guards for QML files the CI container can't
  load. Run via `node --test tests/*.test.mjs`.
- **`tests/qml/tst_*.qml`** — `qmltestrunner-qt6` tests for what
  depends on the QML runtime (component rendering, model forwarding,
  signal flow). Run via `qmltestrunner-qt6 -input tests/qml`.

The combined runner is `tests/run-all.sh`. Both are reproduced in CI
(`.github/workflows/ci.yml`).

## Filename convention: kebab-case

`CamelCase.js` ↔ `kebab-case.test.mjs`:
- `RingGeometry.js` → `ring-geometry.test.mjs`
- `MetricsCatalog.js` → `metrics-catalog.test.mjs`
- `ReorderLogic.js` → `reorder-logic.test.mjs`

QML tests stay `tst_<ComponentName>.qml` to match qmltestrunner's
convention.

The `finish-branch` skill enforces both: every `core/*.js` must have
its paired `tests/<kebab>.test.mjs`, and a missing `tst_<Name>.qml`
for a new component triggers a stub creation. Full rationale in
[`../docs/testing.md`](../docs/testing.md).

## When to add a test

- **New `.js` module** → matching `tests/<kebab>.test.mjs`. This is
  not optional — `finish-branch` will fail loudly. Cover the public
  surface; cover the non-obvious branches (NaN, empty, clamp limits).
- **New QML component with public props / signals** →
  `tests/qml/tst_<Name>.qml`. Test `text`, `model` forwarding,
  signals — the things a Node test can't see. Pure Node tests didn't
  catch the "empty labels" regression because the bug was in a QML
  binding.
- **Reported bug fixed** → `SCENARIO:` test encoding the failure
  mode as a regression guard. Example: `SCENARIO_drag_away_then_back_to_origin_no_emit`
  in `tst_DraggableList.qml`. The body of the test names the bug, not
  the implementation detail.

## What lives where

Full per-file inventory in [`../docs/testing.md`](../docs/testing.md) §
"Test files". This file keeps the rule-shaped content (filename
convention, when to add a test, text-level Node-guard pattern); the
inventory belongs in `docs/` per the convention in
[`../docs/CLAUDE.md`](../docs/CLAUDE.md) ("`CLAUDE.md` is scannable
briefing, `docs/` is read-on-demand explanation including file
inventories").

## Text-level Node guards for QML files (a recurring pattern)

`ConfigStore.qml` imports `org.kde.plasma.plasmoid`, `MetricsBackend.qml`
imports `org.kde.ksysguard.sensors` — neither is in the CI Fedora 41
container (CI only installs Qt 6 + Kirigami). A `qmltestrunner` test
on those files would fail to load.

So `tests/config-store.test.mjs` and `tests/metrics-backend.test.mjs`
**inspect the QML source as plain text** (regex on the file content)
and assert the public surface is declared, every persisted key is
present, and the dynamic-discovery pattern is wired. It's coarser
than a runtime test but catches the same class of bug (typo in a
property name → silent undefined binding in production) without
needing the Plasma runtime.

## Where the runner / CI bits live

- `tests/run-all.sh` — local convenience: Node tests → QML tests,
  shared by humans and pre-PR scripts.
- `.github/workflows/ci.yml` — same two steps, plus the file-size cap
  job over `contents/ui/**/*.{qml,js}` and `tests/{*.test.mjs,qml/*.qml}`.
- `.githooks/pre-commit` — reproduces the file-size cap + qmlformat
  + qmllint locally so CI doesn't reject a push.

## See also

- Cross-cutting rules ("All logic must be tested", "Tests cover
  rendering too"): root [`/CLAUDE.md`](../CLAUDE.md).
- Pure-logic conventions (where `.js` modules live, dual loading
  shim): [`../contents/ui/core/CLAUDE.md`](../contents/ui/core/CLAUDE.md).
- Plasma adapter guards (why backend tests are text-level):
  [`../contents/ui/platforms/plasma/CLAUDE.md`](../contents/ui/platforms/plasma/CLAUDE.md).
- The deeper rationale: [`../docs/testing.md`](../docs/testing.md).
