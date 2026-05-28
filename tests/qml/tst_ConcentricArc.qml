import QtQuick
import QtTest
import "../../contents/ui/core" as Ui

// Tests for ConcentricArc.qml — the shared track+arc renderer used by both
// the CPU-cores nested rings and the disk equal rings. Verifies the value
// smoothing (dv tracks value via the 400ms Behavior) and that the component
// instantiates with the expected public surface.

Item {
    id: root
    width: 200
    height: 200

    Ui.ConcentricArc {
        id: arc
        width: 180
        height: 180
        radius: 80
        stroke: 10
    }

    TestCase {
        name: "ConcentricArc"
        when: windowShown

        function init() {
            arc.value = 0;
            tryCompare(arc, "dv", 0, 1000);
        }

        function test_smoke_loads_with_defaults() {
            verify(arc);
            compare(arc.radius, 80);
            compare(arc.stroke, 10);
            // Opacity factors default to the full-ring (disk) look.
            compare(arc.trackOpacityFactor, 1.0);
            compare(arc.arcOpacityFactor, 1.0);
        }

        function test_dv_tracks_value_through_animation() {
            arc.value = 75;
            tryCompare(arc, "dv", 75, 1000);
        }

        function test_dv_returns_to_zero() {
            arc.value = 60;
            tryCompare(arc, "dv", 60, 1000);
            arc.value = 0;
            tryCompare(arc, "dv", 0, 1000);
        }
    }
}
