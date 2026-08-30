// Tests for MetricsCatalog.classifyDiscoveredIds — the SensorTreeModel
// id classifier (split out of metrics-catalog.test.mjs for the 500-line cap).

import { createRequire } from 'node:module';
import { test } from 'node:test';
import assert from 'node:assert/strict';

const require = createRequire(import.meta.url);
const Catalog = require('../contents/ui/core/MetricsCatalog.js');

// ── classifyDiscoveredIds: filter + natural sort ──────────────────────

test('classifyDiscoveredIds: empty input → empty buckets', () => {
    const out = Catalog.classifyDiscoveredIds([]);
    assert.deepEqual(out, { coreUsageIds: [], gpuTempIds: [], gpuUsageIds: [], diskPartitionUsageIds: [], gpuDeviceIds: [] });
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
    // gpuDeviceIds: gpu0+gpu1 from multiple leaves; gpu/all excluded; existing buckets unaffected.
    assert.deepEqual(out.gpuDeviceIds, ["gpu/gpu0", "gpu/gpu1"]);
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
    const uuid0 = "disk/0af30554-3219-445a-b6f7-e02910a91469/usedPercent";
    const uuid1 = "disk/6286e04e-b217-43bf-834f-d6a054ac4376/usedPercent";
    assert.deepEqual(out.diskPartitionUsageIds, [uuid0, uuid1]);
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
    assert.deepEqual(out.diskPartitionUsageIds, ["disk/6286e04e-b217-43bf-834f-d6a054ac4376/usedPercent"]);
});

test('classifyDiscoveredIds: natural sort puts cpu10 after cpu9', () => {
    // Default JS string sort would produce ["…cpu1…", "…cpu10…", "…cpu2…"].
    const out = Catalog.classifyDiscoveredIds([
        "cpu/cpu10/usage", "cpu/cpu2/usage", "cpu/cpu1/usage",
        "cpu/cpu0/usage", "cpu/cpu9/usage", "cpu/cpu11/usage",
    ]);
    assert.deepEqual(out.coreUsageIds, [
        "cpu/cpu0/usage", "cpu/cpu1/usage", "cpu/cpu2/usage",
        "cpu/cpu9/usage", "cpu/cpu10/usage", "cpu/cpu11/usage",
    ]);
});

test('classifyDiscoveredIds: gpu indices sort numerically too', () => {
    const out = Catalog.classifyDiscoveredIds([
        "gpu/gpu10/temperature", "gpu/gpu1/temperature", "gpu/gpu0/temperature",
    ]);
    assert.deepEqual(out.gpuTempIds, [
        "gpu/gpu0/temperature", "gpu/gpu1/temperature", "gpu/gpu10/temperature",
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
    assert.deepEqual(out, { coreUsageIds: [], gpuTempIds: [], gpuUsageIds: [], diskPartitionUsageIds: [], gpuDeviceIds: [] });
});

// ── classifyDiscoveredIds: gpuDeviceIds ──────────────────────────────
test('classifyDiscoveredIds: gpuDeviceIds — any leaf counts; gpu/all excluded; dedup per device', () => {
    // SCENARIO: non-temp/usage leaves (power, name, coreFrequency) must still
    // register the device; gpu/all must not appear; multiple leaves yield one entry.
    const out = Catalog.classifyDiscoveredIds([
        "gpu/gpu1/usage", "gpu/gpu1/power", "gpu/gpu1/name", "gpu/gpu1/coreFrequency",
        "gpu/all/usage",
    ]);
    assert.deepEqual(out.gpuDeviceIds, ["gpu/gpu1"]);
});

test('classifyDiscoveredIds: gpuDeviceIds is empty with no gpu/gpuN ids', () => {
    const out = Catalog.classifyDiscoveredIds(["cpu/cpu0/usage", "gpu/all/usage"]);
    assert.deepEqual(out.gpuDeviceIds, []);
});

test('classifyDiscoveredIds: gpuDeviceIds sorts numerically (gpu10 after gpu9)', () => {
    const out = Catalog.classifyDiscoveredIds([
        "gpu/gpu10/usage", "gpu/gpu2/usage", "gpu/gpu1/usage",
        "gpu/gpu0/usage",  "gpu/gpu9/usage",
    ]);
    assert.deepEqual(out.gpuDeviceIds, ["gpu/gpu0", "gpu/gpu1", "gpu/gpu2", "gpu/gpu9", "gpu/gpu10"]);
});
