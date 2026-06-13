import { test } from "node:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import assert from "node:assert";

// Text-level sync guard for the tooltip placement chrome shared (but
// DUPLICATED — see core/CLAUDE.md § "The body must be the popup's DIRECT
// contentItem") by ProcessTooltip.qml and DiskTooltip.qml.
//
// Four placement features must be present in both files and stay in lock-step:
//   1. `property bool openRight` input — which side the Window popup opens toward.
//   2. anchorMarker.x binding — `root.openRight ? root.width : 0` — pins the
//      1×1 anchor at the ring's interior-facing top corner so the compositor
//      grows the popup into the screen.
//   3. `closePolicy: QQC2.Popup.NoAutoClose` — tooltip is hover-driven only;
//      combined with the transparent-for-input flag so the popup doesn't steal
//      the pointer from the ring's HoverHandler and flicker (QTBUG-38084).
//   4. `Qt.WindowTransparentForInput` — set on the separate popup window in the
//      contentItem's onWindowChanged handler to prevent pointer-grab flickering.
//
// Both files are "must keep in sync" (documented in core/CLAUDE.md), so this
// guard detects drift between them — the same class of risk as the
// Theme-adapter sync guard in standalone-theme.test.mjs.

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROCESS_TOOLTIP = readFileSync(
    join(__dirname, "..", "contents", "ui", "core", "ProcessTooltip.qml"),
    "utf8"
);
const DISK_TOOLTIP = readFileSync(
    join(__dirname, "..", "contents", "ui", "core", "DiskTooltip.qml"),
    "utf8"
);

const FILES = [
    { name: "ProcessTooltip.qml", src: PROCESS_TOOLTIP },
    { name: "DiskTooltip.qml",    src: DISK_TOOLTIP },
];

// 1. Both declare `property bool openRight`

test("ProcessTooltip.qml declares property bool openRight", () => {
    assert.match(
        PROCESS_TOOLTIP,
        /property\s+bool\s+openRight\s*:/,
        "ProcessTooltip.qml must declare 'property bool openRight'"
    );
});

test("DiskTooltip.qml declares property bool openRight", () => {
    assert.match(
        DISK_TOOLTIP,
        /property\s+bool\s+openRight\s*:/,
        "DiskTooltip.qml must declare 'property bool openRight'"
    );
});

// 2. Both bind anchorMarker.x to `root.openRight ? root.width : 0`
//    Matches the literal in the source (checked against both QML files).

for (const { name, src } of FILES) {
    test(`${name} has anchorMarker with x bound to openRight ? root.width : 0`, () => {
        // Match the anchorMarker block and its x binding in sequence: the id
        // declaration followed (within the same block) by the ternary binding.
        // We do two focused assertions rather than one complex regex:
        //   (a) the marker id exists
        //   (b) the ternary binding expression exists in the file
        assert.match(src, /id:\s*anchorMarker/, `${name} must declare 'id: anchorMarker'`);
        assert.match(
            src,
            /x:\s*root\.openRight\s*\?\s*root\.width\s*:\s*0/,
            `${name} anchorMarker.x must bind to 'root.openRight ? root.width : 0'`
        );
    });
}

// 3. Both set closePolicy: QQC2.Popup.NoAutoClose on the ToolTip

for (const { name, src } of FILES) {
    test(`${name} sets closePolicy: QQC2.Popup.NoAutoClose`, () => {
        assert.match(
            src,
            /closePolicy\s*:\s*QQC2\.Popup\.NoAutoClose/,
            `${name} must set 'closePolicy: QQC2.Popup.NoAutoClose' on the ToolTip`
        );
    });
}

// 4. Both set Qt.WindowTransparentForInput on the separate popup window
//    Match on the assignment call-shape, not the bare symbol name, to avoid
//    matching only a comment that mentions the flag (see tests/CLAUDE.md
//    § "A doesNotMatch guard targets the *call*, not the bare symbol").

for (const { name, src } of FILES) {
    test(`${name} sets Qt.WindowTransparentForInput on the popup window`, () => {
        assert.match(
            src,
            /w\.flags\s*=\s*w\.flags\s*\|\s*Qt\.WindowTransparentForInput/,
            `${name} must assign 'w.flags = w.flags | Qt.WindowTransparentForInput' in onWindowChanged`
        );
    });
}

// 5. Both set tip.parent to anchorMarker (so the compositor uses the marker
//    as the anchor rect for Window-type popup placement).

for (const { name, src } of FILES) {
    test(`${name} sets ToolTip parent to anchorMarker`, () => {
        assert.match(
            src,
            /parent\s*:\s*anchorMarker/,
            `${name} must set 'parent: anchorMarker' on the ToolTip`
        );
    });
}
