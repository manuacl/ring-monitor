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

| File | Covers |
|---|---|
| `tests/reorder-logic.test.mjs` | drag-to-reorder math from `ReorderLogic.js` |
| `tests/metrics-catalog.test.mjs` | catalog + CSV helpers from `MetricsCatalog.js` |
| `tests/ring-geometry.test.mjs` | sweep/radius/sizing math from `RingGeometry.js` |

All current logic is covered. New pure modules should ship with a
matching `*.test.mjs`.

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
