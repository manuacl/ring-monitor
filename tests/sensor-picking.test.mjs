// TDD spec for SensorPicking.pickFirstReadyValue.
//
// Run:  node --test tests/sensor-picking.test.mjs
//
// Implementation: contents/ui/core/SensorPicking.js. Dual-loaded by
// QML and Node via the module.exports shim at the bottom.

import { createRequire } from "node:module";
import { test } from "node:test";
import assert from "node:assert/strict";

const require = createRequire(import.meta.url);
const SensorPicking = require("../contents/ui/core/SensorPicking.js");

test("pickFirstReadyValue returns 0 on null input", () => {
    assert.equal(SensorPicking.pickFirstReadyValue(null), 0);
});

test("pickFirstReadyValue returns 0 on undefined input", () => {
    assert.equal(SensorPicking.pickFirstReadyValue(undefined), 0);
});

test("pickFirstReadyValue returns 0 on empty list", () => {
    assert.equal(SensorPicking.pickFirstReadyValue([]), 0);
});

test("pickFirstReadyValue returns 0 when no candidate is ready", () => {
    const candidates = [
        { ready: false, value: 42 },
        { ready: false, value: 99 },
    ];
    assert.equal(SensorPicking.pickFirstReadyValue(candidates), 0);
});

test("pickFirstReadyValue returns the first ready candidate's value", () => {
    const candidates = [
        { ready: true, value: 73 },
        { ready: true, value: 99 },
    ];
    assert.equal(SensorPicking.pickFirstReadyValue(candidates), 73);
});

test("pickFirstReadyValue skips not-ready candidates before the first ready one", () => {
    const candidates = [
        { ready: false, value: 99 },
        { ready: false, value: 88 },
        { ready: true, value: 42 },
        { ready: true, value: 11 },
    ];
    assert.equal(SensorPicking.pickFirstReadyValue(candidates), 42);
});

test("pickFirstReadyValue tolerates null entries (callers may skip filtering)", () => {
    const candidates = [null, undefined, { ready: true, value: 50 }];
    assert.equal(SensorPicking.pickFirstReadyValue(candidates), 50);
});

test("pickFirstReadyValue coerces a ready candidate's undefined value to 0", () => {
    const candidates = [{ ready: true, value: undefined }];
    assert.equal(SensorPicking.pickFirstReadyValue(candidates), 0);
});

test("pickFirstReadyValue coerces a ready candidate's NaN value to 0", () => {
    const candidates = [{ ready: true, value: NaN }];
    assert.equal(SensorPicking.pickFirstReadyValue(candidates), 0);
});

test("pickFirstReadyValue returns a ready candidate's value when it is 0 (does not skip)", () => {
    // A genuinely 0 reading from a ready sensor IS the answer — it
    // must not fall through to the next candidate.
    const candidates = [
        { ready: true, value: 0 },
        { ready: true, value: 99 },
    ];
    assert.equal(SensorPicking.pickFirstReadyValue(candidates), 0);
});

test("pickFirstReadyValue: a ready candidate with null value wins and yields 0 (does not fall through)", () => {
    // `value || 0` is correct because the contract says callers
    // either pass a finite number or rely on the fallback. We test
    // the value=null edge case here. The previous title said "returns
    // a non-zero ready value" which contradicts what the assertion
    // actually checks — the first ready wins even when its value
    // coerces to 0 via `|| 0`.
    const candidates = [
        { ready: true, value: null },
        { ready: true, value: 50 },
    ];
    assert.equal(SensorPicking.pickFirstReadyValue(candidates), 0);
});
