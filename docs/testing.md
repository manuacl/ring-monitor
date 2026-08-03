# Testing

## Running tests

```bash
node --test tests/
```

That's it — no framework, no install step. We rely on Node's built-in
test runner (`node:test` + `node:assert/strict`), available since Node
18.

To run a single file:

```bash
node --test tests/reorder-logic.test.mjs
```

To watch (re-run on save):

```bash
node --watch --test tests/
```

## Test files

Two runners, two test layers:

- **`tests/*.test.mjs`** — Node tests (pure-JS modules from
  `contents/ui/core/*.js`, plus text-level guards for QML / C++
  files the CI container can't load). Run via `node --test tests/`.
- **`tests/qml/tst_*.qml`** — `qmltestrunner-qt6` tests for what
  depends on the QML runtime (component rendering, model
  forwarding, signal flow). Run via `qmltestrunner-qt6 -input
  tests/qml`.

`tests/run-all.sh` chains both; CI reproduces the same two steps
in `.github/workflows/ci.yml`.

### Node tests (`tests/*.test.mjs`)

Pure-logic tests for `core/*.js` modules:

| File | Covers |
|---|---|
| `metrics-catalog.test.mjs` | catalog ids, sensor mapping, CSV helpers, sensor-discovery classifier |
| `metrics-temperature.test.mjs` | `valueFromSensorMap` defensive reads, °C→% mapping (`tempToPercent`), display-unit resolution + °C→°F conversion |
| `ring-geometry.test.mjs` | sweep / radius / sizing math from `RingGeometry.js` |
| `reorder-logic.test.mjs` | drag-to-reorder array transform (`applyMove`, `computeYShift`) |
| `color-themes.test.mjs` | theme registry + dark/light variant resolution |
| `sensor-picking.test.mjs` | `pickFirstReadyValue` short-circuit semantics |
| `proc-stat-parser.test.mjs` | `/proc/stat` parser + percent math + SCENARIO guards (`cpu`-prefix gate, counter wraparound) |
| `mem-info-parser.test.mjs` | `/proc/meminfo` parser + `usagePercent` (RAM) + `diskUsagePercent` (df formula) |
| `update-check.test.mjs` | semver + notification gating for the in-widget update badge |

Text-level guards (Plasma adapter — `org.kde.plasma.plasmoid` /
`org.kde.ksysguard.sensors` imports aren't in the CI container):

| File | Covers |
|---|---|
| `config-store.test.mjs` | every persisted key declared + bound to `Plasmoid.configuration.X` |
| `metrics-backend.test.mjs` | public surface + universal Sensor instances + `SensorTreeModel` discovery + Instantiator pattern |
| `config-pages-placeholders.test.mjs` | `PlaceholderKCM.qml` declares `cfg_<key>` + `cfg_<key>Default` for every `main.xml` entry, and every `config.qml` page extends it (KDE bug 484541 seam; key set and page list both derived at test time) |

Text-level guards (standalone adapter + C++ files — no
`qmltestrunner` path for files that import `RingMonitor.Standalone`
or that have no Qt-runtime entry point):

| File | Covers |
|---|---|
| `standalone-config-store.test.mjs` | standalone `ConfigStore` mirrors the Plasma key set |
| `standalone-metrics-backend.test.mjs` | wiring of `/proc/stat`, `/proc/meminfo`, `statvfs`, `diskUsagePercent` |
| `standalone-settings-dialog.test.mjs` | `SettingsDialog._bridgeMap` covers every persisted key |
| `standalone-main.test.mjs` | `Main.qml` — deferred `_anchor`, Screen re-anchor, settings-only recovery branch |
| `standalone-main-cpp.test.mjs` | `main.cpp` — argv parse, `settingsOnlyMode` context property, gated EWMH hints |
| `autostart.test.mjs` | `autostart.cpp` desktop-entry write / remove contract |
| `desktop-hints.test.mjs` | `desktop_hints.cpp` — `_NET_WM_STATE` property write, BELOW in list, XWayland probe, `qWarning` on no-op |
| `proc-reader.test.mjs` | `proc_reader.cpp` `/proc/` + `/sys/` allowlist, refusal warning, isolation invariant |

### QML tests (`tests/qml/tst_*.qml`)

Rendered through `qmltestrunner-qt6` — covers the things a Node text
guard can't see (binding flow, signal emission, layout):

| File | Covers |
|---|---|
| `tst_Ring.qml` | label / value / unit rendering, sweep angles, `nestedValues` count, split mode, `rawValue` override |
| `tst_MetricRow.qml` | row layout, checkbox state, `extraContent`, disabled cascade |
| `tst_DraggableList.qml` | `rowModel` forwarding, drag scenarios, no-op drags |
| `tst_MetricsBody.qml` | order CSV ↔ model, `isEnabled` / `setEnabled`, descriptions, `tempUnit` radios |
| `tst_MetricsBodyDisk.qml` | disk-partition picker: selection CSV roundtrip, order model, stale rows, removable auto-show/opt-out |
| `tst_SensorTempSettings.qml` | property round-trip, per-field `*Edited` signal wiring, spinbox cross-clamp |
| `tst_AppearanceBody.qml` | opacity sliders bind two-way, mode radios |
| `tst_MainContent.qml` | ring composition + theme propagation |
| `tst_AboutBody.qml` | version display + update-badge wiring |
| `tst_Theme.qml` | Kirigami theme passthrough + `Qt.styleHints` live light/dark |
| `tst_ThemedIcon.qml` | `Kirigami.Icon` wrapper surface |
| `tst_UpdateChecker.qml` | manual-check signal flow + state transitions |
| `tst_ReorderCycle.qml` | end-to-end drag-cycle regression |

New pure modules / new adapter files should ship with a matching
entry above. The rule lives in [`../tests/CLAUDE.md`](../tests/CLAUDE.md).

### Naming convention

A `.js` module's paired test file is its **kebab-case** form, not
camelCase:

| Module                  | Test file                          |
|---|---|
| `ReorderLogic.js`       | `reorder-logic.test.mjs`           |
| `MetricsCatalog.js`     | `metrics-catalog.test.mjs`         |
| `RingGeometry.js`       | `ring-geometry.test.mjs`           |
| `ColorThemes.js`        | `color-themes.test.mjs`            |

The `finish-branch` skill enforces this convention by deriving the
expected test path from the module name (`sed 's/\([a-z0-9]\)\([A-Z]\)/\1-\2/g' | tr '[:upper:]' '[:lower:]'`).
A camelCase test filename will fail the audit and block phase B
until renamed — an iteration cost that's been paid once already.

## Writing tests

The pattern (mirrors the existing files):

```js
import { createRequire } from 'node:module';
import { test } from 'node:test';
import assert from 'node:assert/strict';

const require = createRequire(import.meta.url);
const Foo = require('../contents/ui/core/Foo.js');

test('foo: human-readable expectation', () => {
    assert.equal(Foo.foo(1, 2), 3);
});
```

Why `createRequire`? The source modules are `.js` files using
`module.exports` (so QML can also load them). Test files are `.mjs`
(ESM), and ESM can't directly `require` CJS. `createRequire` bridges
that.

## What to test

Pure functions: yes. Visual layout: no.

Worth testing:

- Anything that takes inputs and returns outputs (no QML / DOM globals).
- Edge cases: empty input, out-of-range input, NaN, very small / very
  large input.
- Scenarios that map to user bug reports — those go into `SCENARIO:`
  tests as the encoded fix. Example in
  `reorder-logic.test.mjs`:

  ```js
  test('SCENARIO: drag row 3 up to row 0 then back to origin → final shifts all 0', ...)
  ```

Not worth testing (this project):

- The QML/visual side of components — covered by manual testing in
  `plasmawindowed` and on the desktop.
- KSysGuard sensor connectivity — outside our control.

## TDD

When a bug shows up that should be impossible given the code:

1. Find or extract the pure function that owns the broken behavior.
2. Write a failing test that mirrors the user's symptom.
3. Fix the function until the test passes.
4. Leave the test in place — it becomes the regression guard.

The drag-and-drop rewrite did exactly this — the user reported "can't
return to origin" and "stuck on last drop position"; both became
SCENARIO tests before the implementation changed.
