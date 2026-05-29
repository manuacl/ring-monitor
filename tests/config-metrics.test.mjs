// Text-level guard for configMetrics.qml — the Plasma KCM wrapper for the
// Metrics page. Same rationale as config-store.test.mjs / metrics-backend.test.mjs:
// it imports org.kde.kcmutils + the Plasma MetricsBackend, neither in the CI
// container, so a qmltestrunner load would fail. We inspect the source as text
// and assert the wiring the disk picker depends on.
//
// This is the integration seam between the mount-gating (MetricsBackend.
// mountedAvailablePartitions, #65) and the picker (MetricsBody): the bug class
// it guards is "the picker is fed the RAW availablePartitions again", which
// would re-list an unplugged-but-frozen disk as a live selectable row (#58).

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const SRC = readFileSync(join(__dirname, "..", "contents", "ui", "configMetrics.qml"), "utf8");

test("configMetrics feeds the picker the MOUNT-GATED partition list, not the raw one", () => {
    assert.match(
        SRC,
        /diskPartitions\s*:\s*metricsAdapter\.mountedAvailablePartitions/,
        "MetricsBody.diskPartitions must be metricsAdapter.mountedAvailablePartitions (gated), so an unmounted-but-frozen disk drops from the picker (#58/#65)",
    );
    assert.doesNotMatch(
        SRC,
        /diskPartitions\s*:\s*metricsAdapter\.availablePartitions\b/,
        "must NOT feed the raw availablePartitions — that re-lists a frozen unplugged disk as selectable",
    );
});

test("configMetrics activates the findmnt poll so the gate has live mount data", () => {
    // Without removableTrackingActive, MountInfo doesn't poll, mountedPartitionIds
    // stays empty, and filterToMounted passes through (no gating) — the picker
    // would keep the frozen disk. The config dialog is transient so polling
    // while it's open is cheap.
    assert.match(
        SRC,
        /MetricsBackend\s*{[\s\S]*?removableTrackingActive\s*:\s*true/,
        "the config MetricsBackend must set removableTrackingActive: true",
    );
});

test("configMetrics gates the destructive stale-row action on the adapter's readiness", () => {
    assert.match(
        SRC,
        /partitionsReady\s*:\s*metricsAdapter\.partitionsReady/,
        "partitionsReady must come from the adapter so the trash action can't race incremental discovery",
    );
});
