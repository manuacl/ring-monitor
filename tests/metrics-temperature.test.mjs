import { createRequire } from 'node:module';
import { test } from 'node:test';
import assert from 'node:assert/strict';

const require = createRequire(import.meta.url);
const Catalog = require('../contents/ui/core/MetricsCatalog.js');

// Temperature and sensor-value tests for MetricsCatalog.js.

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
