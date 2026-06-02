// Tests for MetricsCatalog.js — the static catalog + CSV helpers.

import { createRequire } from 'node:module';
import { test } from 'node:test';
import assert from 'node:assert/strict';

const require = createRequire(import.meta.url);
const Catalog = require('../contents/ui/core/MetricsCatalog.js');

test('METRIC_IDS contains all known metrics in canonical order', () => {
    // Temp variants sit next to their usage counterpart (adjacent in the strip).
    assert.deepEqual(Catalog.METRIC_IDS, ['cpu', 'cpuTemp', 'ram', 'swap', 'gpu', 'gpuTemp', 'disk', 'diskIo']);
});

test('labelFor: temperature variants get a "T" suffix; diskIo is distinct from DISKS', () => {
    assert.equal(Catalog.labelFor('cpuTemp'), 'CPU T');
    assert.equal(Catalog.labelFor('gpuTemp'), 'GPU T');
    assert.equal(Catalog.labelFor('disk'), 'DISKS');
    assert.equal(Catalog.labelFor('diskIo'), 'DISK IO');
});

test('sensorIdFor: temperature variants map to the same °C sensor as METRIC_TEMP_SENSOR_IDS', () => {
    assert.equal(Catalog.sensorIdFor('cpuTemp'), 'cpu/all/averageTemperature');
    assert.equal(Catalog.sensorIdFor('gpuTemp'), 'gpu/gpu1/temperature');
});

