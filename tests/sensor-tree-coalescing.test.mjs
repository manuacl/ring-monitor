import { test } from "node:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import assert from "node:assert";

// Text-level guard (the files import org.kde.ksysguard.sensors, absent from
// CI) for the three Plasma SensorTreeModel walkers.

const __dirname = dirname(fileURLToPath(import.meta.url));
const PLASMA = join(__dirname, "..", "contents", "ui", "platforms", "plasma");

const WALKERS = ["MetricsBackend.qml", "DiskPartitions.qml", "TempSensorDiscovery.qml"];

for (const file of WALKERS) {
    const SOURCE = readFileSync(join(PLASMA, file), "utf8");

    test(`SCENARIO_config_page_freeze: ${file} coalesces tree signals into one walk (#175)`, () => {
        // The tree emits one rowsInserted PER NODE (~300) in a single
        // event-loop turn. Walking the whole tree in each handler was O(n²)
        // and froze the Metrics config page ~1.6 s. Every structural handler
        // must only restart a zero-interval Timer.
        const conn = /Connections\s*{\s*target:\s*(?:sensorTree|tree)\b([\s\S]*?)\n    }/.exec(SOURCE);
        assert.ok(conn, "must connect to its SensorTreeModel");
        const handlers = [...conn[1].matchAll(/function\s+(on\w+)\s*\(\)\s*{([^}]*)}/g)];
        assert.ok(handlers.length >= 3, "must handle rowsInserted/rowsRemoved/modelReset");
        for (const [, name, body] of handlers) {
            assert.match(body.trim(), /^\w+Timer\.restart\(\);$/, `${name} must only restart the coalescing Timer`);
        }
        assert.match(SOURCE, /Timer\s*{[^}]*interval:\s*0\b/, "the coalescing Timer must have interval 0");
    });

    if (file === "TempSensorDiscovery.qml") {
        test("SCENARIO_config_page_freeze: TempSensorDiscovery probe signals only restart rebuildTimer (#175)", () => {
            // The Instantiator adds ~all probes in one turn; an inline _rebuild
            // per signal is the same O(n²) shape as the tree walk.
            for (const sig of ["onStatusChanged", "onObjectAdded", "onObjectRemoved"]) {
                assert.match(SOURCE, new RegExp(`${sig}:\\s*rebuildTimer\\.restart\\(\\)`), `${sig} must only restart rebuildTimer`);
            }
            assert.doesNotMatch(SOURCE, /on(?!Triggered)\w+:\s*discovery\._rebuild\(\)/, "no signal handler may call _rebuild inline");
        });
    }

    test(`${file} coalesces with a Timer, not Qt.callLater`, () => {
        // Constructed inside a KCM page → callLater can fire in a dead
        // context (platforms/plasma/CLAUDE.md § "KCM pages are constructed at startup").
        assert.doesNotMatch(SOURCE, /Qt\.callLater\(/);
    });
}
