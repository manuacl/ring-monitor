import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

// Bidirectional dead-code guard for the standalone build's QML module
// manifest (the `QML_FILES` list in CMakeLists.txt's qt_add_qml_module).
//
// The standalone binary compiles an EXPLICIT file list into the
// `RingMonitor.Standalone` module — unlike the Plasma build, which loads
// `contents/` from the filesystem / plasmoid package. Two failure modes
// this catches:
//
//   1. MISSING (silent crash): a shared core/ or platforms/standalone/
//      file that exists on disk but isn't listed is not in the module —
//      any `import` of it resolves to nothing, the QML root fails to
//      load, and the binary exits 1 with no diagnostic (the
//      rootObjects().isEmpty() bail in standalone/main.cpp). This bit
//      during the CPU-temperature work (CpuTempDiscovery.js unlisted).
//
//   2. LEAKED (dead weight): a platforms/plasma/ file listed here would
//      compile plasma-only code into the standalone binary. The
//      plasma↔standalone split (pure logic lives beside its adapter:
//      ProcStatParser/MemInfoParser/CpuTempDiscovery under
//      platforms/standalone/, SensorPicking under platforms/plasma/)
//      only stays dead-code-free if the manifest never reaches across.
//
// CI can't run this via the build (the Fedora container doesn't compile
// the standalone target), so the text guard is the mechanical floor.

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, "..");
const CMAKE = readFileSync(join(ROOT, "CMakeLists.txt"), "utf8");

// Extract the QML_FILES block: from `QML_FILES` to the closing `)`.
const qmlFilesBlock = (() => {
    const start = CMAKE.indexOf("QML_FILES");
    assert.ok(start !== -1, "CMakeLists.txt must have a QML_FILES section");
    const after = CMAKE.slice(start);
    const end = after.indexOf("\n)");
    assert.ok(end !== -1, "QML_FILES section must terminate with `)`");
    return after.slice(0, end);
})();

const LISTED = new Set(
    [...qmlFilesBlock.matchAll(/contents\/ui\/\S+\.(?:qml|js)/g)].map((m) => m[0]),
);

function diskFiles(relDir, exts) {
    return readdirSync(join(ROOT, relDir))
        .filter((f) => exts.some((e) => f.endsWith(e)))
        .map((f) => `${relDir}/${f}`);
}

test("QML_FILES block was parsed (non-empty)", () => {
    // Guard against a CMake reformat that breaks the extraction and
    // makes every assertion below vacuously pass.
    assert.ok(LISTED.size >= 15, `expected ≥15 listed QML/JS files, got ${LISTED.size}`);
});

test("standalone build lists every shared core/*.{js,qml}", () => {
    for (const f of diskFiles("contents/ui/core", [".js", ".qml"])) {
        assert.ok(
            LISTED.has(f),
            `${f} exists on disk but is missing from CMakeLists.txt QML_FILES — the standalone build would fail to load it (silent exit 1). Add it to the qt_add_qml_module list.`,
        );
    }
});

test("standalone build lists every platforms/standalone/*.{js,qml}", () => {
    for (const f of diskFiles("contents/ui/platforms/standalone", [".js", ".qml"])) {
        assert.ok(
            LISTED.has(f),
            `${f} exists on disk but is missing from CMakeLists.txt QML_FILES.`,
        );
    }
});

test("standalone build lists NOTHING under platforms/plasma/ (no plasma dead code)", () => {
    // platforms/plasma/ is plasma-only (adapters + SensorPicking.js).
    // Listing any of it would compile dead code into the standalone
    // binary — the exact thing the plasma↔standalone split removes.
    for (const f of LISTED) {
        assert.ok(
            !f.startsWith("contents/ui/platforms/plasma/"),
            `${f} is plasma-only but listed in the standalone QML_FILES — it would be dead code in the standalone binary.`,
        );
    }
});
