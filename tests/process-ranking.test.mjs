// Tests for ProcessRanking.js — pure ranking + formatting for the CPU-ring
// process tooltip (issue #69), shared by both platform adapters.

import { createRequire } from 'node:module';
import { test } from 'node:test';
import assert from 'node:assert/strict';

const require = createRequire(import.meta.url);
const PR = require('../contents/ui/core/ProcessRanking.js');

const rec = (pid, name, cpuPercent, rssKb) => ({ pid, name, cpuPercent, rssKb });

test('DEFAULT_LIMIT is 20 (issue #69 spec: top 20)', () => {
    assert.equal(PR.DEFAULT_LIMIT, 20);
});

// ── rankByCpu ────────────────────────────────────────────────────────────

test('rankByCpu: sorts by cpuPercent descending', () => {
    const out = PR.rankByCpu([rec(1, 'a', 3), rec(2, 'b', 50), rec(3, 'c', 12)]);
    assert.deepEqual(out.map(r => r.name), ['b', 'c', 'a']);
});

test('rankByCpu: caps to the given limit', () => {
    const input = [rec(1, 'a', 1), rec(2, 'b', 2), rec(3, 'c', 3), rec(4, 'd', 4)];
    assert.equal(PR.rankByCpu(input, 2).length, 2);
    assert.deepEqual(PR.rankByCpu(input, 2).map(r => r.name), ['d', 'c']);
});

test('rankByCpu: defaults to DEFAULT_LIMIT (20) when limit omitted', () => {
    const input = [];
    for (let i = 0; i < 50; i++)
        input.push(rec(i, 'p' + i, i));
    assert.equal(PR.rankByCpu(input).length, 20);
});

test('rankByCpu: ties break by pid ascending (deterministic, no flicker)', () => {
    const out = PR.rankByCpu([rec(9, 'late', 10), rec(2, 'early', 10), rec(5, 'mid', 10)]);
    assert.deepEqual(out.map(r => r.pid), [2, 5, 9]);
});

test('rankByCpu: does not mutate the input array', () => {
    const input = [rec(1, 'a', 1), rec(2, 'b', 9)];
    const snapshot = input.map(r => r.pid);
    PR.rankByCpu(input);
    assert.deepEqual(input.map(r => r.pid), snapshot);
});

test('rankByCpu: drops records with no pid', () => {
    const out = PR.rankByCpu([rec(1, 'a', 5), { name: 'nopid', cpuPercent: 99 }, { pid: null, cpuPercent: 80 }]);
    assert.deepEqual(out.map(r => r.name), ['a']);
});

test('rankByCpu: coerces NaN / negative / undefined cpuPercent to 0', () => {
    const out = PR.rankByCpu([rec(1, 'good', 5), rec(2, 'nan', NaN), rec(3, 'neg', -10), rec(4, 'undef', undefined)]);
    assert.equal(out[0].name, 'good');
    // The three coerced-to-0 rows sit below, ordered by pid.
    assert.deepEqual(out.slice(1).map(r => [r.name, r.cpuPercent]), [['nan', 0], ['neg', 0], ['undef', 0]]);
});

test('rankByCpu: missing name becomes empty string', () => {
    const out = PR.rankByCpu([{ pid: 7, cpuPercent: 3 }]);
    assert.equal(out[0].name, '');
});

test('rankByCpu: carries rssKb through (RAM-tooltip forward hook)', () => {
    const out = PR.rankByCpu([rec(1, 'a', 5, 123456)]);
    assert.equal(out[0].rssKb, 123456);
});

test('rankByCpu: non-array / non-positive limit → empty array', () => {
    assert.deepEqual(PR.rankByCpu(null), []);
    assert.deepEqual(PR.rankByCpu(undefined), []);
    assert.deepEqual(PR.rankByCpu([rec(1, 'a', 5)], 0), []);
    assert.deepEqual(PR.rankByCpu([rec(1, 'a', 5)], -3), []);
});

// ── formatCpuPercent ─────────────────────────────────────────────────────

test('formatCpuPercent: one decimal with a percent sign', () => {
    assert.equal(PR.formatCpuPercent(12.34), '12.3%');
    assert.equal(PR.formatCpuPercent(0), '0.0%');
    assert.equal(PR.formatCpuPercent(100), '100.0%');
});

test('formatCpuPercent: rounds to one decimal', () => {
    assert.equal(PR.formatCpuPercent(3.75), '3.8%');
    assert.equal(PR.formatCpuPercent(3.74), '3.7%');
});

test('formatCpuPercent: NaN / negative / undefined → "0.0%"', () => {
    assert.equal(PR.formatCpuPercent(NaN), '0.0%');
    assert.equal(PR.formatCpuPercent(-5), '0.0%');
    assert.equal(PR.formatCpuPercent(undefined), '0.0%');
});

// ── formatLoadAverages ───────────────────────────────────────────────────

test('formatLoadAverages: three values, two decimals, double-space separated', () => {
    assert.equal(PR.formatLoadAverages([0.42, 0.55, 0.61]), '0.42  0.55  0.61');
});

test('formatLoadAverages: pads a short or missing array with 0.00', () => {
    assert.equal(PR.formatLoadAverages([1.5]), '1.50  0.00  0.00');
    assert.equal(PR.formatLoadAverages([]), '0.00  0.00  0.00');
    assert.equal(PR.formatLoadAverages(undefined), '0.00  0.00  0.00');
});

test('formatLoadAverages: ignores extra entries beyond the first three', () => {
    assert.equal(PR.formatLoadAverages([0.1, 0.2, 0.3, 0.4, 0.5]), '0.10  0.20  0.30');
});
