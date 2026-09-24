// Tests for RestartPending.js — detecting an update installed on disk while
// plasmashell still runs the old widget (#172) — plus text-level guards on
// the Plasma QML that consumes it (org.kde.* imports, not loadable in CI).
//
// Run:  node --test tests/restart-pending.test.mjs

import { createRequire } from "node:module";
import { test } from "node:test";
import { existsSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, resolve } from "node:path";
import assert from "node:assert/strict";

const require = createRequire(import.meta.url);
const RP = require("../contents/ui/platforms/plasma/RestartPending.js");

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, "..");
const PLASMA = join(ROOT, "contents", "ui", "platforms", "plasma");
const read = (...p) => readFileSync(join(...p), "utf8");

test("readCommand: cats the decoded path of a file URL", () => {
    assert.equal(
        RP.readCommand("file:///home/u/.local/share/plasma/plasmoids/x/metadata.json"),
        "cat '/home/u/.local/share/plasma/plasmoids/x/metadata.json'");
});

test("readCommand: percent-escapes decoded, single quotes shell-escaped", () => {
    assert.equal(
        RP.readCommand("file:///home/o'brien/My%20Widgets/metadata.json"),
        "cat '/home/o'\\''brien/My Widgets/metadata.json'");
});

test("readCommand: empty for a non-file URL (qrc, empty, undefined)", () => {
    assert.equal(RP.readCommand("qrc:/metadata.json"), "");
    assert.equal(RP.readCommand(""), "");
    assert.equal(RP.readCommand(undefined), "");
});

test("parseInstalledVersion: reads KPlugin.Version", () => {
    assert.equal(RP.parseInstalledVersion('{"KPlugin": {"Id": "x", "Version": "0.18.0"}}'), "0.18.0");
});

test("parseInstalledVersion: the repo's own metadata.json parses", () => {
    assert.match(RP.parseInstalledVersion(read(ROOT, "metadata.json")), /^\d+\.\d+\.\d+$/);
});

test("parseInstalledVersion: empty on garbage, missing key or non-string", () => {
    assert.equal(RP.parseInstalledVersion(""), "");
    assert.equal(RP.parseInstalledVersion("not json"), "");
    assert.equal(RP.parseInstalledVersion('{"KPlugin": {}}'), "");
    assert.equal(RP.parseInstalledVersion("{}"), "");
    assert.equal(RP.parseInstalledVersion('{"KPlugin": {"Version": 18}}'), "");
});

test("isRestartPending: only when both versions are known and differ", () => {
    assert.equal(RP.isRestartPending("0.17.0", "0.18.0"), true);
    assert.equal(RP.isRestartPending("0.18.0", "0.17.0"), true); // downgrade too
    assert.equal(RP.isRestartPending("0.17.0", "0.17.0"), false);
    assert.equal(RP.isRestartPending("0.17.0", ""), false); // disk not read yet
    assert.equal(RP.isRestartPending("", "0.18.0"), false);
});

test("RESTART_COMMAND: systemd restart first, bare executables only", () => {
    assert.match(RP.RESTART_COMMAND, /^systemctl --user restart plasma-plasmashell\.service \|\| /);
    assert.doesNotMatch(RP.RESTART_COMMAND, /(^|\s)\/(usr|bin|sbin)\//);
});

test("RestartPending.qml: its resolvedUrl reaches the package's metadata.json", () => {
    const qml = read(PLASMA, "RestartPending.qml");
    const rel = qml.match(/Qt\.resolvedUrl\("([^"]+)"\)/)[1];
    assert.equal(resolve(PLASMA, rel), join(ROOT, "metadata.json"));
    assert.ok(existsSync(resolve(PLASMA, rel)));
});

test("RestartPending.qml: compares against the in-memory Plasmoid version", () => {
    const qml = read(PLASMA, "RestartPending.qml");
    assert.match(qml, /Plasmoid\.metaData\.version/);
    assert.match(qml, /readonly property bool restartPending:/);
    assert.match(qml, /function restartPlasma\(\)/);
});

test("wiring: main.qml feeds the badge, every config page carries the banner", () => {
    const main = read(ROOT, "contents", "ui", "main.qml");
    assert.match(main, /Platform\.RestartPending \{/);
    assert.match(main, /restartPending: restartPendingAdapter\.restartPending/);
    assert.match(read(PLASMA, "PlaceholderKCM.qml"), /header: RestartBanner \{\}/);
    assert.match(read(PLASMA, "RestartBanner.qml"), /onTriggered: restart\.restartPlasma\(\)/);
});
