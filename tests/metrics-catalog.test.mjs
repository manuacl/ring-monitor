// Tests for MetricsCatalog.js — the static catalog + CSV helpers.

import { createRequire } from 'node:module';
import { test } from 'node:test';
import assert from 'node:assert/strict';

const require = createRequire(import.meta.url);
const Catalog = require('../contents/ui/core/MetricsCatalog.js');

test('METRIC_IDS contains all known metrics in canonical order', () => {
    // Temp variants sit next to their usage counterpart (adjacent in the strip).
    // battery is last: it is availability-gated and absent on desktops without one.
    assert.deepEqual(Catalog.METRIC_IDS, [
        'cpu',
        'cpuTemp',
        'ram',
        'swap',
        'gpu',
        'gpuTemp',
        'disk',
        'diskIo',
        'sensorTemp',
        'battery'
    ]);
});

test('labelFor: temperature variants get a "T" suffix; diskIo is distinct from DISKS', () => {
    assert.equal(Catalog.labelFor('cpuTemp'), 'CPU T');
    assert.equal(Catalog.labelFor('gpuTemp'), 'GPU T');
    assert.equal(Catalog.labelFor('disk'), 'DISKS');
    assert.equal(Catalog.labelFor('diskIo'), 'DISK IO');
    assert.equal(Catalog.labelFor('sensorTemp'), 'SENSOR');
});

test('sensorIdFor: temperature variants map to the same °C sensor as METRIC_TEMP_SENSOR_IDS', () => {
    assert.equal(Catalog.sensorIdFor('cpuTemp'), 'cpu/all/averageTemperature');
    assert.equal(Catalog.sensorIdFor('gpuTemp'), 'gpu/gpu1/temperature');
});

test('isTempMetric: cpuTemp, gpuTemp, and sensorTemp are temperature metrics', () => {
    assert.equal(Catalog.isTempMetric('cpuTemp'), true);
    assert.equal(Catalog.isTempMetric('gpuTemp'), true);
    assert.equal(Catalog.isTempMetric('sensorTemp'), true);
    assert.equal(Catalog.isTempMetric('cpu'), false);
    assert.equal(Catalog.isTempMetric('gpu'), false);
    assert.equal(Catalog.isTempMetric('ram'), false);
    assert.equal(Catalog.isTempMetric('foo'), false);
});

test('isRateMetric: exactly diskIo is a byte/s-rate metric (disjoint from temp)', () => {
    assert.equal(Catalog.isRateMetric('diskIo'), true);
    assert.equal(Catalog.isRateMetric('disk'), false);
    assert.equal(Catalog.isRateMetric('cpu'), false);
    assert.equal(Catalog.isRateMetric('foo'), false);
    assert.equal(Catalog.isTempMetric('diskIo'), false);
});

// ── isBatteryMetric ───────────────────────────────────────────────────

test('battery is in METRIC_IDS and is the last element', () => {
    assert.ok(Catalog.METRIC_IDS.includes('battery'));
    assert.equal(Catalog.METRIC_IDS[Catalog.METRIC_IDS.length - 1], 'battery');
});

test('labelFor: battery returns "BAT"', () => {
    assert.equal(Catalog.labelFor('battery'), 'BAT');
});

test('isBatteryMetric: true for "battery", false for other metric ids', () => {
    assert.equal(Catalog.isBatteryMetric('battery'), true);
    assert.equal(Catalog.isBatteryMetric('cpu'), false);
    assert.equal(Catalog.isBatteryMetric('diskIo'), false);
    assert.equal(Catalog.isBatteryMetric('ram'), false);
});

test('battery is not a rate metric and not a temp metric', () => {
    assert.equal(Catalog.isRateMetric('battery'), false);
    assert.equal(Catalog.isTempMetric('battery'), false);
});

test('battery has no ksysguard sensor id', () => {
    assert.equal(Catalog.sensorIdFor('battery'), '');
});

// ── mergeWithCatalog ──────────────────────────────────────────────────

