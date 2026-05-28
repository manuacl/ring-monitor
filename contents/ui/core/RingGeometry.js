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

// Split-mode geometry: each half is 135° geometrically (half of
// BASE_SWEEP_ANGLE), but the rendered sweep is shortened by
// SPLIT_GAP_ANGLE/2 so the two RoundCap endpoints don't overlap at the
// top. The two halves grow bottom-up from the edges of the existing
// 90° bottom gap toward 12 o'clock (270° in Qt's PathAngleArc
// convention where 0°=east, positive sweep=clockwise).
//
//   Left half  (usage):  start=135 (~7h), sweep +clockwise        → near top
//   Right half (temp):   start=45  (~5h), sweep -anticlockwise    → near top
//
// At 100% the active arcs (and tracks) stop ~3° before 270° on each
// side, leaving a clean ~6° symmetric gap that mirrors the 90° gap at
// the bottom in miniature. Without it the RoundCap extension would
// crush the two endpoints into each other.
var LEFT_HALF_START = 135;
var RIGHT_HALF_START = 45;
var HALF_SWEEP_ANGLE = 135;
var SPLIT_GAP_ANGLE = 8;

// Stroke / radius / font-size scaling rules, expressed as factors of `size`
// with a minimum floor in pixels (so things stay readable when tiny).
//
// nestedStroke / nestedGap are kept here as the "comfortable size" — the
// values nestedRingLayout uses when there's room to spare. Past a
// threshold count the layout shrinks both to keep the cores stack
// within the same fixed envelope regardless of N.
var DIMENSION_RULES = {
    ringStroke:   { factor: 0.055, min: 4  },
    nestedStroke: { factor: 0.017, min: 2  },
    nestedGap:    { factor: 0.022, min: 2  },
    labelPx:      { factor: 0.08,  min: 10 },
    valuePx:      { factor: 0.16,  min: 14 },
};

// Cores rings stay at the "comfortable" stroke + gap up to this count.
// Past it, the stack would creep toward the centre text — so we lock
// the visual envelope at COMFORT_RING_COUNT × (stroke + gap) and shrink
// the per-ring metrics to fit. 7 picked deliberately so the dev-rig
// 6-core case stays unchanged and there's room for one more before
// scaling kicks in.
var COMFORT_RING_COUNT = 7;

// Equal-thickness concentric rings (disk multi-partition mode) stay at the
// main ring's full stroke up to this count. Past it the layout shrinks the
// stroke + gap to keep the stack inside the same envelope — same strategy as
// COMFORT_RING_COUNT for the thin cores rings, but fewer because each disk
// ring is as thick as the main ring (0.055 vs 0.017 of size).
var DISK_COMFORT_RING_COUNT = 5;

function clampPercent(p) {
    if (!isFinite(p)) return 0;
    if (p < 0) return 0;
    if (p > 100) return 100;
    return p;
}

function sweepForPercent(percent) {
    return BASE_SWEEP_ANGLE * clampPercent(percent) / 100;
}

// Split-mode sweeps: each grows from a bottom gap edge toward the top.
// Left grows clockwise (positive sweep), right grows anticlockwise
// (negative). Both top out at HALF_SWEEP_ANGLE − SPLIT_GAP_ANGLE/2 to
// leave the symmetric top gap (see SPLIT_GAP_ANGLE rationale above).
function effectiveHalfSweep() {
    return HALF_SWEEP_ANGLE - SPLIT_GAP_ANGLE / 2;
}

function leftHalfSweepFor(percent) {
    return effectiveHalfSweep() * clampPercent(percent) / 100;
}

