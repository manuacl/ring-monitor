// Tests for MetricsCatalog.js — the static catalog + CSV helpers.

import { createRequire } from 'node:module';
import { test } from 'node:test';
import assert from 'node:assert/strict';

const require = createRequire(import.meta.url);
const Catalog = require('../contents/ui/MetricsCatalog.js');

test('METRIC_IDS contains the 5 known metrics in canonical order', () => {
    assert.deepEqual(Catalog.METRIC_IDS, ['cpu', 'ram', 'swap', 'gpu', 'disk']);
});

test('labelFor returns the abbreviation for known ids', () => {
    assert.equal(Catalog.labelFor('cpu'), 'CPU');
    assert.equal(Catalog.labelFor('ram'), 'RAM');
});

test('labelFor falls back to uppercase for unknown ids', () => {
    assert.equal(Catalog.labelFor('foo'), 'FOO');
});

test('sensorIdFor returns the ksysguard sensor id', () => {
    assert.equal(Catalog.sensorIdFor('cpu'), 'cpu/all/usage');
    assert.equal(Catalog.sensorIdFor('ram'), 'memory/physical/usedPercent');
});

test('sensorIdFor returns empty string for unknown ids', () => {
    assert.equal(Catalog.sensorIdFor('foo'), '');
});

test('parseCsv: empty / null / undefined → []', () => {
    assert.deepEqual(Catalog.parseCsv(''), []);
    assert.deepEqual(Catalog.parseCsv(null), []);
    assert.deepEqual(Catalog.parseCsv(undefined), []);
});

test('parseCsv: single value', () => {
    assert.deepEqual(Catalog.parseCsv('cpu'), ['cpu']);
});

test('parseCsv: multiple values', () => {
    assert.deepEqual(Catalog.parseCsv('cpu,ram,gpu'), ['cpu', 'ram', 'gpu']);
});

test('parseCsv: drops empty segments from trailing/leading/double commas', () => {
    assert.deepEqual(Catalog.parseCsv(',cpu,,ram,'), ['cpu', 'ram']);
});

test('filterByOrder: keeps only ids that are in `ids`, in `order` ordering', () => {
    // enabled set = {disk, cpu}, ordered by canonical → ['cpu', 'disk']
    assert.deepEqual(
        Catalog.filterByOrder(['disk', 'cpu'], Catalog.METRIC_IDS),
        ['cpu', 'disk']
    );
});

test('filterByOrder: respects custom order argument', () => {
    // User-defined order ['gpu', 'cpu', 'ram'] + enabled {cpu, gpu}
    assert.deepEqual(
        Catalog.filterByOrder(['cpu', 'gpu'], ['gpu', 'cpu', 'ram']),
        ['gpu', 'cpu']
    );
});

test('filterByOrder: ignores ids in the enabled set that are not in order', () => {
    assert.deepEqual(
        Catalog.filterByOrder(['cpu', 'unknown'], Catalog.METRIC_IDS),
        ['cpu']
    );
});

test('filterByOrder: empty enabled → []', () => {
    assert.deepEqual(Catalog.filterByOrder([], Catalog.METRIC_IDS), []);
});

test('toggleEnabled: enabling an id not yet present appends it', () => {
    assert.deepEqual(Catalog.toggleEnabled(['cpu', 'ram'], 'gpu', true),
                     ['cpu', 'ram', 'gpu']);
});

test('toggleEnabled: enabling an id already present is a no-op (re-appended at end)', () => {
    // The function strips duplicates then re-adds. The exact position is an
    // implementation detail; what matters is that the set is correct.
    assert.deepEqual(Catalog.toggleEnabled(['cpu', 'ram'], 'cpu', true),
                     ['ram', 'cpu']);
});

test('toggleEnabled: disabling removes the id', () => {
    assert.deepEqual(Catalog.toggleEnabled(['cpu', 'ram', 'gpu'], 'ram', false),
                     ['cpu', 'gpu']);
});

test('toggleEnabled: disabling an id that is not present is a no-op', () => {
    assert.deepEqual(Catalog.toggleEnabled(['cpu', 'ram'], 'foo', false),
                     ['cpu', 'ram']);
});

test('toggleEnabled: does not mutate the input', () => {
    const input = ['cpu', 'ram'];
    Catalog.toggleEnabled(input, 'gpu', true);
    assert.deepEqual(input, ['cpu', 'ram']);
});
