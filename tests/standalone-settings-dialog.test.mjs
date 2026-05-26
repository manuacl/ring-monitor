import { test } from "node:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import assert from "node:assert";

// Text-level guard for the standalone SettingsDialog. The dialog
// imports `QtQuick.Controls` and instantiates `core/MetricsBody`
// (which has internal drag-and-drop logic) — qmltestrunner-qt6 can
// load these, but the dialog's two-way binding wiring only fires at
// runtime once `configStore` is injected and `Component.onCompleted`
// runs. A full integration smoke test would need a mock ConfigStore
// with every property declared — more friction than payoff for the
// boilerplate this catches.
//
// Instead we assert the file structurally:
//   1. Every persisted config key is referenced in the _bridgeMap
//      entries (so adding a key to ConfigStore.qml and forgetting to
//      wire it here gets caught).
//   2. The right Core. bodies are instantiated (Metrics / Appearance
//      / About).
//   3. The bridge wiring pattern (initial pull + onChanged write-back)
//      is present.

const __dirname = dirname(fileURLToPath(import.meta.url));
const SOURCE = readFileSync(join(__dirname, "..", "contents", "ui", "platforms", "standalone", "SettingsDialog.qml"), "utf8");

// Pairs: [bodyProp, storeProp]. Mirrors the _bridgeMap inside
// SettingsDialog.qml. The two CSV-named props on MetricsBody have
// renamed store keys; everything else is name-equal.
const BRIDGED_KEYS = [
    ["metricOrderCsv", "metricOrder"],
    ["enabledMetricsCsv", "enabledMetrics"],
    ["showCpuCores", "showCpuCores"],
    ["mergeCpuTemp", "mergeCpuTemp"],
    ["mergeGpuTemp", "mergeGpuTemp"],
    ["tempUnit", "tempUnit"],
    ["orientation", "orientation"],
    ["ringSize", "ringSize"],
    ["ringSpacingPercent", "ringSpacingPercent"],
    ["windowMargin", "windowMargin"],
    ["textOpacity", "textOpacity"],
    ["trackOpacity", "trackOpacity"],
    ["arcOpacity", "arcOpacity"],
    ["colorTheme", "colorTheme"],
    ["colorMode", "colorMode"],
    ["customColorLight", "customColorLight"],
    ["customColorDark", "customColorDark"],
    ["textColorMode", "textColorMode"],
    ["customTextColorLight", "customTextColorLight"],
    ["customTextColorDark", "customTextColorDark"],
];

test("SettingsDialog _bridgeMap registers every persisted key", () => {
    for (const [bodyProp, storeProp] of BRIDGED_KEYS) {
        const entryPattern = new RegExp(`"${bodyProp}"\\s*,\\s*"${storeProp}"`);
        assert.match(SOURCE, entryPattern, `SettingsDialog._bridgeMap must contain ["${bodyProp}", "${storeProp}"]`);
    }
});

test("SettingsDialog instantiates the three core bodies", () => {
    assert.match(SOURCE, /Core\.MetricsBody\s*{/, "must instantiate Core.MetricsBody");
    assert.match(SOURCE, /Core\.AppearanceBody\s*{/, "must instantiate Core.AppearanceBody");
    assert.match(SOURCE, /Core\.AboutBody\s*{/, "must instantiate Core.AboutBody");
});

test("SettingsDialog uses the pull + change-signal write-back pattern", () => {
    // _wireBridges must contain both halves: initial pull (body[bodyProp] = configStore[storeProp])
    // AND a XChanged signal connect that writes back.
    assert.match(SOURCE, /body\[bodyProp\]\s*=\s*dialog\.configStore\[storeProp\]/, "must do the initial pull (body[bodyProp] = configStore[storeProp])");
    assert.match(SOURCE, /\[bp\s*\+\s*["']Changed["']\]\.connect/, "must connect the body's XChanged signal for write-back");
    assert.match(SOURCE, /metricsBody\.loadOrder\(\)/, "must call metricsBody.loadOrder() after pulling metricOrderCsv so the ListModel reflects the persisted order");
});

test("SettingsDialog wires the AboutBody update-flow surface", () => {
    // AboutBody is bridged differently — it consumes UpdateChecker
    // computed props + emits signals back. Without these the About
    // tab would render empty / buttons no-op.
    assert.match(SOURCE, /onAcknowledgeClicked\s*:\s*dialog\.updateChecker/, "onAcknowledgeClicked must call updateChecker.acknowledge");
    assert.match(SOURCE, /onOpenStorePageClicked\s*:\s*dialog\.updateChecker/, "onOpenStorePageClicked must call updateChecker.openStorePage");
    assert.match(SOURCE, /onCheckForUpdatesToggled\s*:[\s\S]{0,200}configStore\.checkForUpdatesEnabled\s*=/, "onCheckForUpdatesToggled must write configStore.checkForUpdatesEnabled");
});

test("SettingsDialog instantiates Autostart and wires it through AboutBody", () => {
    // Without these the "Start automatically on login" checkbox in
    // AboutBody stays hidden (autostartAvailable defaults to false)
    // OR shows but does not persist (no onAutostartToggled wire-up).
    assert.match(SOURCE, /import\s+RingMonitor\.Standalone/, "must import RingMonitor.Standalone (where Autostart is registered)");
    assert.match(SOURCE, /Autostart\s*{[\s\S]{0,100}id:\s*autostartHelper/, "must instantiate Autostart { id: autostartHelper }");
    assert.match(SOURCE, /autostartAvailable\s*:\s*true/, "AboutBody.autostartAvailable must be true so the toggle renders");
    assert.match(SOURCE, /autostartEnabled\s*:\s*autostartHelper\.enabled/, "AboutBody.autostartEnabled must read from autostartHelper.enabled so the checkbox stays in sync with the .desktop file's existence");
    assert.match(SOURCE, /onAutostartToggled\s*:\s*on\s*=>\s*autostartHelper\.setEnabled\(on\)/, "onAutostartToggled must call autostartHelper.setEnabled(on)");
});
