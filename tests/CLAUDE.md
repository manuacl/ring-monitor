# `tests/` — Node + QML test layout

Two test runners cover two layers:

- **`tests/*.test.mjs`** — Node tests for pure JS (`contents/ui/core/*.js`
  modules) and text-level guards for QML files the CI container can't
  load. Run via `node --test tests/*.test.mjs`.
- **`tests/qml/tst_*.qml`** — `qmltestrunner-qt6` tests for what
  depends on the QML runtime (component rendering, model forwarding,
  signal flow). Run via `qmltestrunner-qt6 -input tests/qml`. Binary
  name varies by install: `qmltestrunner-qt6` (distro package) or
  `qmltestrunner` in Qt's own bin dir (`/usr/lib/qt6/bin/qmltestrunner`).
  CI uses the `-qt6` name.

The combined runner is `tests/run-all.sh`. Both are reproduced in CI
(`.github/workflows/ci.yml`).

## Filename convention: kebab-case

`CamelCase.js` ↔ `kebab-case.test.mjs`:
- `RingGeometry.js` → `ring-geometry.test.mjs`
- `MetricsCatalog.js` → `metrics-catalog.test.mjs`
- `ReorderLogic.js` → `reorder-logic.test.mjs`

QML tests stay `tst_<ComponentName>.qml` to match qmltestrunner's
convention. A component's test file at the 500-line cap → split per
concern as `tst_<Component><Concern>.qml` (e.g.
`tst_MetricsBodyLabelCache.qml`); never trim existing assertions to
fit — qmltestrunner picks up every `tst_*.qml`, so the split is free.

The `finish-branch` skill enforces both: every `core/*.js` must have
its paired `tests/<kebab>.test.mjs`, and a missing `tst_<Name>.qml`
for a new component triggers a stub creation. Full rationale in
[`../docs/testing.md`](../docs/testing.md).

### Don't `qmlformat -i` the QML test fixtures

Hand-match the surrounding style in `tests/qml/*.qml` (notably the
**compact inline-object** literals — `[{ id: "x", label: "y" }]`); do
**not** run `qmlformat-qt6 --inplace` on them. A newer local qmlformat
(Qt 6.10) expands those inline objects that the committed style keeps
inline, and the pre-commit cap check runs **before** its qmlformat pass —
so a reflowed near-cap fixture commits over 500 lines and the next commit
rejects it. CI's qmlformat-check covers **source** `.qml` only
(`contents/ui/*`), not `tests/qml/`, so the compact committed style is
what CI expects. (Bit the per-partition-color work: `qmlformat -i`
ballooned `tst_MetricsBody.qml` 497 → 533.)

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

### Reaching a leaf control from a test: `objectName` + `findChild`

To assert a **leaf control's** wiring (a `TextField` / `SpinBox` buried
inside the component under test), give the control an `objectName` and
look it up with `TestCase.findChild(subject, "theName")` — reference:
`tst_SensorTempSettings.qml`. Prefer this over a `_`-prefixed `property
alias` hook: an alias exposes the control's whole surface as public
component API, while `objectName` stays invisible to QML consumers.
Keep `_`-prefixed aliases for component-level hooks (models, inner
components the test must drive directly), not for individual leaf
controls.

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

### Drift-catchers derive their expected set, never hardcode it

A text-guard that asserts "the standalone adapter declares the same
keys as the Plasma adapter" (or "ConfigStore declares every schema
key") must build its expected set **from the source of truth at test
time**, not from an inline list copied into the test. The inline
list is itself a thing that drifts — PR #35 had to hand-edit the
hardcoded `EXPECTED_KEYS` to add the `ringSize` trio, which means a
contributor who forgets that edit gets a green test against a stale
list.

Canonical derivations in use:
- Config keys ← `contents/config/main.xml`'s `<entry name="X">` set
  (`config-store.test.mjs`, `standalone-config-store.test.mjs`).
- Theme adapter surface ← the Plasma `Theme.qml`'s public
  (non-`_`-prefixed) `readonly property` declarations
  (`standalone-theme.test.mjs`), asserted both directions.

Always pair the derivation with a sanity assertion (e.g. "≥20 keys
found") so a regex/path regression that empties the set fails loudly
instead of making every downstream assertion vacuously pass.

### A `doesNotMatch` guard targets the *call*, not the bare symbol

A negative guard (`assert.doesNotMatch`) must match the actual code
construct it forbids — `/setKeyboardInteractivity\([^)]*None/`, not a
bare `/KeyboardInteractivityNone/`. The comment that explains *why* a
value is rejected almost always names that value ("SCENARIO: `None`
left the menu fullscreen…"), so a bare-symbol regex matches the prose
and fails spuriously even though no forbidden call exists. Hit twice in
PR C2 (the `KeyboardInteractivityNone` and `useLayerShell` guards both
matched their own explanatory comments). Anchor on the call shape or a
fully-qualified `Class::method(`.

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
