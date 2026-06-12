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

test('rankByCpu: carries rssKb through when present (RAM-tooltip forward hook)', () => {
    const out = PR.rankByCpu([rec(1, 'a', 5, 123456)]);
    assert.equal(out[0].rssKb, 123456);
});

test('rankByCpu: omits rssKb when absent (preserves not-sampled vs 0 KB)', () => {
    // v1 producers never set rssKb; it must stay undefined, NOT be fabricated
    // to 0 — else a future rankByMemory can't tell unsampled from genuine 0 KB.
    const out = PR.rankByCpu([{ pid: 1, name: 'a', cpuPercent: 5 }]);
    assert.equal('rssKb' in out[0], false);
    assert.equal(out[0].rssKb, undefined);
});

test('rankByCpu: coerces a string pid to a number so the tiebreak stays numeric', () => {
    // The Plasma ProcessDataModel Value role isn't guaranteed numeric; a string
    // pid must not turn the a.pid - b.pid tiebreak into NaN (unstable sort).
    const out = PR.rankByCpu([rec('9', 'late', 10), rec('2', 'early', 10), rec('5', 'mid', 10)]);
    assert.deepEqual(out.map(r => r.pid), [2, 5, 9]);
    assert.equal(typeof out[0].pid, 'number');
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

// ── rankByMemory ─────────────────────────────────────────────────────────

test('rankByMemory: sorts by rssKb descending', () => {
    const out = PR.rankByMemory([rec(1, 'a', 0, 500), rec(2, 'b', 0, 8000), rec(3, 'c', 0, 1200)]);
    assert.deepEqual(out.map(r => r.name), ['b', 'c', 'a']);
});

test('rankByMemory: caps to the given limit', () => {
    const input = [rec(1, 'a', 0, 100), rec(2, 'b', 0, 200), rec(3, 'c', 0, 300), rec(4, 'd', 0, 400)];
    assert.equal(PR.rankByMemory(input, 2).length, 2);
    assert.deepEqual(PR.rankByMemory(input, 2).map(r => r.name), ['d', 'c']);
});

test('rankByMemory: defaults to DEFAULT_LIMIT (20) when limit omitted', () => {
    const input = [];
    for (let i = 0; i < 50; i++)
        input.push(rec(i, 'p' + i, 0, i * 100));
    assert.equal(PR.rankByMemory(input).length, 20);
});

test('rankByMemory: ties break by pid ascending (deterministic, no flicker)', () => {
    const out = PR.rankByMemory([rec(9, 'late', 0, 1000), rec(2, 'early', 0, 1000), rec(5, 'mid', 0, 1000)]);
    assert.deepEqual(out.map(r => r.pid), [2, 5, 9]);
});

test('rankByMemory: coerces a string pid to a number so the tiebreak stays numeric', () => {
    // Mirror of the rankByCpu guard: the Plasma ProcessDataModel Value role
    // isn't guaranteed numeric, and both rankers share _cleanRecords — pin the
    // memory path too so a future split of the cleaning code can't regress it.
    const out = PR.rankByMemory([rec('9', 'late', 0, 1000), rec('2', 'early', 0, 1000), rec('5', 'mid', 0, 1000)]);
    assert.deepEqual(out.map(r => r.pid), [2, 5, 9]);
    assert.equal(typeof out[0].pid, 'number');
});

test('rankByMemory: absent rssKb ranks as 0 (kept, not dropped)', () => {
    // Records without rssKb are still valid; they rank below those with it.
    const out = PR.rankByMemory([
        { pid: 1, name: 'norss', cpuPercent: 0 },
        rec(2, 'hasrss', 0, 512),
    ]);
    assert.equal(out.length, 2);
    assert.equal(out[0].name, 'hasrss');
    assert.equal(out[1].name, 'norss');
});

test('rankByMemory: does not mutate the input array', () => {
    const input = [rec(1, 'a', 0, 1000), rec(2, 'b', 0, 500)];
    const snapshot = input.map(r => r.pid);
    PR.rankByMemory(input);
    assert.deepEqual(input.map(r => r.pid), snapshot);
});

test('rankByMemory: drops records with no pid', () => {
    const out = PR.rankByMemory([rec(1, 'a', 0, 100), { name: 'nopid', rssKb: 999 }, { pid: null, rssKb: 800 }]);
    assert.deepEqual(out.map(r => r.name), ['a']);
});

test('rankByMemory: non-array / non-positive limit → empty array', () => {
    assert.deepEqual(PR.rankByMemory(null), []);
    assert.deepEqual(PR.rankByMemory(undefined), []);
    assert.deepEqual(PR.rankByMemory([rec(1, 'a', 0, 100)], 0), []);
    assert.deepEqual(PR.rankByMemory([rec(1, 'a', 0, 100)], -1), []);
});

test('rankByMemory: cleaned records carry cpuPercent and conditional rssKb', () => {
    const out = PR.rankByMemory([rec(1, 'a', 42.5, 1024)]);
    assert.equal(out[0].cpuPercent, 42.5);
    assert.equal(out[0].rssKb, 1024);
});

// ── formatMemory ─────────────────────────────────────────────────────────

test('formatMemory: sub-1024 KiB → integer KiB', () => {
    assert.equal(PR.formatMemory(836), '836 KiB');
    assert.equal(PR.formatMemory(0), '0 KiB');
    assert.equal(PR.formatMemory(1023), '1023 KiB');
});

test('formatMemory: exact 1024 KiB boundary → MiB', () => {
    // 1024 KiB == 1.0 MiB; the boundary itself uses the MiB branch.
    assert.equal(PR.formatMemory(1024), '1.0 MiB');
});

test('formatMemory: KiB in MiB range → one decimal MiB', () => {
    assert.equal(PR.formatMemory(9830), '9.6 MiB');  // 9830/1024 ≈ 9.599
    assert.equal(PR.formatMemory(1024 * 512), '512.0 MiB');
});

test('formatMemory: exact 1024 MiB boundary → GiB', () => {
    assert.equal(PR.formatMemory(1024 * 1024), '1.0 GiB');
});

test('formatMemory: KiB in GiB range → one decimal GiB', () => {
    assert.equal(PR.formatMemory(1024 * 1024 * 1.2), '1.2 GiB');
});

test('formatMemory: undefined / NaN / negative → "0 KiB"', () => {
    assert.equal(PR.formatMemory(undefined), '0 KiB');
    assert.equal(PR.formatMemory(NaN), '0 KiB');
    assert.equal(PR.formatMemory(-500), '0 KiB');
});

// ── formatMemPercent ─────────────────────────────────────────────────────

test('formatMemPercent: normal case, one decimal percent', () => {
    // 1024 / 16384 * 100 = 6.25 → "6.3%" (toFixed rounds)
    assert.equal(PR.formatMemPercent(1024, 16384), '6.3%');
    assert.equal(PR.formatMemPercent(0, 16384), '0.0%');
});

test('formatMemPercent: totalKb zero or negative → "0.0%"', () => {
    assert.equal(PR.formatMemPercent(1000, 0), '0.0%');
    assert.equal(PR.formatMemPercent(1000, -1), '0.0%');
});

test('formatMemPercent: totalKb NaN / undefined → "0.0%"', () => {
    assert.equal(PR.formatMemPercent(1000, NaN), '0.0%');
    assert.equal(PR.formatMemPercent(1000, undefined), '0.0%');
});

test('formatMemPercent: clamps at 100% (rss spike above total)', () => {
    assert.equal(PR.formatMemPercent(20000, 16384), '100.0%');
});

test('formatMemPercent: rssKb NaN / undefined / negative → "0.0%"', () => {
    assert.equal(PR.formatMemPercent(undefined, 16384), '0.0%');
    assert.equal(PR.formatMemPercent(NaN, 16384), '0.0%');
    assert.equal(PR.formatMemPercent(-100, 16384), '0.0%');
});
