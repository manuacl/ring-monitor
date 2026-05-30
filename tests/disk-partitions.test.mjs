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
    // The FS volume label ("root") lives on the parent disk/<uuid> node,
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

test("DiskPartitions exposes a debounced `ready` settle signal", () => {
    // The tree populates incrementally (one rowsInserted per subsystem), so a
    // mid-enumeration snapshot would make a not-yet-walked partition look
    // absent. `ready` only trips once the tree goes quiet for settleMs, gating
    // the config picker's destructive stale-row removal (issue #49 review).
    assert.match(SOURCE, /readonly\s+property\s+bool\s+ready/, "must expose a readonly bool `ready`");
    assert.match(SOURCE, /Timer\s*{/, "must use a Timer to debounce the settle");
    assert.match(SOURCE, /settleTimer\.restart\(\)/, "_refresh must restart the settle timer on each tree change");
    assert.match(SOURCE, /onTriggered:\s*{[\s\S]*?disk\._ready\s*=\s*true/, "the timer must latch _ready true when the tree goes quiet");
});

test("DiskPartitions imports no path to a sibling platforms dir (isolation)", () => {
    // It lives in platforms/plasma/ and may import core/ helpers, but must
    // not reach into platforms/standalone.
    assert.doesNotMatch(SOURCE, /platforms\/standalone/, "must not import the standalone adapter dir");
});

test("SCENARIO hot-plug label: re-walks after the change settles + on data/layout changes", () => {
    // A removable plugged into a live tree gets its volume label resolved a beat
    // after its node is inserted, with no rowsInserted/value signal — so the walk
    // on insertion captures the bare `disk/<uuid>` id. The settle tick must
    // re-walk (picking up the now-resolved label), and we also listen to
    // data/layout changes in case ksysguard surfaces the resolution that way.
    // Without this, the picker shows the raw sensor id until the dialog is reopened.
    assert.match(SOURCE, /onTriggered:\s*{[\s\S]*?_ready\s*=\s*true[\s\S]*?_rewalk\(\)/, "settleTimer must re-walk after marking ready (catch the late-resolved label)");
    assert.match(SOURCE, /function\s+_rewalk\s*\(/, "must split the walk into _rewalk() so the settle tick can re-walk without re-arming the timer (no loop)");
    assert.match(SOURCE, /function\s+onDataChanged\s*\(\)\s*{\s*disk\._refresh\(\)/, "must re-refresh on tree dataChanged");
    assert.match(SOURCE, /function\s+onLayoutChanged\s*\(\)\s*{\s*disk\._refresh\(\)/, "must re-refresh on tree layoutChanged");
});
