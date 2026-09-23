import QtQuick
import QtQuick.Shapes
import QtTest
import "../../contents/ui/core" as Ui

// Tests for HaloCap.qml — one half-disc end of WidgetBackground's halo.
// The cap is only right if its radial fade matches the body's linear one
// (same stops, same colours) and it bulges on the correct side.

Item {
    id: root
    width: 200
    height: 200

    Shape {
        anchors.fill: parent

        Ui.HaloCap {
            id: cap
            radius: 50
            capStop: 0.6
            coreColor: Qt.rgba(1, 0, 0, 0.5)
            edgeColor: Qt.rgba(1, 0, 0, 0)
        }
    }

    TestCase {
        name: "HaloCap"
        when: windowShown

        // Left cap of a horizontal pill, reset before each test.
        function init() {
            cap.cap = {
                "start": { "x": 50, "y": 0 },
                "end": { "x": 50, "y": 100 },
                "center": { "x": 50, "y": 50 },
                "clockwise": false
            };
        }

        function test_path_runs_from_start_to_end_around_the_centre() {
            compare(cap.startX, 50);
            compare(cap.startY, 0);
            const arc = cap.pathElements[0];
            compare(arc.x, 50);
            compare(arc.y, 100);
            compare(arc.radiusX, 50);
            compare(arc.direction, PathArc.Counterclockwise);
        }

        function test_radial_fade_is_centred_on_the_ring() {
            const g = cap.fillGradient;
            compare(g.centerX, 50);
            compare(g.centerY, 50);
            compare(g.centerRadius, 50);
        }

        function test_core_holds_until_cap_stop_then_fades_to_the_edge() {
            const stops = cap.fillGradient.stops;
            compare(stops.length, 3);
            fuzzyCompare(stops[1].position, 0.6, 0.001);
            fuzzyCompare(stops[0].color.a, 0.5, 0.01);
            fuzzyCompare(stops[1].color.a, 0.5, 0.01);
            fuzzyCompare(stops[2].color.a, 0, 0.001);
        }

        function test_clockwise_flag_flips_the_arc() {
            cap.cap = {
                "start": { "x": 150, "y": 0 },
                "end": { "x": 150, "y": 100 },
                "center": { "x": 150, "y": 50 },
                "clockwise": true
            };
            compare(cap.pathElements[0].direction, PathArc.Clockwise);
        }
    }
}
