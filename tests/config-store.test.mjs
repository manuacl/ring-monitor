import { test } from "node:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import assert from "node:assert";

// Text-level guard for the ConfigStore adapter. ConfigStore.qml imports
// `org.kde.plasma.plasmoid`, which is part of the Plasma desktop runtime
// and is NOT available in CI (Fedora 41 container ships only Qt 6 +
// Kirigami 6). So we can't run a qmltestrunner-based smoke test for it.
//
// This Node test inspects the QML source as plain text and asserts that
// each persisted config key (mirroring contents/config/main.xml) is
// declared as a property on the adapter. Catches the same class of bug
// the QML hasOwnProperty guard caught (typo in a property name slips
// through reviews and makes a binding silently undefined at runtime),
// without needing the Plasmoid QML module installed.

const __dirname = dirname(fileURLToPath(import.meta.url));
const SOURCE = readFileSync(join(__dirname, "..", "contents", "ui", "platform", "ConfigStore.qml"), "utf8");

// Keys must match contents/config/main.xml — update both when adding a
// new config entry.
const EXPECTED_KEYS = ["metricOrder", "enabledMetrics", "showCpuCores", "orientation", "textOpacity", "trackOpacity", "arcOpacity"];

test("ConfigStore declares every persisted config key", () => {
    for (const key of EXPECTED_KEYS) {
        // Matches: `readonly property <type> <key>:` with any indent.
        const pattern = new RegExp(`property\\s+\\w+\\s+${key}\\s*:`);
        assert.match(SOURCE, pattern, `ConfigStore.qml must declare property "${key}"`);
    }
});

test("ConfigStore properties are readonly (reads-only-by-design contract)", () => {
    for (const key of EXPECTED_KEYS) {
        const readonlyPattern = new RegExp(`readonly\\s+property\\s+\\w+\\s+${key}\\s*:`);
        assert.match(SOURCE, readonlyPattern, `ConfigStore.qml property "${key}" must be readonly`);
    }
});

test("ConfigStore binds each property to the matching Plasmoid.configuration key", () => {
    for (const key of EXPECTED_KEYS) {
        const bindingPattern = new RegExp(`${key}\\s*:\\s*Plasmoid\\.configuration\\.${key}\\b`);
        assert.match(SOURCE, bindingPattern, `ConfigStore.qml property "${key}" must bind to Plasmoid.configuration.${key}`);
    }
});
