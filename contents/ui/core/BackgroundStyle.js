// Pure logic for the optional widget background (issue #170).
//
// The background is a halo: a stadium (pill) behind the rings whose caps
// follow the end rings, optionally grown past them and faded to
// transparent at its edge. Everything WidgetBackground.qml draws beyond
// `Qt.rgba()` is computed here.
//
// Public surface:
//   clampOpacity(value)            - NaN / out-of-range → [0, 1]
//   clampPercent(value, max)       - NaN / out-of-range → [0, max]
//   ringBounds(cells)              - the stadium hugging the drawn rings
//   spreadBounds(bounds, pct)      - that stadium grown by `pct` % of the
//                                    ring radius on every side
//   featherPixels(pct, w, h)       - `backgroundEdgeSoftness` % → width (px)
//                                    of the fade band along the edge
//   haloGeometry(w, h, feather)    - the three paths and their stops
//
// Dual-loaded by QML (`import "BackgroundStyle.js" as BackgroundStyle`)
// and Node (via the module.exports shim at the bottom).

// Half the shorter side = the cap radius: the fade then starts at the
// strip's centre line, a pure glow with no solid core.
var MAX_FEATHER_PERCENT = 50;
// One ring radius of extra halo on every side: the halo is then twice as
// thick as the rings.
var MAX_SPREAD_PERCENT = 100;

function clampOpacity(value) {
    var n = Number(value);
    if (!isFinite(n)) return 0;
    return Math.max(0, Math.min(1, n));
}

function clampPercent(value, max) {
    var n = Number(value);
    if (!isFinite(n)) return 0;
    return Math.max(0, Math.min(max === undefined ? MAX_FEATHER_PERCENT : max, n));
}

// Stadium hugging the rings: each cell draws its ring as a square of side
// min(w, h) centred in the cell (Ring.qml), so the union of those squares is
// the strip, and half its shorter side is the ring radius — the pill's caps
// then follow the end rings exactly. Cells come from the live layout, not
// the host's size: a Plasma applet can be bigger than the ring strip.
// Returns null when there is no sized cell yet.
function ringBounds(cells) {
    var left = Infinity, top = Infinity, right = -Infinity, bottom = -Infinity;
    for (var i = 0; i < (cells || []).length; i++) {
        var c = cells[i];
        var side = Math.min(Number(c.width), Number(c.height));
        if (!isFinite(side) || side <= 0) continue;
        var x = Number(c.x) + (Number(c.width) - side) / 2;
        var y = Number(c.y) + (Number(c.height) - side) / 2;
        left = Math.min(left, x);
        top = Math.min(top, y);
        right = Math.max(right, x + side);
        bottom = Math.max(bottom, y + side);
    }
    if (left === Infinity) return null;
    var width = right - left;
    var height = bottom - top;
    return { x: left, y: top, width: width, height: height, radius: Math.min(width, height) / 2 };
}

// Grown from the ring radius rather than in pixels so the halo keeps its
// proportions at any ring size. The caps grow by the same margin, so they
// stay concentric with the end rings. Past the host's edge the halo is
// simply drawn outside it (Plasma does not clip applets; a standalone
// window does).
function spreadBounds(bounds, pct) {
    if (!bounds) return null;
    var m = Math.round(bounds.radius * clampPercent(pct, MAX_SPREAD_PERCENT) / 100);
    return { x: bounds.x - m, y: bounds.y - m, width: bounds.width + 2 * m, height: bounds.height + 2 * m, radius: bounds.radius + m };
}

// Softness is a percentage of the SHORTER side so a wide horizontal strip
// and a tall vertical one get the same visual treatment; the result is
// the band, measured inward from the edge, over which the halo goes from
// transparent to full opacity.
function featherPixels(softnessPercent, width, height) {
    var pct = clampPercent(softnessPercent);
    var side = Math.min(Number(width), Number(height));
    if (!isFinite(side) || side <= 0 || pct <= 0) return 0;
    return Math.round(side * pct / 100);
}

// The soft edge is an alpha ramp falling linearly to 0 over the last
// `feather` px of the stadium, on every side: a linear gradient across the
// straight body and a radial one on each half-disc cap (same distance to
// the edge on both sides of the seam, so they meet without a step). A blur
// cannot do this — it spreads the edge both ways and reads as the plate
// shrinking. Seams sit on whole pixels so the anti-aliased edges of
// adjacent paths don't overlap into a visible line. Coordinates are local
// to the stadium's box; `t` is its thickness, `r` the cap radius.
// feather 0 → edgeAlpha 1: the "fade" stops are opaque, a crisp stadium.
function haloGeometry(width, height, feather) {
    var w = Math.max(0, Number(width) || 0);
    var h = Math.max(0, Number(height) || 0);
    var horizontal = w >= h;
    var t = horizontal ? h : w;
    var len = horizontal ? w : h;
    var r = t / 2;
    var f = Math.max(0, Math.min(r, Number(feather) || 0));
    var a = Math.min(Math.round(r), len / 2);
    var b = len - a;
    // (along, across) → (x, y) for the strip's orientation.
    function pt(along, across) {
        return horizontal ? { x: along, y: across } : { x: across, y: along };
    }
    return {
        r: r,
        edgeAlpha: f > 0 ? 0 : 1,
        fadeStop: t > 0 ? f / t : 0,
        capStop: r > 0 ? (r - f) / r : 1,
        body: [pt(a, 0), pt(b, 0), pt(b, t), pt(a, t)],
        across: { start: pt(0, 0), end: pt(0, t) },
        // Each cap runs from the across=0 side to the across=t side of its
        // seam. Screen y points down, so the start cap bulges
        // counterclockwise when horizontal (leftward) but clockwise when
        // vertical (upward); the end cap is the mirror.
        capA: { start: pt(a, 0), end: pt(a, t), center: pt(a, r), clockwise: !horizontal },
        capB: { start: pt(b, 0), end: pt(b, t), center: pt(b, r), clockwise: horizontal }
    };
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        clampOpacity: clampOpacity,
        clampPercent: clampPercent,
        ringBounds: ringBounds,
        spreadBounds: spreadBounds,
        featherPixels: featherPixels,
        haloGeometry: haloGeometry,
        MAX_FEATHER_PERCENT: MAX_FEATHER_PERCENT,
        MAX_SPREAD_PERCENT: MAX_SPREAD_PERCENT,
    };
}
