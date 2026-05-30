// Tests for scripts/infer-release-scope.sh — the release-tag scope
// classifier (issue #89). Feeds newline-separated file lists on stdin
// and asserts the emitted tag suffix (`-p` / `-s` / "").

import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { test } from "node:test";
import assert from "node:assert/strict";

const SCRIPT = join(dirname(fileURLToPath(import.meta.url)), "..", "scripts", "infer-release-scope.sh");

// Run via `bash` explicitly so the test doesn't depend on the +x bit
// surviving the checkout. Returns the raw stdout (the suffix, no newline).
function scopeOf(files) {
    return execFileSync("bash", [SCRIPT], { input: files.join("\n"), encoding: "utf8" });
}

test("plasma-only changes → -p", () => {
    assert.equal(scopeOf(["contents/ui/platforms/plasma/Theme.qml", "contents/ui/main.qml"]), "-p");
    assert.equal(scopeOf(["contents/config/main.xml"]), "-p");
    assert.equal(scopeOf(["contents/ui/configAbout.qml"]), "-p");
});

test("standalone-only changes → -s", () => {
    assert.equal(scopeOf(["standalone/main.cpp"]), "-s");
    assert.equal(scopeOf(["contents/ui/platforms/standalone/MetricsBackend.qml"]), "-s");
    assert.equal(scopeOf(["CMakeLists.txt", "scripts/build-appimage.sh", "packaging/dev.manuacl.ringmonitor.desktop"]), "-s");
});

test("any core/ change → no suffix (shared, both platforms)", () => {
    assert.equal(scopeOf(["contents/ui/core/Ring.qml"]), "");
    // core wins even when a single-platform file is also present.
    assert.equal(scopeOf(["contents/ui/core/UpdateCheck.js", "contents/ui/platforms/plasma/Theme.qml"]), "");
    assert.equal(scopeOf(["contents/ui/core/Ring.qml", "standalone/main.cpp"]), "");
});

test("both platforms touched → no suffix", () => {
    assert.equal(scopeOf(["contents/ui/platforms/plasma/Theme.qml", "standalone/main.cpp"]), "");
});

test("neutral-only changes (docs / CI / tests / metadata) → no suffix", () => {
    assert.equal(scopeOf(["docs/releasing.md", "README.md"]), "");
    assert.equal(scopeOf([".github/workflows/ci.yml", "metadata.json", "tests/ring-geometry.test.mjs"]), "");
    assert.equal(scopeOf([]), "");
    assert.equal(scopeOf([""]), "");
});

test("single-platform + neutral still resolves to that platform", () => {
    assert.equal(scopeOf(["contents/ui/platforms/plasma/Theme.qml", "docs/components.md", ".github/workflows/ci.yml"]), "-p");
    assert.equal(scopeOf(["standalone/main.cpp", "CHANGELOG.md"]), "-s");
});

test("platform-only .js logic beside each adapter classifies with its platform", () => {
    assert.equal(scopeOf(["contents/ui/platforms/standalone/ProcStatParser.js"]), "-s");
    assert.equal(scopeOf(["contents/ui/platforms/plasma/SensorPicking.js"]), "-p");
});