test('mergeWithCatalog: appends missing catalog ids to a user CSV', () => {
    // Pre-0.4 user: cpu+ram+gpu order, no temp metrics yet.
    const result = Catalog.mergeWithCatalog(['cpu', 'ram', 'gpu']);
    assert.deepEqual(result, [
        'cpu',
        'ram',
        'gpu',
        'cpuTemp',
        'swap',
        'gpuTemp',
        'disk',
        'diskIo',
        'sensorTemp',
        'battery'
    ]);
});

test('mergeWithCatalog: preserves existing order when nothing is missing', () => {
    const input = [
        'gpu',
        'cpu',
        'ram',
        'cpuTemp',
        'swap',
        'gpuTemp',
        'disk',
        'diskIo',
        'sensorTemp',
        'battery'
    ];
    assert.deepEqual(Catalog.mergeWithCatalog(input), input);
});

test('mergeWithCatalog: empty input returns the full canonical order', () => {
    assert.deepEqual(Catalog.mergeWithCatalog([]), Catalog.METRIC_IDS);
});

test('mergeWithCatalog: does not duplicate ids the user already has', () => {
    const out = Catalog.mergeWithCatalog(['cpuTemp', 'cpu']);
    const count = out.filter(x => x === 'cpuTemp').length;
    assert.equal(count, 1);
});

// ── applyMergedTempMode ───────────────────────────────────────────────

test('applyMergedTempMode: no merge flag → list returned untouched (copy)', () => {
    const input = ['cpu', 'cpuTemp'];
    const out = Catalog.applyMergedTempMode(input, false, false);
    assert.deepEqual(out, input);
    assert.notEqual(out, input, 'must return a fresh array, not the input reference');
});

test('applyMergedTempMode: cpuTemp dropped when mergeCpuTemp + both cpu & cpuTemp enabled', () => {
    assert.deepEqual(
        Catalog.applyMergedTempMode(['cpu', 'cpuTemp', 'ram'], true, false),
        ['cpu', 'ram']
    );
});

test('applyMergedTempMode: merge flag does nothing when the base ring is not in the list', () => {
    // No cpu in the list → cpuTemp stays as its own full ring.
    assert.deepEqual(
        Catalog.applyMergedTempMode(['cpuTemp', 'ram'], true, false),
        ['cpuTemp', 'ram']
    );
});

test('applyMergedTempMode: both cpu and gpu can be merged simultaneously', () => {
    assert.deepEqual(
        Catalog.applyMergedTempMode(['cpu', 'cpuTemp', 'gpu', 'gpuTemp'], true, true),
        ['cpu', 'gpu']
    );
});

// ── isSplitForBase ────────────────────────────────────────────────────

test('isSplitForBase: cpu ring goes split when mergeCpuTemp + both enabled', () => {
    assert.equal(Catalog.isSplitForBase('cpu', ['cpu', 'cpuTemp'], true, false), true);
});

test('isSplitForBase: cpu ring stays single when cpuTemp is not enabled', () => {
    assert.equal(Catalog.isSplitForBase('cpu', ['cpu', 'ram'], true, false), false);
});

test('isSplitForBase: cpu and gpu are independent', () => {
    assert.equal(Catalog.isSplitForBase('gpu', ['cpu', 'cpuTemp'], true, true), false);
    assert.equal(Catalog.isSplitForBase('cpu', ['gpu', 'gpuTemp'], true, true), false);
});

test('isSplitForBase: non-cpu/gpu base ids never split', () => {
    assert.equal(Catalog.isSplitForBase('ram', ['ram', 'cpuTemp'], true, true), false);
    assert.equal(Catalog.isSplitForBase('disk', ['disk'], true, true), false);
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
    assert.deepEqual(Catalog.filterByOrder(['disk', 'cpu'], Catalog.METRIC_IDS), ['cpu', 'disk']);
});

test('filterByOrder: respects custom order argument', () => {
    assert.deepEqual(Catalog.filterByOrder(['cpu', 'gpu'], ['gpu', 'cpu', 'ram']), ['gpu', 'cpu']);
});

