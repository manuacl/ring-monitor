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

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        DIRECTIONS: DIRECTIONS,
        normalizeDirection: normalizeDirection,
        isHorizontal: isHorizontal,
        clampOpacity: clampOpacity,
        startAlpha: startAlpha,
        endAlpha: endAlpha,
    };
}
