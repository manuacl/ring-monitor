import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami
import "RingGeometry.js" as Geom

Item {
    id: root

    property string label: ""
    property real value: 0
    property color ringColor: Kirigami.Theme.highlightColor
    property string unit: "%"

    // Opacities (configurable from the plasmoid config UI)
    property real textOpacity: 1.0
    property real trackOpacity: 0.15
    property real arcOpacity: 1.0

    // Optional: array of 0-100 values rendered as concentric inner rings
    // (e.g. per-core CPU usage inside the total CPU ring)
    property var nestedValues: []

    implicitWidth: 180
    implicitHeight: 180

    // Everything scales with the smaller dimension via Geom.dimensionsFor.
    readonly property real size: Math.min(width, height)
    readonly property var dims: Geom.dimensionsFor(size)
    readonly property real ringStroke: dims.ringStroke
    readonly property real ringRadius: dims.ringRadius
    readonly property real nestedStroke: dims.nestedStroke
    readonly property real nestedGap: dims.nestedGap
    readonly property real labelPx: dims.labelPx
    readonly property real valuePx: dims.valuePx

    // Smooth main value transitions
    property real displayValue: value
    Behavior on displayValue {
        NumberAnimation {
            duration: 400
            easing.type: Easing.OutCubic
        }
    }
    onValueChanged: displayValue = value

    // ── Main outer ring (track + active arc) ─────────────────────────────
    Shape {
        id: trackShape
        anchors.fill: parent
        antialiasing: true
        ShapePath {
            strokeColor: Qt.rgba(1, 1, 1, root.trackOpacity)
            strokeWidth: root.ringStroke
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: trackShape.width / 2
                centerY: trackShape.height / 2
                radiusX: root.ringRadius
                radiusY: root.ringRadius
                startAngle: Geom.BASE_START_ANGLE
                sweepAngle: Geom.BASE_SWEEP_ANGLE
            }
        }
    }

    Shape {
        id: arcShape
        anchors.fill: parent
        antialiasing: true
        opacity: root.arcOpacity
        ShapePath {
            strokeColor: root.ringColor
            strokeWidth: root.ringStroke
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: arcShape.width / 2
                centerY: arcShape.height / 2
                radiusX: root.ringRadius
                radiusY: root.ringRadius
                startAngle: Geom.BASE_START_ANGLE
                sweepAngle: Geom.sweepForPercent(root.displayValue)
            }
        }
    }

    // ── Concentric inner rings (nested values) ───────────────────────────
    Repeater {
        id: nestedRepeater
        model: root.nestedValues.length

        delegate: Item {
            id: nestedItem
            anchors.fill: parent

            required property int index

            readonly property real r: Geom.nestedRadius(root.ringRadius, root.ringStroke, root.nestedStroke, root.nestedGap, index)
            readonly property real v: root.nestedValues[index] || 0

            // Smooth this core's value
            property real dv: v
            Behavior on dv {
                NumberAnimation {
                    duration: 400
                    easing.type: Easing.OutCubic
                }
            }
            onVChanged: dv = v

            Shape {
                id: nTrack
                anchors.fill: parent
                antialiasing: true
                ShapePath {
                    strokeColor: Qt.rgba(1, 1, 1, root.trackOpacity * 0.6)
                    strokeWidth: root.nestedStroke
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: nTrack.width / 2
                        centerY: nTrack.height / 2
                        radiusX: nestedItem.r
                        radiusY: nestedItem.r
                        startAngle: Geom.BASE_START_ANGLE
                        sweepAngle: Geom.BASE_SWEEP_ANGLE
                    }
                }
            }

            Shape {
                id: nArc
                anchors.fill: parent
                antialiasing: true
                opacity: 0.55 * root.arcOpacity
                ShapePath {
                    strokeColor: root.ringColor
                    strokeWidth: root.nestedStroke
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: nArc.width / 2
                        centerY: nArc.height / 2
                        radiusX: nestedItem.r
                        radiusY: nestedItem.r
                        startAngle: Geom.BASE_START_ANGLE
                        sweepAngle: Geom.sweepForPercent(nestedItem.dv)
                    }
                }
            }
        }
    }

    // ── Center label ─────────────────────────────────────────────────────
    Column {
        anchors.centerIn: parent
        spacing: 2
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            color: Kirigami.Theme.textColor
            opacity: 0.55 * root.textOpacity
            font.pixelSize: root.labelPx
            font.letterSpacing: 2
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Math.round(root.displayValue) + root.unit
            color: Kirigami.Theme.textColor
            opacity: root.textOpacity
            font.pixelSize: root.valuePx
            font.weight: Font.Light
        }
    }
}
