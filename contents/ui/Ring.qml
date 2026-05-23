import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami

Item {
    id: root

    property string label: ""
    property real value: 0
    property color ringColor: Kirigami.Theme.highlightColor
    property string unit: "%"

    // Optional: array of 0-100 values rendered as concentric inner rings
    // (e.g. per-core CPU usage inside the total CPU ring)
    property var nestedValues: []

    implicitWidth: 180
    implicitHeight: 180

    // Everything scales with the smaller dimension so the widget stays
    // proportional when resized on the desktop.
    readonly property real size: Math.min(width, height)
    readonly property real ringStroke: Math.max(4, Math.round(size * 0.055))
    readonly property real ringRadius: size / 2 - ringStroke / 2 - 2
    readonly property real nestedStroke: Math.max(2, Math.round(size * 0.017))
    readonly property real nestedGap: Math.max(2, Math.round(size * 0.022))
    readonly property real labelPx: Math.max(8, Math.round(size * 0.06))
    readonly property real valuePx: Math.max(14, Math.round(size * 0.16))

    // Smooth main value transitions
    property real displayValue: value
    Behavior on displayValue {
        NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
    }
    onValueChanged: displayValue = value

    // ── Main outer ring (track + active arc) ─────────────────────────────
    Shape {
        id: trackShape
        anchors.fill: parent
        antialiasing: true
        ShapePath {
            strokeColor: Qt.rgba(1, 1, 1, 0.08)
            strokeWidth: root.ringStroke
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: trackShape.width / 2
                centerY: trackShape.height / 2
                radiusX: root.ringRadius
                radiusY: root.ringRadius
                startAngle: 135
                sweepAngle: 270
            }
        }
    }

    Shape {
        id: arcShape
        anchors.fill: parent
        antialiasing: true
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
                startAngle: 135
                sweepAngle: 270 * Math.max(0, Math.min(1, root.displayValue / 100))
            }
        }
    }

    // ── Concentric inner rings (nested values) ───────────────────────────
    // Drawn inside the main ring at progressively smaller radii.
    // Track + active arc per nested value, lower opacity than the main ring.
    Repeater {
        id: nestedRepeater
        model: root.nestedValues.length

        delegate: Item {
            id: nestedItem
            anchors.fill: parent

            required property int index

            // Radius for this nested ring: start just inside the main ring,
            // step inward by (nestedStroke + nestedGap) per level
            readonly property real r: root.ringRadius
                - root.ringStroke / 2
                - root.nestedGap
                - root.nestedStroke / 2
                - index * (root.nestedStroke + root.nestedGap)
            readonly property real v: root.nestedValues[index] || 0

            // Smooth this core's value
            property real dv: v
            Behavior on dv {
                NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
            }
            onVChanged: dv = v

            // Nested track
            Shape {
                id: nTrack
                anchors.fill: parent
                antialiasing: true
                ShapePath {
                    strokeColor: Qt.rgba(1, 1, 1, 0.05)
                    strokeWidth: root.nestedStroke
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: nTrack.width / 2
                        centerY: nTrack.height / 2
                        radiusX: nestedItem.r
                        radiusY: nestedItem.r
                        startAngle: 135
                        sweepAngle: 270
                    }
                }
            }

            // Nested active arc — same color as main ring, lower opacity
            Shape {
                id: nArc
                anchors.fill: parent
                antialiasing: true
                opacity: 0.55
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
                        startAngle: 135
                        sweepAngle: 270 * Math.max(0, Math.min(1, nestedItem.dv / 100))
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
            opacity: 0.55
            font.pixelSize: root.labelPx
            font.letterSpacing: 2
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Math.round(root.displayValue) + root.unit
            color: Kirigami.Theme.textColor
            font.pixelSize: root.valuePx
            font.weight: Font.Light
        }
    }
}
