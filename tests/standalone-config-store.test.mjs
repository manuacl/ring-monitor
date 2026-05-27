import { test } from "node:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import assert from "node:assert";

// Text-level guard for the standalone ConfigStore adapter. Same
// rationale as tests/config-store.test.mjs (its Plasma counterpart):
// the file imports `Qt.labs.settings`, which is shipped by Qt 6 but
// the standalone build's runtime context (Qt.labs.settings.Settings
// as the root element) requires the C++ app to have set
// QGuiApplication::setOrganizationName + setApplicationName — a
// qmltestrunner-based smoke test would not satisfy that. Asserting
// the public surface as text catches typos that would otherwise slip
// through to silent undefined bindings at runtime.
//
// Per platforms/standalone/CLAUDE.md § Same-surface rule, the
// standalone adapter must mirror the Plasma adapter on the public
// property surface main.qml + core/MainContent.qml consume.

const __dirname = dirname(fileURLToPath(import.meta.url));
const SOURCE = readFileSync(join(__dirname, "..", "contents", "ui", "platforms", "standalone", "ConfigStore.qml"), "utf8");
const PLASMA_SOURCE = readFileSync(join(__dirname, "..", "contents", "ui", "platforms", "plasma", "ConfigStore.qml"), "utf8");

// Public surface — must match the Plasma adapter's tests/config-store.test.mjs
// EXPECTED_KEYS exactly. Kept inline (not imported) so the assertion
// fails on either drift: someone bumping the Plasma list without the
// standalone, or vice versa.
const EXPECTED_KEYS = [
    "metricOrder", "enabledMetrics", "showCpuCores", "mergeCpuTemp", "mergeGpuTemp",
    "orientation", "ringSize", "ringSpacingPercent", "windowMargin", "textOpacity", "trackOpacity", "arcOpacity",
    "colorTheme", "colorMode", "customColorLight", "customColorDark",
    "textColorMode", "customTextColorLight", "customTextColorDark",
    "tempUnit",
    "checkForUpdatesEnabled", "lastUpdateCheck", "latestKnownVersion", "acknowledgedVersion",
];

test("standalone ConfigStore declares every persisted config key", () => {
    for (const key of EXPECTED_KEYS) {
        const pattern = new RegExp(`property\\s+\\w+\\s+${key}\\s*:`);
        assert.match(SOURCE, pattern, `standalone ConfigStore.qml must declare property "${key}"`);
    }
});

test("standalone ConfigStore properties are writable (NOT readonly)", () => {
    // Important divergence from the Plasma adapter: the standalone
    // dialog writes directly to the Settings element, so the keys
    // must NOT carry the readonly modifier. Catches a mechanical
    // mistake of copying the Plasma adapter's readonly convention.
    // localVersion is the documented exception (readonly, derived
    // from Qt.application.version).
    for (const key of EXPECTED_KEYS) {
        const readonlyPattern = new RegExp(`readonly\\s+property\\s+\\w+\\s+${key}\\s*:`);
        assert.doesNotMatch(SOURCE, readonlyPattern, `standalone ConfigStore.qml property "${key}" must NOT be readonly — the dialog needs to write through`);
    }
});

test("standalone ConfigStore root element is Qt.labs.settings.Settings", () => {
    assert.match(SOURCE, /import\s+Qt\.labs\.settings/, "must import Qt.labs.settings");
    // Root element on its own line (after imports + comments): the
    // file's QML root is a Settings instance, not an Item wrapping
    // one. That's intentional — Settings IS the persistence layer,
    // wrapping it would mean duplicating every property declaration.
    assert.match(SOURCE, /^Settings\s*{/m, "root element must be Settings (not Item wrapping Settings)");
});

test("standalone ConfigStore exposes the update-check writer surface", () => {
    assert.match(SOURCE, /function\s+recordUpdateCheck\s*\(\s*version\s*,\s*timestampMs\s*\)/, "must declare recordUpdateCheck(version, timestampMs)");
    assert.match(SOURCE, /function\s+acknowledgeVersion\s*\(\s*version\s*\)/, "must declare acknowledgeVersion(version)");
});

test("standalone ConfigStore exposes localVersion via Qt.application.version", () => {
    // Different source from the Plasma adapter (which reads
    // Plasmoid.metaData.version), same public surface name.
    assert.match(SOURCE, /readonly\s+property\s+string\s+localVersion\s*:\s*Qt\.application\.version/, "localVersion must be readonly + sourced from Qt.application.version");
});

test("standalone ConfigStore key list mirrors the Plasma adapter key list", () => {
    // Drift catcher: someone adding a new key in main.xml and
    // wiring it in only one adapter would silently produce two
    // different config surfaces. Asserting the Plasma adapter declares
    // the same set keeps both files honest.
    for (const key of EXPECTED_KEYS) {
        const pattern = new RegExp(`property\\s+\\w+\\s+${key}\\s*:`);
        assert.match(PLASMA_SOURCE, pattern, `Plasma ConfigStore.qml must also declare property "${key}" (drift between adapters)`);
    }
});
