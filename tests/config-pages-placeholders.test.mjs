// Text-level guard for the KDE-484541 placeholder seam: Plasma sets
// every cfg_<key> (+ the auto-generated cfg_<key>Default) on every
// config page it opens; a missing property logs "Setting initial
// properties failed" per key per open (bit configAbout twice — #77,
// then #58/#67's keys). The placeholders live ONCE in
// platforms/plasma/PlaceholderKCM.qml; each page extends it and
// overrides only its bridged keys with `property alias`.
//
// Both expected sets are derived at test time, never hardcoded — keys
// from main.xml, pages from config.qml's ConfigCategory sources — per
// tests/CLAUDE.md § "Drift-catchers derive their expected set".

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const UI = join(__dirname, "..", "contents", "ui");
const CONFIG = join(__dirname, "..", "contents", "config");

// Same extraction regex as config-store.test.mjs / standalone-config-store.test.mjs
// (\s+ tolerates reformatting) — keep the three in sync.
const SCHEMA = readFileSync(join(CONFIG, "main.xml"), "utf8");
const KEYS = [...SCHEMA.matchAll(/<entry\s+name="([^"]+)"/g)].map((m) => m[1]);

const CONFIG_MODEL = readFileSync(join(CONFIG, "config.qml"), "utf8");
const PAGES = [...new Set([...CONFIG_MODEL.matchAll(/source:\s*"([^"]+)"/g)].map((m) => m[1]))];

const BASE = readFileSync(join(UI, "platforms", "plasma", "PlaceholderKCM.qml"), "utf8");

test("derived sets are sane (regex/path regressions fail loudly)", () => {
    assert.ok(KEYS.length >= 30, `expected ≥30 schema keys, got ${KEYS.length}`);
    assert.ok(PAGES.length >= 3, `expected ≥3 config pages, got ${PAGES.length}`);
});

test("PlaceholderKCM declares cfg_<key> and cfg_<key>Default for every main.xml entry", () => {
    const missing = [];
    for (const key of KEYS) {
        for (const prop of [`cfg_${key}`, `cfg_${key}Default`]) {
            if (!new RegExp(`property\\s+\\w+\\s+${prop}\\b`).test(BASE))
                missing.push(prop);
        }
    }
    assert.deepEqual(missing, [], `PlaceholderKCM.qml is missing declarations for: ${missing.join(", ")}`);
});

for (const page of PAGES) {
    test(`${page} extends PlaceholderKCM so the 484541 placeholders apply`, () => {
        const src = readFileSync(join(UI, page), "utf8");
        assert.match(src, /^Platform\.PlaceholderKCM\s*\{/m, `${page} must use Platform.PlaceholderKCM as its root type (a bare KCM.SimpleKCM root loses every inherited cfg_* placeholder)`);
    });
}