test('filterByOrder: ignores ids in the enabled set that are not in order', () => {
    assert.deepEqual(Catalog.filterByOrder(['cpu', 'unknown'], Catalog.METRIC_IDS), ['cpu']);
});

test('filterByOrder: empty enabled → []', () => {
    assert.deepEqual(Catalog.filterByOrder([], Catalog.METRIC_IDS), []);
});

// ── filterByAvailable: keep only available ids, in the enabled order ──

test('filterByAvailable: keeps only available ids, in the enabled order', () => {
    assert.deepEqual(Catalog.filterByAvailable(['cpu', 'gpu', 'ram', 'swap'], ['cpu', 'ram', 'disk']), ['cpu', 'ram']);
});

test('filterByAvailable: preserves the enabled order, not the available order', () => {
    assert.deepEqual(Catalog.filterByAvailable(['gpu', 'cpu', 'ram'], ['cpu', 'ram', 'gpu']), ['gpu', 'cpu', 'ram']);
});

test('filterByAvailable: everything available → enabled list returned untouched (copy)', () => {
    const input = ['cpu', 'ram'];
    const out = Catalog.filterByAvailable(input, ['cpu', 'ram', 'gpu']);
    assert.deepEqual(out, input);
    assert.notEqual(out, input, 'must return a fresh array, not the input reference');
});

test('filterByAvailable: nothing available → empty list', () => {
    assert.deepEqual(Catalog.filterByAvailable(['cpu', 'gpu'], []), []);
});

test('filterByAvailable: null/undefined available → pass-through copy (availability unknown)', () => {
    // Warm-up / pre-surface host: show configured rings, don't blank the widget.
    const input = ['cpu', 'gpu', 'swap'];
    assert.deepEqual(Catalog.filterByAvailable(input, null), input);
    assert.deepEqual(Catalog.filterByAvailable(input, undefined), input);
    assert.notEqual(Catalog.filterByAvailable(input, null), input, 'must return a fresh array');
});

test('filterByAvailable: empty enabled → []', () => {
    assert.deepEqual(Catalog.filterByAvailable([], ['cpu', 'ram']), []);
});

// ── availableMetricsFrom: emit truthy ids of a {id:bool} map in METRIC_IDS order ──

test('availableMetricsFrom: emits truthy ids in canonical METRIC_IDS order', () => {
    // Flags given out of order → output still canonical.
    assert.deepEqual(Catalog.availableMetricsFrom({ disk: true, cpu: true, ram: true }), ['cpu', 'ram', 'disk']);
});

test('availableMetricsFrom: drops falsy flags (false / undefined / missing)', () => {
    assert.deepEqual(
        Catalog.availableMetricsFrom({ cpu: true, cpuTemp: false, ram: true, gpu: undefined }), ['cpu', 'ram']
    );
});

test('availableMetricsFrom: full host → the whole catalog in order', () => {
    const all = {};
    for (const id of Catalog.METRIC_IDS) all[id] = true;
    assert.deepEqual(Catalog.availableMetricsFrom(all), Catalog.METRIC_IDS);
});

test('availableMetricsFrom: ignores ids that are not in the catalog', () => {
    assert.deepEqual(Catalog.availableMetricsFrom({ cpu: true, bogus: true }), ['cpu']);
});

test('availableMetricsFrom: empty / null flags → []', () => {
    assert.deepEqual(Catalog.availableMetricsFrom({}), []);
    assert.deepEqual(Catalog.availableMetricsFrom(null), []);
    assert.deepEqual(Catalog.availableMetricsFrom(undefined), []);
});

test('toggleEnabled: enabling an id not yet present appends it', () => {
    assert.deepEqual(Catalog.toggleEnabled(['cpu', 'ram'], 'gpu', true),
                     ['cpu', 'ram', 'gpu']);
});

test('toggleEnabled: enabling an id already present is a no-op (re-appended at end)', () => {
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

