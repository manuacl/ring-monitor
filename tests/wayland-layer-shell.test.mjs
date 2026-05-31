// Text-level guards for the native Wayland (wlr-layer-shell) C++ files
// `standalone/wayland_layer_shell.{cpp,h}`. Like `desktop_hints.cpp`,
// they link a C++-only library (layer-shell-qt) and can't be loaded by
// qmltestrunner-qt6 or driven from a Node unit test — same text-guard
// pattern as `desktop-hints.test.mjs` / `autostart.test.mjs`.
//
// The contract these guards lock in:
//
//   1. The layer surface is a BOTTOM layer, anchored to a caller-chosen
//      corner (issue #98), with no keyboard interactivity and zero
//      exclusive zone — a wallpaper widget that never enters Alt+Tab and
//      never reserves screen space. This is the whole reason C2 exists
//      (the XWayland NORMAL window can't shed those two warts).
//   2. Every layer-shell-qt call is behind `#ifdef HAVE_LAYER_SHELL_QT`,
//      and the class is otherwise a no-op — so the binary still builds
//      and the QML singleton still registers when layer-shell-qt is
//      absent (the dev box without the rpm-ostree layer).
//   3. No Plasma headers — standalone isolation invariant.

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const SRC = readFileSync(
    join(__dirname, "..", "standalone", "wayland_layer_shell.cpp"),
    "utf8",
);
const HEADER = readFileSync(
    join(__dirname, "..", "standalone", "wayland_layer_shell.h"),
    "utf8",
);

test("configures a BOTTOM layer surface (not background)", () => {
    // SCENARIO: the `background` layer sits at/below Plasma's desktop
    // containment, so a desktop click occluded the widget (it vanished —
    // same bug as the X11 DESKTOP window type). `bottom` sits above the
    // wallpaper and below normal windows: survives the click, never
    // covers app windows.
    assert.match(
        SRC,
        /setLayer\(\s*LayerShellQt::Window::LayerBottom\s*\)/,
        "must place the surface on the bottom layer (above wallpaper, below windows)",
    );
    assert.doesNotMatch(
        SRC,
        /LayerBackground/,
        "must NOT use LayerBackground — it's occluded by Plasma's desktop containment on a desktop click",
    );
});

test("anchors the surface to the caller-chosen corner", () => {
    // Issue #98: the corner is configurable. The .cpp picks the horizontal
    // edge from `anchorLeft` (AnchorLeft else AnchorRight) and the vertical
    // from `anchorTop` (AnchorTop else AnchorBottom), then ORs them — so all
    // four corner enums must appear and the choice flows from the booleans.
    for (const anchor of ["AnchorLeft", "AnchorRight", "AnchorTop", "AnchorBottom"]) {
        assert.match(SRC, new RegExp(`LayerShellQt::Window::${anchor}\\b`), `must reference ${anchor} for corner mapping`);
    }
    assert.match(SRC, /anchorLeft\s*\?/, "horizontal anchor must be driven by anchorLeft");
    assert.match(SRC, /anchorTop\s*\?/, "vertical anchor must be driven by anchorTop");
    assert.match(
        SRC,
        /setAnchors\([\s\S]*?horizontal[\s\S]*?vertical[\s\S]*?\)/,
        "must OR the chosen horizontal + vertical anchors into setAnchors",
    );
});

test("insets the X/Y margins from the anchored edges", () => {
    // QMargins(left, top, right, bottom): the X margin maps to left OR
    // right per anchorLeft, the Y margin to top OR bottom per anchorTop.
    assert.match(
        SRC,
        /setMargins\(QMargins\([\s\S]*?anchorLeft\s*\?\s*marginX[\s\S]*?anchorTop\s*\?\s*marginY[\s\S]*?\)\)/,
        "must route marginX/marginY to the anchored edges",
    );
});

test("takes keyboard focus on demand and reserves no space", () => {
    // OnDemand (not None): the xdg_popup context menu needs the parent
    // surface to take seat focus for its grab to install — None made the
    // menu open fullscreen + un-closeable. Exclusive zone 0 means it
    // doesn't push panels/maximised windows around — a wallpaper widget,
    // not a dock.
    assert.match(
        SRC,
        /setKeyboardInteractivity\(\s*LayerShellQt::Window::KeyboardInteractivityOnDemand\s*\)/,
        "must set KeyboardInteractivityOnDemand (None breaks the right-click menu's popup grab)",
    );
    assert.doesNotMatch(
        SRC,
        /setKeyboardInteractivity\([^)]*KeyboardInteractivityNone/,
        "must NOT call setKeyboardInteractivity(...None) — it left the context menu fullscreen + un-dismissable",
    );
    assert.match(
        SRC,
        /setExclusiveZone\(\s*0\s*\)/,
        "must set exclusive zone to 0",
    );
});

test("gets the layer controller via LayerShellQt::Window::get", () => {
    assert.match(
        SRC,
        /LayerShellQt::Window::get\(/,
        "must obtain the per-window controller from LayerShellQt::Window::get",
    );
});

test("all layer-shell-qt use is guarded by HAVE_LAYER_SHELL_QT", () => {
    // Without the build flag the class must compile to a no-op (active()
    // false, configure() a no-op) so the X11/XWayland-only build is
    // byte-for-byte unchanged and the QML singleton still registers.
    assert.match(
        SRC,
        /#ifdef HAVE_LAYER_SHELL_QT/,
        "the .cpp must gate the layer-shell calls behind #ifdef HAVE_LAYER_SHELL_QT",
    );
    assert.match(
        SRC,
        /#include\s*<LayerShellQt\/Window>/,
        "the LayerShellQt include must itself sit under the guard",
    );
    // The include must be inside the guard, not at file scope — assert it
    // appears AFTER the first #ifdef.
    assert.ok(
        SRC.indexOf("#ifdef HAVE_LAYER_SHELL_QT") <
            SRC.indexOf("#include <LayerShellQt/Window>"),
        "the LayerShellQt include must come after the #ifdef guard, not before it",
    );
});

test("registers as a QML singleton with a constant active property", () => {
    assert.match(HEADER, /QML_ELEMENT/, "must carry QML_ELEMENT");
    assert.match(HEADER, /QML_SINGLETON/, "must be a QML_SINGLETON");
    assert.match(
        HEADER,
        /Q_PROPERTY\(\s*bool\s+active\s+READ\s+active\s+CONSTANT\s*\)/,
        "must expose a constant `active` bool property (drives Main.qml's visible + anchor branch)",
    );
});

test("wayland_layer_shell includes no Plasma headers (standalone isolation)", () => {
    assert.doesNotMatch(
        SRC,
        /#include\s*<plasma\//,
        "wayland_layer_shell.cpp must not include Plasma headers",
    );
    assert.doesNotMatch(
        HEADER,
        /#include\s*<plasma\//,
        "wayland_layer_shell.h must not include Plasma headers",
    );
});
