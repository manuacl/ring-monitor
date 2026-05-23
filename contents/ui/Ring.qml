import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami

Item {
    id: root

    property string label: ""
    property real value: 0
    property color ringColor: Kirigami.Theme.highlightColor
    property string unit: "%"

    implicitWidth: 180
    implicitHeight: 180

    readonly property real ringRadius: Math.min(width, height) / 2 - 12
    readonly property real ringStroke: 10

    // Smooth value transitions
    property real displayValue: value
    Behavior on displayValue {
        NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
    }
    onValueChanged: displayValue = value

    // Track
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

    // Active arc
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

    Column {
        anchors.centerIn: parent
        spacing: 2
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            color: Kirigami.Theme.textColor
            opacity: 0.55
            font.pixelSize: 12
            font.letterSpacing: 2
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Math.round(root.displayValue) + root.unit
            color: Kirigami.Theme.textColor
            font.pixelSize: 32
            font.weight: Font.Light
        }
    }
}
