import QtQuick
import QtQuick.Shapes
import "RingGeometry.js" as Geom

// One concentric track + active arc at a given radius and stroke, with the
// same 400ms OutCubic value smoothing as the main ring. Extracted from
// Ring.qml so the two stacking modes share one renderer:
//   - CPU cores  → thin rings nested inside the main ring (nestedValues)
//   - disk parts → full-stroke equal rings replacing the main ring (equalValues)
// The opacity *factors default to 1.0 (the disk full-ring look); the cores
// caller passes 0.6 / 0.55 to keep the thin rings visually subordinate.
//
// Anchors-fill its parent (the square ringBox), so centerX/Y resolve to the
// shared ring centre — same convention as Ring.qml's own Shapes.

Item {
    id: arc
    anchors.fill: parent

    property real radius: 0
    property real stroke: 0
    property real value: 0            // 0-100, drives the sweep
    property color ringColor: "#3daee9"
    property real trackOpacity: 0.15
    property real arcOpacity: 1.0
    property real trackOpacityFactor: 1.0
    property real arcOpacityFactor: 1.0

    // Smooth this ring's value the same way the main ring smooths displayValue.
    property real dv: value
    Behavior on dv {
        NumberAnimation {
            duration: 400
            easing.type: Easing.OutCubic
        }
    }
    onValueChanged: dv = value

    Shape {
        id: track
        anchors.fill: parent
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: Qt.rgba(1, 1, 1, arc.trackOpacity * arc.trackOpacityFactor)
            strokeWidth: arc.stroke
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: track.width / 2
                centerY: track.height / 2
                radiusX: arc.radius
                radiusY: arc.radius
                startAngle: Geom.BASE_START_ANGLE
                sweepAngle: Geom.BASE_SWEEP_ANGLE
            }
        }
    }

    Shape {
        id: active
        anchors.fill: parent
        antialiasing: true
        opacity: arc.arcOpacityFactor * arc.arcOpacity
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: arc.ringColor
            strokeWidth: arc.stroke
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: active.width / 2
                centerY: active.height / 2
                radiusX: arc.radius
                radiusY: arc.radius
                startAngle: Geom.BASE_START_ANGLE
                sweepAngle: Geom.sweepForPercent(arc.dv)
            }
        }
    }
}
