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
const SOURCE = readFileSync(join(__dirname, "..", "contents", "ui", "platforms", "plasma", "ConfigStore.qml"), "utf8");

// Single source of truth: the config schema in contents/config/main.xml.
// Deriving the key set from `<entry name="X">` (instead of an inline
// hardcoded list) means adding a new schema entry automatically
// expands the expected set — the drift PR #35 hit (had to hand-edit
// the inline list to add the `ringSize` trio) can't recur silently.
const MAIN_XML = readFileSync(join(__dirname, "..", "contents", "config", "main.xml"), "utf8");
const EXPECTED_KEYS = [...MAIN_XML.matchAll(/<entry\s+name="([^"]+)"/g)].map(m => m[1]);

test("schema sanity — main.xml yields a non-empty key set", () => {
    // Guard against a regex / path regression silently emptying the
    // list and making every key assertion below vacuously pass.
    assert.ok(EXPECTED_KEYS.length >= 20, `expected ≥20 schema keys, got ${EXPECTED_KEYS.length}`);
});

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

// Keys deliberately overridden in the Plasma adapter rather than
// bound through to `Plasmoid.configuration`. Each entry must come
// with a dedicated test below explaining the override.
const HARDCODED_OVERRIDES = new Set(["ringSpacingPercent", "windowAnchorCorner", "windowMarginX", "windowMarginY", "windowScreen"]);

test("ConfigStore binds each property to the matching Plasmoid.configuration key", () => {
    for (const key of EXPECTED_KEYS) {
        if (HARDCODED_OVERRIDES.has(key)) continue;
        const bindingPattern = new RegExp(`${key}\\s*:\\s*Plasmoid\\.configuration\\.${key}\\b`);
        assert.match(SOURCE, bindingPattern, `ConfigStore.qml property "${key}" must bind to Plasmoid.configuration.${key}`);
    }
});

test("ConfigStore hardcodes ringSpacingPercent to 0 on Plasma (frame-fixed widget)", () => {
    // On the Plasma desktop containment the plasmoid frame is
    // user-dragged-fixed; the GridLayout's rowSpacing/columnSpacing
    // eats into the available frame area, shrinking the rings to
    // compensate. Forcing ringSpacingPercent=0 gives those pixels
    // back so the rings render edge-to-edge in the frame. The
    // AppearanceBody slider is also hidden on Plasma via
    // `ringSpacingVisible`, so the user never sets a value through
    // the UI — the standalone host keeps its own configurable value.
    assert.match(
        SOURCE,
        /readonly\s+property\s+int\s+ringSpacingPercent\s*:\s*0\b/,
        "ConfigStore must hardcode ringSpacingPercent to 0 (Plasma-specific override)",
    );
    assert.doesNotMatch(
        SOURCE,
        /ringSpacingPercent\s*:\s*Plasmoid\.configuration\.ringSpacingPercent/,
        "ConfigStore must NOT bind ringSpacingPercent through to Plasmoid.configuration (that would reintroduce the frame-fixed visual no-op)",
    );
});

test("ConfigStore hardcodes the window-placement keys on Plasma (unused — plasmashell positions the slot)", () => {
    // windowAnchorCorner / windowMarginX / windowMarginY / windowScreen are only
    // consumed by the standalone Window anchoring code (Main.qml's
    // WindowAnchor.setGeometry / WaylandLayerShell.configure). On Plasma
    // the slot position is plasmashell's job and AppearanceBody hides the
    // controls via `windowPlacementVisible`. Hardcoding makes the "unused
    // on Plasma" intent explicit and prevents a stray
    // Plasmoid.configuration value from leaking into a future Plasma-side
    // consumer.
    assert.match(
        SOURCE,
        /readonly\s+property\s+string\s+windowAnchorCorner\s*:\s*"top-right"/,
        "ConfigStore must hardcode windowAnchorCorner to \"top-right\" (Plasma-specific override)",
    );
    assert.match(
        SOURCE,
        /readonly\s+property\s+int\s+windowMarginX\s*:\s*0\b/,
        "ConfigStore must hardcode windowMarginX to 0 (Plasma-specific override)",
    );
    assert.match(
        SOURCE,
        /readonly\s+property\s+int\s+windowMarginY\s*:\s*0\b/,
        "ConfigStore must hardcode windowMarginY to 0 (Plasma-specific override)",
    );
    assert.match(
        SOURCE,
        /readonly\s+property\s+string\s+windowScreen\s*:\s*""/,
        "ConfigStore must hardcode windowScreen to \"\" (Plasma-specific override)",
    );
    for (const key of ["windowAnchorCorner", "windowMarginX", "windowMarginY", "windowScreen"]) {
        assert.doesNotMatch(
            SOURCE,
            new RegExp(`${key}\\s*:\\s*Plasmoid\\.configuration\\.${key}`),
            `ConfigStore must NOT bind ${key} through to Plasmoid.configuration (unused on Plasma)`,
        );
    }
});
