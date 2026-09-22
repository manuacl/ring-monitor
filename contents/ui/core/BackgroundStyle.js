// Pure logic for the optional widget background (issue #170).
//
// The background is one Rectangle painted behind the rings, with a
// two-stop gradient so it can fade out toward one edge and blend into
// the wallpaper. Everything the Rectangle needs beyond `Qt.rgba()` is
// computed here.
//
// Public surface:
//   DIRECTIONS                  - the persisted `backgroundGradient` values,
//                                 in the order the config combo lists them
//   normalizeDirection(dir)     - unknown / empty → "none"
//   isHorizontal(dir)           - Gradient.Horizontal vs Gradient.Vertical
//   clampOpacity(value)         - NaN / out-of-range → [0, 1]
//   startAlpha(dir, opacity)    - alpha of the stop at position 0.0
//   endAlpha(dir, opacity)      - alpha of the stop at position 1.0
//   featherPixels(pct, w, h)    - `backgroundEdgeSoftness` % → the blur
//                                 radius (px) that softens all four edges
//
// A direction names the edge the background fades OUT toward: "top"
// means transparent at the top, fully `backgroundOpacity` at the
// bottom. "none" makes both stops equal, i.e. a flat fill — one code
// path for both cases, so the Rectangle never branches on `gradient`
// vs `color`.
//
// Dual-loaded by QML (`import "BackgroundStyle.js" as BackgroundStyle`)
// and Node (via the module.exports shim at the bottom).

var DIRECTIONS = ["none", "top", "bottom", "left", "right"];

// A linear Gradient fades along ONE axis, so it can never soften the two
// edges perpendicular to it. The all-around soft edge is a blur instead
// (QtQuick.Effects MultiEffect), and 64 px is that effect's own blurMax
// ceiling — asking for more is silently ignored, so clamp here where the
// number is computed.
var MAX_FEATHER_PX = 64;
// Half the shorter side would blur the plate away entirely; a third
// still reads as a plate with soft edges.
var MAX_FEATHER_PERCENT = 33;

function normalizeDirection(dir) {
    return DIRECTIONS.indexOf(dir) >= 0 ? dir : "none";
}

function isHorizontal(dir) {
    var d = normalizeDirection(dir);
    return d === "left" || d === "right";
}

function clampOpacity(value) {
    var n = Number(value);
    if (!isFinite(n)) return 0;
    return Math.max(0, Math.min(1, n));
}

// Position 0.0 is the top edge (vertical) or the left edge (horizontal).
function startAlpha(dir, opacity) {
    var d = normalizeDirection(dir);
    return (d === "top" || d === "left") ? 0 : clampOpacity(opacity);
}

// Position 1.0 is the bottom edge (vertical) or the right edge (horizontal).
function endAlpha(dir, opacity) {
    var d = normalizeDirection(dir);
    return (d === "bottom" || d === "right") ? 0 : clampOpacity(opacity);
}

// Softness is a percentage of the SHORTER side so a wide horizontal strip
// and a tall vertical one get the same visual treatment; the result is
// both the blur radius and the inset the plate is drawn at, so the fade
// lands inside the widget instead of being clipped at its edge.
function featherPixels(softnessPercent, width, height) {
    var pct = clampPercent(softnessPercent);
    var side = Math.min(Number(width), Number(height));
    if (!isFinite(side) || side <= 0 || pct <= 0) return 0;
    return Math.min(MAX_FEATHER_PX, Math.round(side * pct / 100));
}

function clampPercent(value) {
    var n = Number(value);
    if (!isFinite(n)) return 0;
    return Math.max(0, Math.min(MAX_FEATHER_PERCENT, n));
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        DIRECTIONS: DIRECTIONS,
        normalizeDirection: normalizeDirection,
        isHorizontal: isHorizontal,
        clampOpacity: clampOpacity,
        startAlpha: startAlpha,
        endAlpha: endAlpha,
        featherPixels: featherPixels,
        clampPercent: clampPercent,
        MAX_FEATHER_PX: MAX_FEATHER_PX,
        MAX_FEATHER_PERCENT: MAX_FEATHER_PERCENT,
    };
}
