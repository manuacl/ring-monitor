// Pure geometry math for the Ring component.
//
// Ring.qml uses a 270° arc starting at 135° (the 90° gap at the bottom is
// intentional — see CLAUDE.md "aesthetic guidelines"). All dimensions
// scale with the ring's smallest side so the widget stays proportional
// when resized.
//
// Dual-loaded by QML and Node. No `.pragma library`.

var BASE_START_ANGLE = 135;
var BASE_SWEEP_ANGLE = 270;

// Stroke / radius / font-size scaling rules, expressed as factors of `size`
// with a minimum floor in pixels (so things stay readable when tiny).
var DIMENSION_RULES = {
    ringStroke:   { factor: 0.055, min: 4  },
    nestedStroke: { factor: 0.017, min: 2  },
    nestedGap:    { factor: 0.022, min: 2  },
    labelPx:      { factor: 0.08,  min: 10 },
    valuePx:      { factor: 0.16,  min: 14 },
};

function clampPercent(p) {
    if (!isFinite(p)) return 0;
    if (p < 0) return 0;
    if (p > 100) return 100;
    return p;
}

function sweepForPercent(percent) {
    return BASE_SWEEP_ANGLE * clampPercent(percent) / 100;
}

function dimensionsFor(size) {
    if (!isFinite(size) || size <= 0) size = 0;
    function compute(rule) {
        return Math.max(rule.min, Math.round(size * rule.factor));
    }
    var ringStroke   = compute(DIMENSION_RULES.ringStroke);
    var nestedStroke = compute(DIMENSION_RULES.nestedStroke);
    var nestedGap    = compute(DIMENSION_RULES.nestedGap);
    // 2px padding from the edge for the main ring.
    var ringRadius = size / 2 - ringStroke / 2 - 2;
    return {
        ringStroke:   ringStroke,
        ringRadius:   ringRadius,
        nestedStroke: nestedStroke,
        nestedGap:    nestedGap,
        labelPx:      compute(DIMENSION_RULES.labelPx),
        valuePx:      compute(DIMENSION_RULES.valuePx),
    };
}

// Radius for the Nth nested (concentric) ring, indexed from 0 = outermost.
// Each level steps inward by (nestedStroke + nestedGap).
function nestedRadius(ringRadius, ringStroke, nestedStroke, nestedGap, index) {
    return ringRadius
         - ringStroke / 2
         - nestedGap
         - nestedStroke / 2
         - index * (nestedStroke + nestedGap);
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        BASE_START_ANGLE: BASE_START_ANGLE,
        BASE_SWEEP_ANGLE: BASE_SWEEP_ANGLE,
        clampPercent: clampPercent,
        sweepForPercent: sweepForPercent,
        dimensionsFor: dimensionsFor,
        nestedRadius: nestedRadius,
    };
}
