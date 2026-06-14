import { test } from "node:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import assert from "node:assert";

// Text-level guard for the tooltip placement chrome (issue #149). The chrome —
// popup-type heuristic, show-delay, grow-only width mark, edge anchor — used to
// be DUPLICATED across ProcessTooltip.qml and DiskTooltip.qml and was kept in
// sync by tooltip-placement-sync.test.mjs. It now lives once in the shared
// TooltipBehavior.qml helper, so this guard instead asserts:
//   1. TooltipBehavior owns the chrome (openRight, anchorMarker + guarded shift,
//      _applyPopupType with the popupType guard).
//   2. Each tooltip delegates to it (instantiates TooltipBehavior, parents its
//      ToolTip to behavior.anchorMarker) — the seam that replaced the copy-paste.
//   3. Each tooltip keeps the BODY as a DIRECT contentItem (ColumnLayout, never a
//      Loader) and still sets the transparent-for-input flag — the two
//      invariants the extraction must NOT break (core/CLAUDE.md § "The body must
//      be the popup's DIRECT contentItem").

const __dirname = dirname(fileURLToPath(import.meta.url));
const CORE = join(__dirname, "..", "contents", "ui", "core");
const read = (name) => readFileSync(join(CORE, name), "utf8");

const BEHAVIOR = read("TooltipBehavior.qml");
const PROCESS_TOOLTIP = read("ProcessTooltip.qml");
const DISK_TOOLTIP = read("DiskTooltip.qml");

const TOOLTIPS = [
    { name: "ProcessTooltip.qml", src: PROCESS_TOOLTIP },
    { name: "DiskTooltip.qml",    src: DISK_TOOLTIP },
];

// ── 1. TooltipBehavior owns the chrome ───────────────────────────────

test("TooltipBehavior declares the openRight input", () => {
    assert.match(
        BEHAVIOR,
        /property\s+bool\s+openRight\s*:/,
        "TooltipBehavior.qml must declare 'property bool openRight'"
    );
});

test("TooltipBehavior declares the anchorMarker with the Window-guarded x shift", () => {
    assert.match(BEHAVIOR, /id:\s*anchorMarker/, "must declare 'id: anchorMarker'");
    assert.match(
        BEHAVIOR,
        /x:\s*\(behavior\.openRight\s*&&\s*behavior\.tip\s*&&\s*behavior\.tip\.popupType\s*===\s*QQC2\.Popup\.Window\)\s*\?\s*behavior\.width\s*:\s*0/,
        "anchorMarker.x must bind to the openRight + Window-popup guarded shift"
    );
});

test("TooltipBehavior decides popupType per-show, guarded for Qt < 6.8", () => {
    assert.match(BEHAVIOR, /function\s+_applyPopupType\s*\(/, "must define _applyPopupType()");
    assert.match(
        BEHAVIOR,
        /behavior\.tip\.popupType\s*===\s*undefined/,
        "_applyPopupType must early-return when popupType is absent (Qt < 6.8)"
    );
});

test("TooltipBehavior owns the in-scene placement (inSceneX / inSceneY)", () => {
    assert.match(BEHAVIOR, /readonly\s+property\s+real\s+inSceneX\s*:/, "must expose inSceneX");
    assert.match(BEHAVIOR, /readonly\s+property\s+real\s+inSceneY\s*:/, "must expose inSceneY");
});

// The side is chosen by whether THIS tooltip actually fits on the right
// (`spaceRight >= w + gap`), not a fixed reference width — so a wide tooltip
// never lands half-off-screen and its ring-facing edge stays glued.
test("TooltipBehavior decides the side from the tooltip's own width", () => {
    assert.match(
        BEHAVIOR,
        /spaceRight\s*>=\s*w\s*\+\s*_gap/,
        "inSceneX must flip side on the tooltip's own width fitting on the right"
    );
});

// mapToGlobal() is not a reactive binding dependency, so the placement bindings
// re-read it via a nonce bumped on every hover-enter — otherwise moving the
// widget leaves the side decision computed against the ring's stale position.
test("TooltipBehavior re-reads mapToGlobal via a show nonce", () => {
    assert.match(BEHAVIOR, /property\s+int\s+_placeNonce/, "must declare _placeNonce");
    assert.match(BEHAVIOR, /behavior\._placeNonce\+\+/, "onSamplingActiveChanged must bump _placeNonce");
    const inSceneReads = BEHAVIOR.match(/behavior\._placeNonce\s*;/g) || [];
    assert.ok(
        inSceneReads.length >= 2,
        "inSceneX AND inSceneY must read _placeNonce to re-trigger on show"
    );
});

// ── 2. Each tooltip delegates the chrome to TooltipBehavior ───────────

for (const { name, src } of TOOLTIPS) {
    test(`${name} instantiates TooltipBehavior and parents its ToolTip to its anchorMarker`, () => {
        assert.match(src, /TooltipBehavior\s*\{/, `${name} must instantiate TooltipBehavior`);
        assert.match(
            src,
            /parent\s*:\s*behavior\.anchorMarker/,
            `${name} must set 'parent: behavior.anchorMarker' on the ToolTip`
        );
        assert.match(
            src,
            /x:\s*behavior\.inSceneX/,
            `${name} must bind its in-scene x to behavior.inSceneX`
        );
        assert.match(
            src,
            /y:\s*behavior\.inSceneY/,
            `${name} must bind its in-scene y to behavior.inSceneY`
        );
    });
}

// ── 3. The body stays a DIRECT contentItem + keeps the input flag ─────
//    These are the invariants the extraction must not regress: a Loader
//    contentItem makes a Window popup render wrong, and dropping the flag
//    reintroduces the pointer-grab flicker (QTBUG-38084).

for (const { name, src } of TOOLTIPS) {
    test(`${name} keeps the body as a direct ColumnLayout contentItem (no Loader)`, () => {
        assert.match(
            src,
            /contentItem\s*:\s*ColumnLayout\s*\{/,
            `${name} body must be an inline ColumnLayout contentItem`
        );
        assert.doesNotMatch(
            src,
            /contentItem\s*:\s*Loader\b/,
            `${name} must NOT host its body via a Loader contentItem`
        );
    });

    test(`${name} sets Qt.WindowTransparentForInput on the popup window`, () => {
        assert.match(
            src,
            /w\.flags\s*=\s*w\.flags\s*\|\s*Qt\.WindowTransparentForInput/,
            `${name} must assign the transparent-for-input flag in onWindowChanged`
        );
    });

    // Closing instantly (empty exit Transition) — a fading-out popup lingers a
    // frame with its content already emptied: an empty-flash AND, overlapping the
    // neighbour ring, a hover thief that closes the next ring's tooltip.
    test(`${name} closes instantly (empty exit Transition)`, () => {
        assert.match(
            src,
            /exit\s*:\s*Transition\s*\{\s*\}/,
            `${name} must set 'exit: Transition {}' so the popup hides without a fade`
        );
    });

    // The grow-only width mark is for the Window popup only (it can't auto-size);
    // the in-scene popup must equal its content, else a marked surplus detaches
    // the text from the ring on the left side.
    test(`${name} applies the grow-only width mark only to the Window popup`, () => {
        assert.match(
            src,
            /popupType\s*===\s*QQC2\.Popup\.Window\s*\?\s*Math\.max\(behavior\._maxContentWidth/,
            `${name} width must gate the high-water mark on the Window popup type`
        );
    });
}
