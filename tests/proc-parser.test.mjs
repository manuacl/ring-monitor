// Tests for ProcParser.js — the standalone /proc parsers for the CPU-ring
// process tooltip (issue #69). Pure; ranking/formatting is exercised
// separately in process-ranking.test.mjs.

import { createRequire } from 'node:module';
import { test } from 'node:test';
import assert from 'node:assert/strict';

const require = createRequire(import.meta.url);
const P = require('../contents/ui/platforms/standalone/ProcParser.js');
const Stat = require('../contents/ui/platforms/standalone/ProcStatParser.js');

// A /proc/<pid>/stat line with the fields we read at their real offsets.
// After "(comm)" the tokens are: state ppid pgrp session tty_nr tpgid flags
// minflt cminflt majflt cmajflt utime stime ... — so utime is the 12th token
// after comm, stime the 13th, and rss (field 24) is the 22nd (index [21]).
const stat = (pid, comm, utime, stime, rssPages = 512) =>
    `${pid} (${comm}) S 1 ${pid} ${pid} 0 -1 4194304 999 0 0 0 ${utime} ${stime} 0 0 20 0 12 0 99999 0 ${rssPages} 0 0 0 0 0 0 0 0 0 0 0 0 17 0 0 0`;

// ── parsePidStat ──────────────────────────────────────────────────────────

test('parsePidStat: extracts pid, name, jiffies = utime + stime', () => {
    const r = P.parsePidStat(stat(42, 'bash', 100, 50));
    assert.deepEqual(r, { pid: 42, name: 'bash', jiffies: 150, rssPages: 512 });
});

test('parsePidStat: comm with spaces (split on the LAST paren)', () => {
    const r = P.parsePidStat(stat(1234, 'Web Content', 4500, 1200));
    assert.equal(r.name, 'Web Content');
    assert.equal(r.jiffies, 5700);
});

test('parsePidStat: comm containing parens (e.g. ((sd-pam)))', () => {
    const r = P.parsePidStat(stat(7, '(sd-pam)', 3, 4));
    assert.equal(r.name, '(sd-pam)');
    assert.equal(r.pid, 7);
    assert.equal(r.jiffies, 7);
});

test('parsePidStat: no parens / non-string / empty → null', () => {
    assert.equal(P.parsePidStat('1234 bash S 1 2 3'), null);
    assert.equal(P.parsePidStat(''), null);
    assert.equal(P.parsePidStat(null), null);
    assert.equal(P.parsePidStat(undefined), null);
});

test('parsePidStat: truncated line (no utime/stime) → null', () => {
    assert.equal(P.parsePidStat('99 (short) S 1 99'), null);
});

test('parsePidStat: rssPages parsed from field 24 of the stat line', () => {
    const r = P.parsePidStat(stat(100, 'firefox', 200, 100, 4096));
    assert.equal(r.rssPages, 4096);
    assert.equal(r.jiffies, 300);
});

test('parsePidStat: comm with spaces still parses rssPages correctly', () => {
    const r = P.parsePidStat(stat(55, 'Web Content', 10, 5, 1024));
    assert.equal(r.name, 'Web Content');
    assert.equal(r.rssPages, 1024);
});

test('parsePidStat: comm with nested parens still parses rssPages correctly', () => {
    const r = P.parsePidStat(stat(7, '(sd-pam)', 3, 4, 256));
    assert.equal(r.name, '(sd-pam)');
    assert.equal(r.rssPages, 256);
});

test('parsePidStat: missing rss field → rssPages 0, record otherwise intact', () => {
    // A stat line truncated before field 24 must still yield a valid record
    // (utime/stime are present); a broken rss must not hide the process from
    // the CPU ranking.
    const truncated = '42 (bash) S 1 42 42 0 -1 4194304 0 0 0 0 100 50';
    const r = P.parsePidStat(truncated);
    assert.equal(r.rssPages, 0);
    assert.equal(r.jiffies, 150);
    assert.equal(r.pid, 42);
});

test('parsePidStat: garbage rss field → rssPages 0, record otherwise intact', () => {
    // Non-numeric rss (e.g. a kernel that extends the field with a suffix)
    // must degrade gracefully to 0 without dropping the process.
    const line = '10 (kworker) S 0 0 0 0 -1 4096 0 0 0 0 5 3 0 0 20 0 1 0 999 0 xyz 0 0 0 0 0 0 0 0 0 0 0 0 17 0 0 0';
    const r = P.parsePidStat(line);
    assert.equal(r.rssPages, 0);
    assert.equal(r.jiffies, 8);
});

