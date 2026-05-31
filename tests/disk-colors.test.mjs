// Tests for the per-partition disk ring color map (issue #67). The map helpers
// live in DiskMetrics.js (beside the label cache they share their JSON-map
// plumbing with — the dual-load convention forbids a separate importable
// module). The generic parseUuidMap / serializeUuidMap primitives are covered
// in disk-metrics.test.mjs; this file covers the color-semantic layer + the
// pruneMap bounding.

import { createRequire } from "node:module";
import { test } from "node:test";
import assert from "node:assert/strict";

const require = createRequire(import.meta.url);
const Disk = require("../contents/ui/core/DiskMetrics.js");

const A = "11111111-1111";
const B = "22222222-2222";

test("colorFor: returns the stored color, or '' when unset / non-string", () => {
    const json = Disk.withColor("", A, "#abcdef");
    assert.equal(Disk.colorFor(json, A), "#abcdef");
    assert.equal(Disk.colorFor(json, B), "", "unset id → empty string");
    assert.equal(Disk.colorFor("", A), "");
    assert.equal(Disk.colorFor('{"a":123}', "a"), "", "non-string value → empty");
});

test("withColor: sets a partition color immutably, leaving others intact", () => {
    let json = Disk.withColor("", A, "#ff0000");
    json = Disk.withColor(json, B, "#00ff00");
    assert.equal(Disk.colorFor(json, A), "#ff0000");
    assert.equal(Disk.colorFor(json, B), "#00ff00");
});

test("withColor: overwrites an existing entry", () => {
    let json = Disk.withColor("", A, "#ff0000");
    json = Disk.withColor(json, A, "#0000ff");
    assert.equal(Disk.colorFor(json, A), "#0000ff");
    assert.deepEqual(Disk.parseUuidMap(json), { [A]: "#0000ff" });
});

test("withoutColor: drops an entry → back to the general color; no-op when absent", () => {
    let json = Disk.withColor(Disk.withColor("", A, "#ff0000"), B, "#00ff00");
    json = Disk.withoutColor(json, A);
    assert.equal(Disk.colorFor(json, A), "", "cleared id inherits the shared color");
    assert.equal(Disk.colorFor(json, B), "#00ff00", "other entry untouched");
    assert.equal(Disk.withoutColor(json, "absent"), json, "removing an absent id is a stable no-op");
});

test("withoutColor: removing the last entry yields an empty map", () => {
    const json = Disk.withColor("", A, "#ff0000");
    assert.equal(Disk.withoutColor(json, A), "{}");
});

test("resolveRingColors: aligns to ids, custom where set else the fallback", () => {
    const fallback = "#3daee9";
    const json = Disk.withColor("", B, "#ff8800");
    // ids order is the ring order (outermost first); A has no override.
    assert.deepEqual(Disk.resolveRingColors([A, B], json, fallback), [fallback, "#ff8800"]);
});

test("resolveRingColors: empty map → every ring on the fallback; empty ids → []", () => {
    assert.deepEqual(Disk.resolveRingColors([A, B], "", "#123456"), ["#123456", "#123456"]);
    assert.deepEqual(Disk.resolveRingColors([], '{"a":"#fff"}', "#000"), []);
});

// ── pruneMap: bound the color map to the referenced partitions (#67/#3) ──
test("pruneMap: keeps referenced ids, drops the rest", () => {
    const json = Disk.withColor(Disk.withColor("", A, "#ff0000"), B, "#00ff00");
    // B no longer referenced (e.g. its partition was removed) → pruned.
    assert.deepEqual(Disk.parseUuidMap(Disk.pruneMap(json, [A])), { [A]: "#ff0000" });
});

test("pruneMap: unchecking keeps the color (partition still in the kept set)", () => {
    // An unchecked-but-still-ordered partition stays referenced → its color survives.
    const json = Disk.withColor("", A, "#ff0000");
    assert.equal(Disk.colorFor(Disk.pruneMap(json, [A, B]), A), "#ff0000");
});

test("pruneMap: empty keep set → empty map; stable serialization", () => {
    const json = Disk.withColor("", A, "#ff0000");
    assert.equal(Disk.pruneMap(json, []), "{}");
    assert.equal(Disk.pruneMap("", [A]), "{}");
});