test('isTempMetric: exactly cpuTemp and gpuTemp are temperature metrics', () => {
    assert.equal(Catalog.isTempMetric('cpuTemp'), true);
    assert.equal(Catalog.isTempMetric('gpuTemp'), true);
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

// ── mergeWithCatalog ──────────────────────────────────────────────────

test('mergeWithCatalog: appends missing catalog ids to a user CSV', () => {
    // Pre-0.4 user: cpu+ram+gpu order, no temp metrics yet.
    const result = Catalog.mergeWithCatalog(['cpu', 'ram', 'gpu']);
    assert.deepEqual(result, ['cpu', 'ram', 'gpu', 'cpuTemp', 'swap', 'gpuTemp', 'disk', 'diskIo']);
});

test('mergeWithCatalog: preserves existing order when nothing is missing', () => {
    const input = ['gpu', 'cpu', 'ram', 'cpuTemp', 'swap', 'gpuTemp', 'disk', 'diskIo'];
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

// ── classifyDiscoveredIds: filter + natural sort ──────────────────────

test('classifyDiscoveredIds: empty input → empty buckets', () => {
    const out = Catalog.classifyDiscoveredIds([]);
    assert.deepEqual(out, { coreUsageIds: [], gpuTempIds: [], gpuUsageIds: [], diskPartitionUsageIds: [] });
});

test('classifyDiscoveredIds: routes ids into the right buckets', () => {
    const out = Catalog.classifyDiscoveredIds([
        "cpu/cpu0/usage",
        "cpu/cpu1/usage",
        "cpu/cpu0/temperature",          // per-core temp — not a bucket
        "cpu/all/usage",                  // aggregate — not a bucket
        "cpu/all/averageTemperature",
        "gpu/gpu0/temperature",
        "gpu/gpu1/temperature",
        "gpu/gpu0/usage",
        "gpu/all/usage",
        "memory/physical/usedPercent",
        "disk/all/usedPercent",
        "lmsensors/nvme-pci-0400/temp1"
    ]);
    assert.deepEqual(out.coreUsageIds, ["cpu/cpu0/usage", "cpu/cpu1/usage"]);
    assert.deepEqual(out.gpuTempIds, ["gpu/gpu0/temperature", "gpu/gpu1/temperature"]);
    assert.deepEqual(out.gpuUsageIds, ["gpu/gpu0/usage"]);
    assert.deepEqual(out.diskPartitionUsageIds, []);  // disk/all is excluded; no per-fs ids here
});

test('classifyDiscoveredIds: buckets per-filesystem disk usedPercent, excludes disk/all', () => {
    // ksysguard keys mounted filesystems by UUID, emitting usedPercent only
    // for them (physical disks have read/write, no usedPercent). The disk/all
    // aggregate stays a static sensor → must NOT land in the per-partition bucket.
    const out = Catalog.classifyDiscoveredIds([
        "disk/6286e04e-b217-43bf-834f-d6a054ac4376/usedPercent",
        "disk/0af30554-3219-445a-b6f7-e02910a91469/usedPercent",
        "disk/all/usedPercent",          // aggregate — excluded
        "disk/sda/read",                  // physical disk — no usedPercent
        "disk/6286e04e-b217-43bf-834f-d6a054ac4376/free"  // not usedPercent
    ]);
    assert.deepEqual(out.diskPartitionUsageIds, [
        "disk/0af30554-3219-445a-b6f7-e02910a91469/usedPercent",
        "disk/6286e04e-b217-43bf-834f-d6a054ac4376/usedPercent"
    ]);
});

test('classifyDiscoveredIds: ignores the regex subscription node behind disk/all', () => {
    // SCENARIO: the SensorTreeModel surfaces the regex *matcher* node behind
    // disk/all — `disk/(?!all).*/usedPercent`, not a real filesystem. A [^/]+
    // middle segment matched it → phantom checkbox; the id-char restriction
    // ([A-Za-z0-9_-]) excludes it while keeping UUID partitions.
    const out = Catalog.classifyDiscoveredIds([
        "disk/(?!all).*/usedPercent",
        "disk/6286e04e-b217-43bf-834f-d6a054ac4376/usedPercent"
    ]);
    assert.deepEqual(out.diskPartitionUsageIds, [
        "disk/6286e04e-b217-43bf-834f-d6a054ac4376/usedPercent"
    ]);
});

test('classifyDiscoveredIds: natural sort puts cpu10 after cpu9', () => {
    // Default JS string sort would produce ["…cpu1…", "…cpu10…", "…cpu2…"].
    const input = [
        "cpu/cpu10/usage", "cpu/cpu2/usage", "cpu/cpu1/usage",
        "cpu/cpu0/usage", "cpu/cpu9/usage", "cpu/cpu11/usage"
    ];
    const out = Catalog.classifyDiscoveredIds(input);
    assert.deepEqual(out.coreUsageIds, [
        "cpu/cpu0/usage", "cpu/cpu1/usage", "cpu/cpu2/usage",
        "cpu/cpu9/usage", "cpu/cpu10/usage", "cpu/cpu11/usage"
    ]);
});

test('classifyDiscoveredIds: gpu indices sort numerically too', () => {
    const out = Catalog.classifyDiscoveredIds([
        "gpu/gpu10/temperature", "gpu/gpu1/temperature", "gpu/gpu0/temperature"
    ]);
    assert.deepEqual(out.gpuTempIds, [
        "gpu/gpu0/temperature", "gpu/gpu1/temperature", "gpu/gpu10/temperature"
    ]);
});

test('classifyDiscoveredIds: ignores ids that do not match any bucket pattern', () => {
    const out = Catalog.classifyDiscoveredIds([
        "cpu/cpu0/frequency",            // not /usage
        "cpu/cpufan/usage",              // not /cpuN/usage
        "gpu/all/temperature",           // not /gpuN/
        "garbage",
        ""
    ]);
    assert.deepEqual(out, { coreUsageIds: [], gpuTempIds: [], gpuUsageIds: [], diskPartitionUsageIds: [] });
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

// ── filterByAvailable: keep only available ids, in the enabled order ──

test('filterByAvailable: keeps only available ids, in the enabled order', () => {
    assert.deepEqual(
        Catalog.filterByAvailable(['cpu', 'gpu', 'ram', 'swap'], ['cpu', 'ram', 'disk']),
        ['cpu', 'ram']
    );
});

test('filterByAvailable: preserves the enabled order, not the available order', () => {
    assert.deepEqual(
        Catalog.filterByAvailable(['gpu', 'cpu', 'ram'], ['cpu', 'ram', 'gpu']),
        ['gpu', 'cpu', 'ram']
    );
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
    assert.deepEqual(
        Catalog.availableMetricsFrom({ disk: true, cpu: true, ram: true }),
        ['cpu', 'ram', 'disk']
    );
});

test('availableMetricsFrom: drops falsy flags (false / undefined / missing)', () => {
    assert.deepEqual(
        Catalog.availableMetricsFrom({ cpu: true, cpuTemp: false, ram: true, gpu: undefined }),
        ['cpu', 'ram']
    );
});

test('availableMetricsFrom: full host → the whole catalog in order', () => {
    const all = {};
    for (const id of Catalog.METRIC_IDS) all[id] = true;
    assert.deepEqual(Catalog.availableMetricsFrom(all), Catalog.METRIC_IDS);
});

test('availableMetricsFrom: ignores ids that are not in the catalog', () => {
    assert.deepEqual(
        Catalog.availableMetricsFrom({ cpu: true, bogus: true }),
        ['cpu']
    );
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

// ── valueFromSensorMap — read sensor value defensively ──────────────────
// `Sensor.value` is undefined pre-first-sample, NaN on a bad id, map may be null.

test('valueFromSensorMap: returns sensor value for a known id', () => {
    const map = { cpu: { value: 42 }, ram: { value: 17 } };
    assert.equal(Catalog.valueFromSensorMap(map, 'cpu'), 42);
    assert.equal(Catalog.valueFromSensorMap(map, 'ram'), 17);
});

test('valueFromSensorMap: returns 0 for an unknown id', () => {
    const map = { cpu: { value: 42 } };
    assert.equal(Catalog.valueFromSensorMap(map, 'gpu'), 0);
});

test('valueFromSensorMap: returns 0 when the sensor has no value yet', () => {
    assert.equal(Catalog.valueFromSensorMap({ cpu: {} }, 'cpu'), 0);
    assert.equal(Catalog.valueFromSensorMap({ cpu: { value: undefined } }, 'cpu'), 0);
    assert.equal(Catalog.valueFromSensorMap({ cpu: { value: null } }, 'cpu'), 0);
});

test('valueFromSensorMap: returns 0 for NaN value (bad sensor id)', () => {
    assert.equal(Catalog.valueFromSensorMap({ cpu: { value: NaN } }, 'cpu'), 0);
});

test('valueFromSensorMap: returns 0 when the sensorMap itself is null/undefined', () => {
    assert.equal(Catalog.valueFromSensorMap(null, 'cpu'), 0);
    assert.equal(Catalog.valueFromSensorMap(undefined, 'cpu'), 0);
});

test('valueFromSensorMap: preserves 0 as a valid sensor reading', () => {
    // 0 is a legitimate value (idle CPU). Don't coerce it via `||` etc.
    assert.equal(Catalog.valueFromSensorMap({ cpu: { value: 0 } }, 'cpu'), 0);
});

// ── Temperature sensors + °C → % mapping ────────────────────────────────
// cpu (core-averaged) + gpu (per-GPU — ksysguard has no `gpu/all` aggregate).

test('tempSensorIdFor: known ids return their ksysguard temperature sensor', () => {
    assert.equal(Catalog.tempSensorIdFor('cpu'), 'cpu/all/averageTemperature');
    assert.equal(Catalog.tempSensorIdFor('gpu'), 'gpu/gpu1/temperature');
});

test('tempSensorIdFor: unknown / non-temperature ids return ""', () => {
    assert.equal(Catalog.tempSensorIdFor('ram'), '');
    assert.equal(Catalog.tempSensorIdFor('foo'), '');
});

test('tempToPercent: default range 30-90°C maps endpoints to 0/100', () => {
    assert.equal(Catalog.tempToPercent(30), 0);
    assert.equal(Catalog.tempToPercent(90), 100);
});

test('tempToPercent: midpoint of default range → 50%', () => {
    assert.equal(Catalog.tempToPercent(60), 50);
});

test('tempToPercent: clamps below min and above max', () => {
    assert.equal(Catalog.tempToPercent(0), 0);
    assert.equal(Catalog.tempToPercent(150), 100);
});

test('tempToPercent: respects custom min/max', () => {
    // 20-100°C range, value 60 → (60-20)/(100-20)*100 = 50
    assert.equal(Catalog.tempToPercent(60, 20, 100), 50);
    assert.equal(Catalog.tempToPercent(20, 20, 100), 0);
    assert.equal(Catalog.tempToPercent(100, 20, 100), 100);
});

test('tempToPercent: non-finite input → 0', () => {
    assert.equal(Catalog.tempToPercent(NaN), 0);
    assert.equal(Catalog.tempToPercent(undefined), 0);
    assert.equal(Catalog.tempToPercent(Infinity), 0);
    assert.equal(Catalog.tempToPercent(-Infinity), 0);
});

test('tempToPercent: degenerate range (max <= min) → 0', () => {
    assert.equal(Catalog.tempToPercent(50, 60, 60), 0);
    assert.equal(Catalog.tempToPercent(50, 90, 30), 0);
});

// ── Display unit resolution + °C → °F conversion ────────────────────────
// Sensor stays Celsius; only the *displayed* number converts (last hop, MainContent).

test('MEASUREMENT_* constants match Qt QLocale.MeasurementSystem enum', () => {
    assert.equal(Catalog.MEASUREMENT_METRIC, 0);
    assert.equal(Catalog.MEASUREMENT_IMPERIAL_US, 1);
    assert.equal(Catalog.MEASUREMENT_IMPERIAL_UK, 2);
});

test('resolveTempMode: explicit user choice wins over the system locale', () => {
    assert.equal(Catalog.resolveTempMode('celsius', Catalog.MEASUREMENT_IMPERIAL_US), 'celsius');
    assert.equal(Catalog.resolveTempMode('fahrenheit', Catalog.MEASUREMENT_METRIC), 'fahrenheit');
});

test('resolveTempMode: "auto" follows MEASUREMENT_IMPERIAL_US → fahrenheit', () => {
    assert.equal(Catalog.resolveTempMode('auto', Catalog.MEASUREMENT_IMPERIAL_US), 'fahrenheit');
});

test('resolveTempMode: "auto" falls back to celsius for metric and Imperial-UK', () => {
    // UK has been metric for temperature since ~1965 — only Imperial-US
    // expects °F.
    assert.equal(Catalog.resolveTempMode('auto', Catalog.MEASUREMENT_METRIC), 'celsius');
    assert.equal(Catalog.resolveTempMode('auto', Catalog.MEASUREMENT_IMPERIAL_UK), 'celsius');
});

test('resolveTempMode: unknown userMode is treated like "auto"', () => {
    // Defensive — if a future schema migration leaves a stale value
    // in cfg_tempUnit, we still show *something* sensible.
    assert.equal(Catalog.resolveTempMode('kelvin', Catalog.MEASUREMENT_IMPERIAL_US), 'fahrenheit');
    assert.equal(Catalog.resolveTempMode('', Catalog.MEASUREMENT_METRIC), 'celsius');
});

test('convertTemp: celsius mode passes the value through with °C unit', () => {
    assert.deepEqual(Catalog.convertTemp(0, 'celsius'), { value: 0, unit: '°C' });
    assert.deepEqual(Catalog.convertTemp(45, 'celsius'), { value: 45, unit: '°C' });
});

test('convertTemp: fahrenheit mode applies the standard formula', () => {
    // 0°C → 32°F, 100°C → 212°F, 60°C → 140°F
    assert.deepEqual(Catalog.convertTemp(0, 'fahrenheit'), { value: 32, unit: '°F' });
    assert.deepEqual(Catalog.convertTemp(100, 'fahrenheit'), { value: 212, unit: '°F' });
    assert.deepEqual(Catalog.convertTemp(60, 'fahrenheit'), { value: 140, unit: '°F' });
});

test('convertTemp: non-finite input falls back to 0 in the requested unit', () => {
    assert.deepEqual(Catalog.convertTemp(NaN, 'celsius'), { value: 0, unit: '°C' });
    assert.deepEqual(Catalog.convertTemp(undefined, 'fahrenheit'), { value: 0, unit: '°F' });
});
