import QtQuick
import QtQuick.Shapes
import "RingGeometry.js" as Geom

Item {
    id: root

    property string label: ""
    property real value: 0
    // Optional decoupling: when isFinite(rawValue), the centre text
    // shows Math.round(rawValue) + unit instead of value + unit. The
    // sweep still uses `value` (treated as 0-100 percent). Useful for
    // temperature rings where value=tempToPercent(rawC) drives the
    // sweep but rawC (or its °F conversion) is what the user reads.
    property real rawValue: NaN
    // Theme tokens — injected by the parent via the platforms/plasma/Theme adapter.
    // Sensible defaults so the component renders standalone (tests, previews).
    property color ringColor: "#3daee9"
    property color textColor: "#eeeeee"
    property string unit: "%"

    // Opacities (configurable from the plasmoid config UI)
    property real textOpacity: 1.0
    property real trackOpacity: 0.15
    property real arcOpacity: 1.0

    // Optional: array of 0-100 values rendered as concentric inner rings
    // (e.g. per-core CPU usage inside the total CPU ring)
    property var nestedValues: []

    // Optional: when `splitMode` is true the outer ring is scinded at
    // the top into two half-arcs growing bottom-up from the gap edges:
    //   - left half  = `value`        (0-100, usage %)
    //   - right half = `splitValue`   (0-100, secondary metric)
    // Both halves meet at the top when their respective inputs hit 100%.
    // The center shows two values side by side: `value+unit` to the left
    // and `splitRawValue+splitUnit` to the right (raw, e.g. °C, not the
    // 0-100 mapping). nestedValues rings stay full 270° in split mode —
    // the values text overlaps them by design (cores arcs render at
    // 0.55 opacity so the text on top stays readable).
    property bool splitMode: false
    property real splitValue: 0
    property real splitRawValue: 0
    property string splitUnit: "°"

    // Optional: render a small "update available" dot inside the 90°
    // bottom gap, next to the label. Clicking it fires updateBadgeClicked
    // which the parent uses to trigger Plasmoid.action("configure").
    // Off by default so non-cpu / non-first rings stay clean.
    property bool showUpdateBadge: false
    signal updateBadgeClicked

    implicitWidth: 180
    implicitHeight: 180

    // Everything scales with the smaller dimension via Geom.dimensionsFor.
    readonly property real size: Math.min(width, height)
    readonly property var dims: Geom.dimensionsFor(size)
    readonly property real ringStroke: dims.ringStroke
    readonly property real ringRadius: dims.ringRadius
    readonly property real labelPx: dims.labelPx
    readonly property real valuePx: dims.valuePx
    // Cores layout is count-dependent: up to 7 rings use the preferred
    // stroke / gap; past that, the layout shrinks them to keep the
    // stack within a fixed visual envelope (see Geom.nestedRingLayout).
    readonly property var nestedLayout: Geom.nestedRingLayout(root.ringRadius, root.ringStroke, dims.nestedStroke, dims.nestedGap, root.nestedValues.length)
    readonly property real nestedStroke: nestedLayout.stroke

    // Smooth main value transitions — displayValue drives the sweep
    // and (when no rawValue override) the centre text.
    property real displayValue: value
    Behavior on displayValue {
        NumberAnimation {
            duration: 400
            easing.type: Easing.OutCubic
        }
    }

    // Separately smoothed display readout for when value ≠ what the
    // user should see (temperature rings). Falls back to `value` when
    // rawValue is NaN, so the binding stays correct for the common
    // case where the displayed value IS the percent.
    property real displayRawValue: isFinite(rawValue) ? rawValue : value
    Behavior on displayRawValue {
        NumberAnimation {
            duration: 400
            easing.type: Easing.OutCubic
        }
    }

    onValueChanged: {
        displayValue = value;
        if (!isFinite(rawValue))
            displayRawValue = value;
    }
    onRawValueChanged: {
        displayRawValue = isFinite(rawValue) ? rawValue : value;
    }

    // Same smoothing for the split secondary (animated %) and its raw
    // °C representation. Both share the 400ms / OutCubic easing so the
    // two halves move in sync visually.
    property real displaySplitValue: splitValue
    Behavior on displaySplitValue {
        NumberAnimation {
            duration: 400
            easing.type: Easing.OutCubic
        }
    }
    onSplitValueChanged: displaySplitValue = splitValue

    property real displaySplitRawValue: splitRawValue
    Behavior on displaySplitRawValue {
        NumberAnimation {
            duration: 400
            easing.type: Easing.OutCubic
        }
    }
    onSplitRawValueChanged: displaySplitRawValue = splitRawValue

    // Square inner box centered in the root. All ring geometry + label
    // anchor against this, not against `root`. Without this wrap, the
    // label was anchored to `root.bottom` — fine when the delegate is
    // a tight square, but in horizontal layout `Layout.fillHeight: true`
    // stretches the root taller than `size`, so the label drifted off
    // the bottom of the visible ring. See issue #13.
    Item {
        id: ringBox
        width: root.size
        height: root.size
        anchors.centerIn: parent

        // ── Main outer ring (track + active arc) ─────────────────────────
        // Single full 270° arc when !splitMode; in split mode this is
        // hidden and replaced by the two half-arcs below.
        Shape {
            id: trackShape
            anchors.fill: parent
            antialiasing: true
            visible: !root.splitMode
            preferredRendererType: Shape.CurveRenderer
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
            visible: !root.splitMode
            opacity: root.arcOpacity
            preferredRendererType: Shape.CurveRenderer
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

        // ── Split-mode halves ───────────────────────────────────────────
        // Left half — track + active arc (135° start, growing clockwise
        // bottom-up). Active arc is the `value` (usage %).
        Shape {
            id: leftTrackShape
            anchors.fill: parent
            antialiasing: true
            visible: root.splitMode
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Qt.rgba(1, 1, 1, root.trackOpacity)
                strokeWidth: root.ringStroke
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: leftTrackShape.width / 2
                    centerY: leftTrackShape.height / 2
                    radiusX: root.ringRadius
                    radiusY: root.ringRadius
                    startAngle: Geom.LEFT_HALF_START
                    sweepAngle: Geom.leftHalfSweepFor(100)
                }
            }
        }

        Shape {
            id: leftArcShape
            anchors.fill: parent
            antialiasing: true
            visible: root.splitMode
            opacity: root.arcOpacity
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: root.ringColor
                strokeWidth: root.ringStroke
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: leftArcShape.width / 2
                    centerY: leftArcShape.height / 2
                    radiusX: root.ringRadius
                    radiusY: root.ringRadius
                    startAngle: Geom.LEFT_HALF_START
                    sweepAngle: Geom.leftHalfSweepFor(root.displayValue)
                }
            }
        }

        // Right half — track + active arc (45° start, growing
        // anticlockwise bottom-up). Active arc is the `splitValue`
        // (the secondary metric, 0-100; for temperature: see
        // Catalog.tempToPercent).
        Shape {
            id: rightTrackShape
            anchors.fill: parent
            antialiasing: true
            visible: root.splitMode
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Qt.rgba(1, 1, 1, root.trackOpacity)
                strokeWidth: root.ringStroke
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: rightTrackShape.width / 2
                    centerY: rightTrackShape.height / 2
                    radiusX: root.ringRadius
                    radiusY: root.ringRadius
                    startAngle: Geom.RIGHT_HALF_START
                    sweepAngle: Geom.rightHalfSweepFor(100)
                }
            }
        }

        Shape {
            id: rightArcShape
            anchors.fill: parent
            antialiasing: true
            visible: root.splitMode
            opacity: root.arcOpacity
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: root.ringColor
                strokeWidth: root.ringStroke
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: rightArcShape.width / 2
                    centerY: rightArcShape.height / 2
                    radiusX: root.ringRadius
                    radiusY: root.ringRadius
                    startAngle: Geom.RIGHT_HALF_START
                    sweepAngle: Geom.rightHalfSweepFor(root.displaySplitValue)
                }
            }
        }

        // ── Concentric inner rings (nested values) ───────────────────────
        Repeater {
            id: nestedRepeater
            model: root.nestedValues.length

            delegate: Item {
                id: nestedItem
                anchors.fill: parent

                required property int index

                readonly property real r: root.nestedLayout.radii[index] || 0
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
                    preferredRendererType: Shape.CurveRenderer
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
                    preferredRendererType: Shape.CurveRenderer
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

        // ── Value (centered, or left-of-center in split mode) ────────────
        // In split mode the font shrinks to 75% of valuePx so usage and
        // temperature both fit side by side. The horizontalCenterOffset
        // shifts ~18% of the ring's size to either side of the geometric
        // center — empirically the most balanced position for two
        // 2-3-char readouts inside a 180px ring without crowding the gap
        // label below or the cores arcs (which keep their full 270°
        // sweep and stay below the text).
        Text {
            id: valueText
            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: root.splitMode ? -root.size * 0.18 : 0
            text: Math.round(root.displayRawValue) + root.unit
            color: root.textColor
            opacity: root.textOpacity
            font.pixelSize: root.splitMode ? Math.round(root.valuePx * 0.75) : root.valuePx
            font.weight: Font.Light
        }

        Text {
            id: splitValueText
            visible: root.splitMode
            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: root.size * 0.18
            text: Math.round(root.displaySplitRawValue) + root.splitUnit
            color: root.textColor
            opacity: root.textOpacity
            font.pixelSize: Math.round(root.valuePx * 0.75)
            font.weight: Font.Light
        }

        // ── Label (inside the 90° gap at the bottom of the ring) ─────────
        Text {
            id: labelText
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Math.max(2, Math.round(root.size * 0.14))
            text: root.label
            color: root.textColor
            opacity: 0.55 * root.textOpacity
            font.pixelSize: root.labelPx
            font.letterSpacing: 2
        }

        // ── Update-available badge (90° gap, left of the label) ─────────
        // Discreet dot sized to ~55% of labelPx, anchored to labelText's
        // left edge. Pulse animation (opacity 0.45 ↔ 1.0, 1.8s breath
        // cycle) draws the eye without crying for attention. Hover /
        // click area is generous enough for fingers but the rendered
        // dot stays small.
        Rectangle {
            id: updateBadge
            visible: root.showUpdateBadge
            width: Math.max(6, Math.round(root.labelPx * 0.55))
            height: width
            radius: width / 2
            color: root.ringColor
            // Black outline so the dot stays readable on any background
            // (e.g. a red wallpaper that camouflages a red ringColor).
            border.color: "black"
            border.width: 1
            opacity: root.textOpacity
            anchors.right: labelText.left
            anchors.rightMargin: Math.max(4, Math.round(root.labelPx * 0.5))
            anchors.verticalCenter: labelText.verticalCenter

            SequentialAnimation on opacity {
                running: updateBadge.visible
                loops: Animation.Infinite
                NumberAnimation {
                    from: root.textOpacity
                    to: 0.45 * root.textOpacity
                    duration: 900
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    from: 0.45 * root.textOpacity
                    to: root.textOpacity
                    duration: 900
                    easing.type: Easing.InOutSine
                }
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -6   // larger hit-target than the dot
                cursorShape: Qt.PointingHandCursor
                onClicked: root.updateBadgeClicked()
            }
        }
    }

    // ── Test hooks (read what's actually rendered) ───────────────────────
    readonly property alias _labelText: labelText.text
    readonly property alias _valueText: valueText.text
    readonly property alias _splitValueText: splitValueText.text
    readonly property real _sweepAngle: Geom.sweepForPercent(root.displayValue)
    readonly property real _leftSweepAngle: Geom.leftHalfSweepFor(root.displayValue)
    readonly property real _rightSweepAngle: Geom.rightHalfSweepFor(root.displaySplitValue)
    readonly property bool _fullArcVisible: arcShape.visible
    readonly property bool _leftArcVisible: leftArcShape.visible
    readonly property bool _rightArcVisible: rightArcShape.visible
    readonly property bool _splitValueTextVisible: splitValueText.visible
    // Label's bottom-y in root coords — used by the regression test for
    // issue #13 to assert the label tracks the visible ring's bottom,
    // not the root Item's bottom when the delegate is stretched.
    readonly property real _labelBottomY: labelText.mapToItem(root, 0, labelText.height).y
}
