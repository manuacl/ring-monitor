// Text-level guard: every Plasma config page declares a cfg_<key> (and
// cfg_<key>Default) for EVERY entry in main.xml — as a real alias bridge
// or a KDE-bug-484541 placeholder. Plasma broadcasts every key to every
// page on dialog open; a missing property logs "Setting initial
// properties failed" in the journal for each open (seen live for
// cfg_diskPartitionColors / cfg_partitionOptOut on the About page after
// #58/#67 added the keys without extending the placeholder blocks).
//
// Expected set derived from main.xml at test time, never hardcoded —
// see tests/CLAUDE.md § "Drift-catchers derive their expected set".

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const UI = join(__dirname, "..", "contents", "ui");

const SCHEMA = readFileSync(join(__dirname, "..", "contents", "config", "main.xml"), "utf8");
const KEYS = [...SCHEMA.matchAll(/<entry name="([^"]+)"/g)].map((m) => m[1]);

const PAGES = ["configMetrics.qml", "configAppearance.qml", "configAbout.qml"];

test("main.xml key extraction is sane", () => {
    assert.ok(KEYS.length >= 20, `expected ≥20 schema keys, got ${KEYS.length}`);
});

for (const page of PAGES) {
    test(`${page} declares cfg_<key> and cfg_<key>Default for every main.xml entry`, () => {
        const src = readFileSync(join(UI, page), "utf8");
        const missing = [];
        for (const key of KEYS) {
            for (const prop of [`cfg_${key}`, `cfg_${key}Default`]) {
                // Matches both bridge aliases and 484541 placeholders:
                //   property alias cfg_x: body.x   |   property var cfg_x
                const decl = new RegExp(`property\\s+\\w+\\s+${prop}\\b`);
                if (!decl.test(src))
                    missing.push(prop);
            }
        }
        assert.deepEqual(missing, [], `${page} is missing declarations for: ${missing.join(", ")}`);
    });
}
