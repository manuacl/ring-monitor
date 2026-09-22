import QtQuick
import QtTest
import "../../contents/ui/core" as Ui

// Tests for WidgetBackground.qml — the optional plate painted behind
// the rings (issue #170). Covers the enable gate and the two gradient
// stops, which is where the colour + opacity + fade settings land.

Item {
    id: root
    width: 200
    height: 200

    Ui.WidgetBackground {
        id: plate
        anchors.fill: parent
    }

    TestCase {
        name: "WidgetBackground"
        when: windowShown

        function init() {
            plate.backgroundEnabled = false;
            plate.backgroundColor = "#204060";
            plate.backgroundOpacity = 0.5;
            plate.backgroundGradient = "none";
        }

        function test_hidden_until_enabled() {
            compare(plate.visible, false);
            plate.backgroundEnabled = true;
            compare(plate.visible, true);
        }

        // The rectangle is always painted by the gradient, so `color`
        // itself must stay transparent — a coloured `color` would show
        // through a fade's transparent end.
        function test_rectangle_color_stays_transparent() {
            compare(plate.color.a, 0);
        }

        function test_flat_fill_uses_the_color_at_both_stops() {
            plate.backgroundEnabled = true;
            const stops = plate.gradient.stops;
            compare(stops.length, 2);
            fuzzyCompare(stops[0].color.r, plate.backgroundColor.r, 0.01);
            fuzzyCompare(stops[0].color.g, plate.backgroundColor.g, 0.01);
            fuzzyCompare(stops[0].color.b, plate.backgroundColor.b, 0.01);
            fuzzyCompare(stops[0].color.a, 0.5, 0.01);
            fuzzyCompare(stops[1].color.a, 0.5, 0.01);
        }

        function test_opacity_drives_both_stops() {
            plate.backgroundOpacity = 0.2;
            fuzzyCompare(plate.gradient.stops[0].color.a, 0.2, 0.01);
            fuzzyCompare(plate.gradient.stops[1].color.a, 0.2, 0.01);
        }

        function test_vertical_fade_is_transparent_at_the_named_edge() {
            plate.backgroundGradient = "top";
            compare(plate.gradient.orientation, Gradient.Vertical);
            fuzzyCompare(plate.gradient.stops[0].color.a, 0, 0.01);
            fuzzyCompare(plate.gradient.stops[1].color.a, 0.5, 0.01);

            plate.backgroundGradient = "bottom";
            fuzzyCompare(plate.gradient.stops[0].color.a, 0.5, 0.01);
            fuzzyCompare(plate.gradient.stops[1].color.a, 0, 0.01);
        }

        function test_horizontal_fade_flips_the_gradient_orientation() {
            plate.backgroundGradient = "left";
            compare(plate.gradient.orientation, Gradient.Horizontal);
            fuzzyCompare(plate.gradient.stops[0].color.a, 0, 0.01);

            plate.backgroundGradient = "right";
            compare(plate.gradient.orientation, Gradient.Horizontal);
            fuzzyCompare(plate.gradient.stops[1].color.a, 0, 0.01);
        }

        function test_unknown_direction_paints_flat() {
            plate.backgroundGradient = "diagonal";
            compare(plate.gradient.orientation, Gradient.Vertical);
            fuzzyCompare(plate.gradient.stops[0].color.a, 0.5, 0.01);
            fuzzyCompare(plate.gradient.stops[1].color.a, 0.5, 0.01);
        }

        // The colour is the host's config value; changing it must repaint
        // both stops rather than only the one the Rectangle was born with.
        function test_color_change_reaches_the_stops() {
            plate.backgroundColor = "#ffffff";
            fuzzyCompare(plate.gradient.stops[0].color.r, 1, 0.01);
            fuzzyCompare(plate.gradient.stops[1].color.r, 1, 0.01);
        }
    }
}
