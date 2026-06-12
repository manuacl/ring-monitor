// Pure placement math for the standalone window. Standalone-only
// logic (the Plasma panel positions its own slot), so it lives beside
// the adapter rather than in core/ — shipping it in the .plasmoid zip
// would be dead code.
//
// Two host paths consume this (see platforms/standalone/Main.qml
// _anchor() and standalone/wayland_layer_shell.cpp):
//
//   X11 / XWayland   the window is a managed toplevel we position with
//                    an absolute (x, y) origin → computeX11Origin().
//   Wayland layer-shell  the compositor positions the surface from
//                    anchor edges + margins; there is no free x/y, so
//                    we only resolve which edges to anchor to →
//                    cornerToAnchorSpec(). The C++ side maps the spec
//                    to LayerShellQt anchor enums + QMargins.
//
// Keeping the corner → edges decision HERE (not duplicated in C++)
// makes it the single tested source of truth for both paths.
//
// Dual-loaded by QML and Node (module.exports shim at the bottom).

// The four supported anchor corners. No "center" — margins would be
// meaningless there, and the issue #98 use case is edge placement.
var CORNERS = ["top-left", "top-right", "bottom-left", "bottom-right"];

// Default mirrors the historic top-right anchor so an un-set config
// reproduces the pre-#98 behaviour byte-for-byte.
function _normalizeCorner(corner) {
    return CORNERS.indexOf(corner) !== -1 ? corner : "top-right";
}

// Resolve a corner to the two edges its margins inset from. `left`/`top`
// false mean the opposite edge (right/bottom).
function cornerToAnchorSpec(corner) {
    corner = _normalizeCorner(corner);
    return {
        left: corner === "top-left" || corner === "bottom-left",
        top: corner === "top-left" || corner === "top-right"
    };
}

// Absolute top-left origin (x, y) of the window for the X11 path.
// `marginX`/`marginY` inset from the anchored horizontal/vertical edge;
// the opposite-corner cases subtract the window extent so the content
// stays fully on-screen. Callers pass an already screen-capped winW/winH.
//
// `screenX`/`screenY`: virtual-desktop origin of the target screen.
// QWindow::setGeometry is virtual-desktop-absolute on X11; without these
// offsets every anchor always lands on the leftmost screen (issue #142).
// Omitting them (or passing undefined/non-finite) is back-compat with the
// single-screen case where the origin is implicitly (0, 0).
function computeX11Origin(corner, screenW, screenH, winW, winH, marginX, marginY, screenX, screenY) {
    var spec = cornerToAnchorSpec(corner);
    var ox = isFinite(screenX) ? screenX : 0;
    var oy = isFinite(screenY) ? screenY : 0;
    var x = ox + (spec.left ? marginX : screenW - winW - marginX);
    var y = oy + (spec.top ? marginY : screenH - winH - marginY);
    return { x: x, y: y };
}

// Find a screen by name from an array-like screens list.
// Returns the first entry whose `.name === name`, or null when:
//   - `name` is falsy (no preference — caller uses the current screen)
//   - `screens` is null/undefined or has no numeric `length`
//   - no entry matches (unknown name)
// QML passes Qt.application.screens, a QQmlListProperty — array-like
// (length + integer index) but not a JS Array, so Array.isArray() returns
// false. Guard on a numeric `length` instead.
// The caller is responsible for falling back to the window's current screen.
function pickScreen(screens, name) {
    if (!name || !screens || typeof screens.length !== "number") {
        return null;
    }
    for (var i = 0; i < screens.length; i++) {
        if (screens[i].name === name) {
            return screens[i];
        }
    }
    return null;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        CORNERS: CORNERS,
        cornerToAnchorSpec: cornerToAnchorSpec,
        computeX11Origin: computeX11Origin,
        pickScreen: pickScreen
    };
}