test('parsePidStat: negative rss field → rssPages 0, record otherwise intact', () => {
    // The kernel should never emit a negative rss, but guard it anyway
    // to keep the tooltip free of negative KiB values.
    const line = '10 (proc) S 0 0 0 0 -1 4096 0 0 0 0 5 3 0 0 20 0 1 0 999 0 -1 0 0 0 0 0 0 0 0 0 0 0 0 17 0 0 0';
    const r = P.parsePidStat(line);
    assert.equal(r.rssPages, 0);
    assert.equal(r.jiffies, 8);
});

// ── parseLoadAvg ────────────────────────────────────────────────────────────

test('parseLoadAvg: first three tokens of /proc/loadavg', () => {
    assert.deepEqual(P.parseLoadAvg('0.42 0.55 0.61 1/938 12345\n'), [0.42, 0.55, 0.61]);
});

test('parseLoadAvg: partial / empty / non-string → padded with 0', () => {
    assert.deepEqual(P.parseLoadAvg('1.5'), [1.5, 0, 0]);
    assert.deepEqual(P.parseLoadAvg(''), [0, 0, 0]);
    assert.deepEqual(P.parseLoadAvg(null), [0, 0, 0]);
});

// ── sumJiffies ──────────────────────────────────────────────────────────────

test('sumJiffies: sums the aggregate-cpu field array', () => {
    assert.equal(P.sumJiffies([3357, 0, 4313, 1362393, 234, 0, 0, 0, 0, 0]), 1370297);
});

test('sumJiffies: non-array → 0; non-finite entries ignored', () => {
    assert.equal(P.sumJiffies(null), 0);
    assert.equal(P.sumJiffies([10, NaN, 5, undefined]), 15);
});

// No-desync guard: sumJiffies is a deliberate copy of the field-summing logic
// in ProcStatParser.percentFromSample (the dual-load convention forbids a .js
// importing a sibling .js). If the two ever diverge — a new /proc/stat column
// summed in one but not the other — the standalone CPU% would silently disagree
// with itself. ProcStatParser doesn't export its internal total, so tie them via
// percentFromSample: the usage it computes from its OWN inline sum must equal the
// usage derived from sumJiffies-based totals over the same sample pair.
test('sumJiffies matches ProcStatParser internal total (dual-load no-desync)', () => {
    const prev = Stat.parseProcStat('cpu  100 0 100 1000 0 0 0 0 0 0\n').all;
    const cur = Stat.parseProcStat('cpu  150 0 150 1200 50 0 0 0 0 0\n').all;
    const dTotal = P.sumJiffies(cur) - P.sumJiffies(prev);
    const dIdle = (cur[3] + cur[4]) - (prev[3] + prev[4]);
    const expected = (1 - dIdle / dTotal) * 100;
    assert.ok(Math.abs(Stat.percentFromSample(prev, cur) - expected) < 1e-9,
        'sumJiffies total must equal the total ProcStatParser sums internally');
});

// ── computePercents ──────────────────────────────────────────────────────────

test('computePercents: pct = process jiffy delta / total jiffy delta * 100', () => {
    const prev = { 42: { pid: 42, name: 'bash', jiffies: 100 } };
    const cur = { 42: { pid: 42, name: 'bash', jiffies: 175 } };
    const out = P.computePercents(prev, cur, 300);
    assert.deepEqual(out, [{ pid: 42, name: 'bash', cpuPercent: 25 }]);
});

test('computePercents: a pid only in cur (no prior sample) is skipped', () => {
    const prev = { 1: { pid: 1, name: 'a', jiffies: 10 } };
    const cur = {
        1: { pid: 1, name: 'a', jiffies: 20 },
        2: { pid: 2, name: 'fresh', jiffies: 999 },
    };
    const out = P.computePercents(prev, cur, 100);
    assert.deepEqual(out.map(r => r.pid), [1]);
});

test('computePercents: negative delta (pid reuse / reset) clamps to 0', () => {
    const prev = { 5: { pid: 5, name: 'x', jiffies: 500 } };
    const cur = { 5: { pid: 5, name: 'x', jiffies: 100 } };
    assert.equal(P.computePercents(prev, cur, 1000)[0].cpuPercent, 0);
});

test('computePercents: clamps above 100', () => {
    const prev = { 5: { pid: 5, name: 'x', jiffies: 0 } };
    const cur = { 5: { pid: 5, name: 'x', jiffies: 5000 } };
    assert.equal(P.computePercents(prev, cur, 100)[0].cpuPercent, 100);
});

test('computePercents: null maps / non-positive total → empty', () => {
    const m = { 1: { pid: 1, name: 'a', jiffies: 5 } };
    assert.deepEqual(P.computePercents(null, m, 100), []);
    assert.deepEqual(P.computePercents(m, null, 100), []);
    assert.deepEqual(P.computePercents(m, m, 0), []);
    assert.deepEqual(P.computePercents(m, m, -50), []);
});
