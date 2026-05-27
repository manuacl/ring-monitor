import { test } from "node:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import assert from "node:assert";

// Text-level guard for the standalone MetricsBackend adapter. Same
// rationale as tests/metrics-backend.test.mjs (its Plasma counterpart):
// the file imports `RingMonitor.Standalone` (the ProcReader C++ helper
// registered via QML_ELEMENT), which is built by CMake locally but NOT
// in the Fedora 41 CI container (CI ships Qt6 + Kirigami, no cmake
// step for standalone/). A qmltestrunner-based smoke test would fail
// to load. Asserting the public surface as text catches the same
// class of bug (typo in a property name → silent undefined binding in
// production) without needing the helper available.
//
// Per platforms/standalone/CLAUDE.md § Same-surface rule, the
// standalone adapter must mirror the Plasma adapter byte-for-byte on
// the public surface main.qml consumes.

const __dirname = dirname(fileURLToPath(import.meta.url));
const SOURCE = readFileSync(join(__dirname, "..", "contents", "ui", "platforms", "standalone", "MetricsBackend.qml"), "utf8");

// Same public surface as platforms/plasma/MetricsBackend.qml.
const PUBLIC_PROPS = ["coreValues", "loading"];
const PUBLIC_FUNCS = ["metricValue", "metricRawTemp", "metricTempPercent"];

test("standalone MetricsBackend exposes the public properties main.qml depends on", () => {
    for (const name of PUBLIC_PROPS) {
        const pattern = new RegExp(`property\\s+\\w+\\s+${name}\\s*:`);
        assert.match(SOURCE, pattern, `standalone MetricsBackend.qml must declare property "${name}"`);
    }
});

test("standalone MetricsBackend exposes the public functions main.qml depends on", () => {
    for (const name of PUBLIC_FUNCS) {
        const pattern = new RegExp(`function\\s+${name}\\s*\\(`);
        assert.match(SOURCE, pattern, `standalone MetricsBackend.qml must declare function ${name}(...)`);
    }
});

test("standalone MetricsBackend wires ProcReader + ProcStatParser", () => {
    assert.match(SOURCE, /ProcReader\s*{/, "must instantiate the ProcReader QML element");
    assert.match(SOURCE, /import\s+RingMonitor\.Standalone/, "must import RingMonitor.Standalone (where ProcReader is registered)");
    assert.match(SOURCE, /ProcStatParser\.parseProcStat\s*\(/, "must call ProcStatParser.parseProcStat on the raw text");
    assert.match(SOURCE, /ProcStatParser\.percentFromSample\s*\(/, "must call ProcStatParser.percentFromSample to derive the % between two samples");
});

test("standalone MetricsBackend wires RAM via /proc/meminfo + MemInfoParser", () => {
    assert.match(SOURCE, /reader\.read\(["']\/proc\/meminfo["']\)/, "must read /proc/meminfo through the ProcReader helper");
    assert.match(SOURCE, /MemInfoParser\.parseMemInfo\s*\(/, "must call MemInfoParser.parseMemInfo on the raw text");
    assert.match(SOURCE, /MemInfoParser\.usagePercent\s*\(/, "must compute the RAM percent through the shared usagePercent helper");
});

test("standalone MetricsBackend wires disk via statvfs(/)", () => {
    assert.match(SOURCE, /reader\.statvfs\s*\(/, "must call ProcReader.statvfs(...) for disk usage");
    // The default mount is "/" — matches the plan's MVP scope. A
    // future per-mount selector is allowed to override this, but the
    // current default must stay on root.
    assert.match(SOURCE, /["']\/["']/, "must reference the root mount '/' for the default disk path");
    // Review finding 🟠 PR #30: disk usage must use df(1)'s formula
    // via diskUsagePercent, not the naive usagePercent (which counts
    // the ext4 5% root reservation as used and reports a non-zero
    // percent on a freshly-formatted empty disk). Lock the wiring in.
    assert.match(
        SOURCE,
        /MemInfoParser\.diskUsagePercent\s*\(\s*disk\.total\s*,\s*disk\.free\s*,\s*disk\.available\s*\)/,
        "disk percent must be computed via diskUsagePercent(total, free, available) so it matches `df`",
    );
});

test("standalone MetricsBackend exposes ram + disk through metricValue", () => {
    // metricValue must route the new ids to the freshly-sampled
    // backing properties. Catches the failure mode where the wiring
    // exists but the public function still returns 0 for ram/disk.
    assert.match(SOURCE, /id\s*===\s*["']ram["']/, "metricValue must branch on id === 'ram'");
    assert.match(SOURCE, /id\s*===\s*["']disk["']/, "metricValue must branch on id === 'disk'");
});

test("standalone MetricsBackend polls on a Timer", () => {
    // Polling cadence: once per second is the contract documented in
    // platforms/standalone/CLAUDE.md. Use the interval value as the
    // marker — looser than full Timer block matching, tighter than no
    // assertion at all.
    assert.match(SOURCE, /Timer\s*{[\s\S]*?interval:\s*1000/, "must declare a Timer with interval: 1000ms");
});
