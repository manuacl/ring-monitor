import { test } from "node:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import assert from "node:assert";

// Text-level guard for the Plasma DiskPartitions adapter. Like
// tests/metrics-backend.test.mjs, this file imports
// `org.kde.ksysguard.sensors`, which the CI Fedora container doesn't
// ship — a qmltestrunner test would fail to load. So we inspect the QML
// source as text and pin the contract. The pure parts it relies on
// (Catalog.classifyDiscoveredIds bucketing + the regex-subscription
// exclusion) are covered at the JS level in tests/metrics-catalog.test.mjs.

const __dirname = dirname(fileURLToPath(import.meta.url));
const SOURCE = readFileSync(join(__dirname, "..", "contents", "ui", "platforms", "plasma", "DiskPartitions.qml"), "utf8");

test("DiskPartitions exposes the partitions surface consumed by backend + config", () => {
    assert.match(SOURCE, /property\s+var\s+partitions\s*:/, "must expose a `partitions` property ([{id,label,sensorId}])");
});

test("DiskPartitions walks the SensorTreeModel and classifies via the pure helper", () => {
    assert.match(SOURCE, /import\s+org\.kde\.ksysguard\.sensors/, "must import the ksysguard sensors module");
    assert.match(SOURCE, /SensorTreeModel\s*{/, "must instantiate a SensorTreeModel to walk");
    assert.match(SOURCE, /Catalog\.classifyDiscoveredIds\s*\(/, "must bucket the discovered ids via the pure classifier");
});

test("DiskPartitions takes the label from the parent node display name", () => {
    // The FS volume label ("bazzite") lives on the parent disk/<uuid> node,
    // whose SensorId role can be empty — so the label must come from the
    // parent's Qt.DisplayRole carried down the walk (parentName), not a
    // SensorId-keyed lookup. Regression: labels showed raw UUIDs.
    assert.match(SOURCE, /Qt\.DisplayRole/, "must read the display name via Qt.DisplayRole");
    assert.match(SOURCE, /labelByUuid/, "must map uuid → parent display name during the walk");
});

test("DiskPartitions refreshes on tree structural changes", () => {
    // A late-mounted disk (USB plug) must appear without a widget reload.
    assert.match(SOURCE, /onRowsInserted/, "must refresh on rowsInserted");
    assert.match(SOURCE, /onRowsRemoved/, "must refresh on rowsRemoved");
    assert.match(SOURCE, /onModelReset/, "must refresh on modelReset");
});

test("DiskPartitions imports no path to a sibling platforms dir (isolation)", () => {
    // It lives in platforms/plasma/ and may import core/ helpers, but must
    // not reach into platforms/standalone.
    assert.doesNotMatch(SOURCE, /platforms\/standalone/, "must not import the standalone adapter dir");
});
