// Tests for DiskColors.js — the per-partition disk ring color map (issue #67).

import { createRequire } from "node:module";
import { test } from "node:test";
import assert from "node:assert/strict";

const require = createRequire(import.meta.url);
const DiskColors = require("../contents/ui/core/DiskColors.js");

const A = "11111111-1111";
const B = "22222222-2222";

test("parseColors: empty / malformed → {}", () => {
    assert.deepEqual(DiskColors.parseColors(""), {});
    assert.deepEqual(DiskColors.parseColors(undefined), {});
    assert.deepEqual(DiskColors.parseColors("not json"), {});
    assert.deepEqual(DiskColors.parseColors("[1,2]"), {}, "a JSON array is not a map");
    assert.deepEqual(DiskColors.parseColors("null"), {});
});

test("parseColors: valid object round-trips", () => {
    assert.deepEqual(DiskColors.parseColors('{"a":"#ff0000"}'), { a: "#ff0000" });
});

test("serializeColors: sorted keys → stable string regardless of insertion order", () => {
    const s1 = DiskColors.serializeColors({ [B]: "#00ff00", [A]: "#ff0000" });
    const s2 = DiskColors.serializeColors({ [A]: "#ff0000", [B]: "#00ff00" });
    assert.equal(s1, s2, "same map → same string (no spurious config write)");
    assert.equal(s1, `{"${A}":"#ff0000","${B}":"#00ff00"}`);
});

test("colorFor: returns the stored color, or '' when unset / non-string", () => {
    const json = DiskColors.withColor("", A, "#abcdef");
    assert.equal(DiskColors.colorFor(json, A), "#abcdef");
    assert.equal(DiskColors.colorFor(json, B), "", "unset id → empty string");
    assert.equal(DiskColors.colorFor("", A), "");
    assert.equal(DiskColors.colorFor('{"a":123}', "a"), "", "non-string value → empty");
});

test("withColor: sets a partition color immutably, leaving others intact", () => {
    let json = DiskColors.withColor("", A, "#ff0000");
    json = DiskColors.withColor(json, B, "#00ff00");
    assert.equal(DiskColors.colorFor(json, A), "#ff0000");
    assert.equal(DiskColors.colorFor(json, B), "#00ff00");
});

test("withColor: overwrites an existing entry", () => {
    let json = DiskColors.withColor("", A, "#ff0000");
    json = DiskColors.withColor(json, A, "#0000ff");
    assert.equal(DiskColors.colorFor(json, A), "#0000ff");
    assert.deepEqual(DiskColors.parseColors(json), { [A]: "#0000ff" });
});

test("withoutColor: drops an entry → back to the general color; no-op when absent", () => {
    let json = DiskColors.withColor(DiskColors.withColor("", A, "#ff0000"), B, "#00ff00");
    json = DiskColors.withoutColor(json, A);
    assert.equal(DiskColors.colorFor(json, A), "", "cleared id inherits the shared color");
    assert.equal(DiskColors.colorFor(json, B), "#00ff00", "other entry untouched");
    // Removing an absent id is a no-op that still serializes stably.
    assert.equal(DiskColors.withoutColor(json, "absent"), json);
});

test("withoutColor: removing the last entry yields an empty map", () => {
    const json = DiskColors.withColor("", A, "#ff0000");
    assert.equal(DiskColors.withoutColor(json, A), "{}");
});

test("resolveRingColors: aligns to ids, custom where set else the fallback", () => {
    const fallback = "#3daee9";
    const json = DiskColors.withColor("", B, "#ff8800");
    // ids order is the ring order (outermost first); A has no override.
    assert.deepEqual(
        DiskColors.resolveRingColors([A, B], json, fallback),
        [fallback, "#ff8800"],
    );
});

test("resolveRingColors: empty map → every ring on the fallback", () => {
    assert.deepEqual(
        DiskColors.resolveRingColors([A, B], "", "#123456"),
        ["#123456", "#123456"],
    );
});

test("resolveRingColors: empty ids → []", () => {
    assert.deepEqual(DiskColors.resolveRingColors([], '{"a":"#fff"}', "#000"), []);
});
