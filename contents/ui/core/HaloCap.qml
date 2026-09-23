import QtQuick
import QtQuick.Shapes

// One half-disc end of WidgetBackground's halo: `coreColor` up to
// `capStop`, fading radially to `edgeColor` at the rim. Geometry from
// BackgroundStyle.haloGeometry (capA / capB).

ShapePath {
    id: halfDisc

    property var cap
    property real radius
    property real capStop: 1
    property color coreColor
    property color edgeColor

    strokeColor: "transparent"
    startX: halfDisc.cap.start.x
    startY: halfDisc.cap.start.y
    fillGradient: RadialGradient {
        centerX: halfDisc.cap.center.x
        centerY: halfDisc.cap.center.y
        centerRadius: halfDisc.radius
        focalX: halfDisc.cap.center.x
        focalY: halfDisc.cap.center.y

        GradientStop {
            position: 0
            color: halfDisc.coreColor
        }
        GradientStop {
            position: halfDisc.capStop
            color: halfDisc.coreColor
        }
        GradientStop {
            position: 1
            color: halfDisc.edgeColor
        }
    }

    PathArc {
        x: halfDisc.cap.end.x
        y: halfDisc.cap.end.y
        radiusX: halfDisc.radius
        radiusY: halfDisc.radius
        direction: halfDisc.cap.clockwise ? PathArc.Clockwise : PathArc.Counterclockwise
    }
}