function rightHalfSweepFor(percent) {
    // `+ 0` normalises -0 → 0 so strict-equal tests don't surprise.
    return -effectiveHalfSweep() * clampPercent(percent) / 100 + 0;
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

// Layout for the concentric nested rings (per-core CPU usage rings).
//
// Strategy: each ring needs (stroke + gap) of radial space. Total span
// for N rings = N × (stroke + gap). Up to COMFORT_RING_COUNT (7),
// we use the preferred stroke / gap directly — the cores stack
// occupies its natural zone, growing inward as cores are added.
// Past 7, we lock the envelope at 7 × (preferred stroke + gap) and
// scale stroke = gap = envelope / (2 × count) so the stack always
// ends at the same inner radius regardless of core count.
//
// Returns:
//   {
//     stroke: pixel width of each nested ring,
//     gap:    pixel gap between consecutive rings (and between the
//             outermost ring and the main ring),
//     radii:  [r0, r1, ...] center radius per ring, outermost first.
//   }
function nestedRingLayout(ringRadius, ringStroke, preferredStroke, preferredGap, count) {
    if (!isFinite(count) || count <= 0) return { stroke: 0, gap: 0, radii: [] };
    var outerEdge = ringRadius - ringStroke / 2;   // inner edge of the main ring
    var stroke, gap;
    if (count <= COMFORT_RING_COUNT) {
        stroke = preferredStroke;
        gap = preferredGap;
    } else {
        // Lock to the 7-ring envelope and divide it evenly between
        // stroke and gap. 1 px floor so 32-core+ stacks still render
        // distinct bands instead of a solid fill.
        var envelope = COMFORT_RING_COUNT * (preferredStroke + preferredGap);
        var unit = Math.max(1, envelope / (2 * count));
        stroke = unit;
        gap = unit;
    }
    var radii = [];
    for (var i = 0; i < count; i++) {
        radii.push(outerEdge - gap - stroke / 2 - i * (stroke + gap));
    }
    return { stroke: stroke, gap: gap, radii: radii };
}

// Layout for equal-thickness concentric rings (disk multi-partition mode).
//
// Unlike nestedRingLayout (thin rings nested INSIDE a separate main ring),
// here the outermost ring IS at the main radius — there is no distinct
// aggregate ring above them. Each partition is one full-stroke ring stepping
// inward by (stroke + gap). Up to DISK_COMFORT_RING_COUNT the preferred
// (full) stroke / gap are used; past it, stroke = gap = envelope / (2 × count)
// so the stack always ends at the same inner radius regardless of partition
// count (the 1px floor keeps many-partition stacks as distinct bands).
//
// Returns:
//   {
//     stroke: pixel width of each ring,
//     gap:    pixel gap between consecutive rings,
//     radii:  [r0, r1, ...] center radius per ring, outermost first
//             (radii[0] === ringRadius — the main-ring position).
//   }
function equalRingLayout(ringRadius, preferredStroke, preferredGap, count) {
    if (!isFinite(count) || count <= 0) return { stroke: 0, gap: 0, radii: [] };
    var stroke, gap;
    if (count <= DISK_COMFORT_RING_COUNT) {
        stroke = preferredStroke;
        gap = preferredGap;
    } else {
        var envelope = DISK_COMFORT_RING_COUNT * (preferredStroke + preferredGap);
        var unit = Math.max(1, envelope / (2 * count));
        stroke = unit;
        gap = unit;
    }
    var radii = [];
    for (var i = 0; i < count; i++) {
        radii.push(ringRadius - i * (stroke + gap));
    }
    return { stroke: stroke, gap: gap, radii: radii };
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        BASE_START_ANGLE: BASE_START_ANGLE,
        BASE_SWEEP_ANGLE: BASE_SWEEP_ANGLE,
        LEFT_HALF_START: LEFT_HALF_START,
        RIGHT_HALF_START: RIGHT_HALF_START,
        HALF_SWEEP_ANGLE: HALF_SWEEP_ANGLE,
        SPLIT_GAP_ANGLE: SPLIT_GAP_ANGLE,
        COMFORT_RING_COUNT: COMFORT_RING_COUNT,
        DISK_COMFORT_RING_COUNT: DISK_COMFORT_RING_COUNT,
        clampPercent: clampPercent,
        sweepForPercent: sweepForPercent,
        effectiveHalfSweep: effectiveHalfSweep,
        leftHalfSweepFor: leftHalfSweepFor,
        rightHalfSweepFor: rightHalfSweepFor,
        dimensionsFor: dimensionsFor,
        nestedRingLayout: nestedRingLayout,
        equalRingLayout: equalRingLayout,
    };
}
