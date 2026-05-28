import { test } from "node:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import assert from "node:assert";

// Text-level drift-catcher for the standalone Theme adapter.
// `platforms/standalone/Theme.qml` mirrors `platforms/plasma/Theme.qml`
// by hand (both re-export Kirigami tokens + the Qt.styleHints
// light/dark signal under the same property surface that `core/`
// leaves consume). Neither loads under the CI Fedora container's
// qmltestrunner without a real Qt app instantiating Kirigami, so a
// text guard is the only mechanical option — same rationale as
// standalone-config-store.test.mjs.
//
// Rather than hardcode the expected property list (which would itself
// drift), this derives the public surface from the PLASMA adapter and
// asserts the standalone declares the same set. Adding a token to one
// adapter without the other lands as a test failure. (Per
// platforms/standalone/CLAUDE.md § Same-surface rule.)

const __dirname = dirname(fileURLToPath(import.meta.url));
const PLASMA = readFileSync(join(__dirname, "..", "contents", "ui", "platforms", "plasma", "Theme.qml"), "utf8");
const STANDALONE = readFileSync(join(__dirname, "..", "contents", "ui", "platforms", "standalone", "Theme.qml"), "utf8");

// Public surface = readonly properties that are NOT underscore-prefixed
// (the `_qtScheme` intermediate is an internal impl detail of the
// light/dark plumbing, legitimately allowed to differ).
function publicReadonlyProps(source) {
    return [...source.matchAll(/readonly\s+property\s+\w+\s+(\w+)\s*:/g)]
        .map(m => m[1])
        .filter(name => !name.startsWith("_"));
}

const PLASMA_SURFACE = publicReadonlyProps(PLASMA);

test("Plasma Theme adapter exposes the expected token surface", () => {
    // Sanity: the derivation found a real surface, not an empty set
    // (which would make the mirror assertion below vacuously pass).
    // The seven tokens core/ consumes: color trio + size trio + isDarkMode.
    assert.ok(PLASMA_SURFACE.length >= 7, `expected ≥7 public Theme tokens, got ${PLASMA_SURFACE.length}: ${PLASMA_SURFACE.join(", ")}`);
    for (const token of ["textColor", "highlightColor", "backgroundColor", "unit", "smallSpacing", "iconSize", "isDarkMode"]) {
        assert.ok(PLASMA_SURFACE.includes(token), `Plasma Theme.qml must expose "${token}"`);
    }
});

test("standalone Theme adapter mirrors the Plasma adapter's public surface", () => {
    const standaloneSurface = publicReadonlyProps(STANDALONE);
    for (const token of PLASMA_SURFACE) {
        assert.ok(
            standaloneSurface.includes(token),
            `standalone Theme.qml is missing "${token}" exposed by the Plasma adapter (same-surface drift)`,
        );
    }
    // And the reverse — standalone must not grow a public token the
    // Plasma side lacks (that would mean core/ could read a value on
    // one host but get undefined on the other).
    for (const token of standaloneSurface) {
        assert.ok(
            PLASMA_SURFACE.includes(token),
            `standalone Theme.qml exposes "${token}" that the Plasma adapter doesn't — core/ would get undefined on Plasma`,
        );
    }
});

test("standalone Theme includes no Plasma-only imports (isolation)", () => {
    // The standalone adapter may import Kirigami (KF6 runs on any Qt 6
    // desktop) but nothing Plasma-shell-bound.
    assert.doesNotMatch(STANDALONE, /import\s+org\.kde\.plasma/, "standalone Theme.qml must not import org.kde.plasma.*");
});
