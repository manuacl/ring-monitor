import QtQuick
import QtTest
import "../../contents/ui/core" as Ui

// Tests for WidgetBackground.qml — the optional plate painted behind
// the rings (issue #170). Covers the enable gate, the two gradient
// stops (colour + opacity + directional fade) and the soft-edge blur.

Item {
    id: root
    width: 200
    height: 200

    Ui.WidgetBackground {
        id: background
        anchors.fill: parent
    }

    TestCase {
        name: "WidgetBackground"
        when: windowShown

        // The plate is the Rectangle the gradient is painted on; the
        // root is the Item that also carries the feathering effect.
        property var plate: background._plate

        function init() {
            background.backgroundEnabled = false;
            background.backgroundColor = "#204060";
            background.backgroundOpacity = 0.5;
            background.backgroundGradient = "none";
            background.backgroundEdgeSoftness = 0;
        }

        function test_hidden_until_enabled() {
            compare(background.visible, false);
            background.backgroundEnabled = true;
            compare(background.visible, true);
        }

        // The rectangle is always painted by the gradient, so `color`
        // itself must stay transparent — a coloured `color` would show
        // through a fade's transparent end.
        function test_rectangle_color_stays_transparent() {
            compare(plate.color.a, 0);
        }

        function test_flat_fill_uses_the_color_at_both_stops() {
            background.backgroundEnabled = true;
            const stops = plate.gradient.stops;
            compare(stops.length, 2);
            fuzzyCompare(stops[0].color.r, background.backgroundColor.r, 0.01);
            fuzzyCompare(stops[0].color.g, background.backgroundColor.g, 0.01);
            fuzzyCompare(stops[0].color.b, background.backgroundColor.b, 0.01);
            fuzzyCompare(stops[0].color.a, 0.5, 0.01);
            fuzzyCompare(stops[1].color.a, 0.5, 0.01);
        }

        function test_opacity_drives_both_stops() {
            background.backgroundOpacity = 0.2;
            fuzzyCompare(plate.gradient.stops[0].color.a, 0.2, 0.01);
            fuzzyCompare(plate.gradient.stops[1].color.a, 0.2, 0.01);
        }

        function test_vertical_fade_is_transparent_at_the_named_edge() {
            background.backgroundGradient = "top";
            compare(plate.gradient.orientation, Gradient.Vertical);
            fuzzyCompare(plate.gradient.stops[0].color.a, 0, 0.01);
            fuzzyCompare(plate.gradient.stops[1].color.a, 0.5, 0.01);

            background.backgroundGradient = "bottom";
            fuzzyCompare(plate.gradient.stops[0].color.a, 0.5, 0.01);
            fuzzyCompare(plate.gradient.stops[1].color.a, 0, 0.01);
        }

        function test_horizontal_fade_flips_the_gradient_orientation() {
            background.backgroundGradient = "left";
            compare(plate.gradient.orientation, Gradient.Horizontal);
            fuzzyCompare(plate.gradient.stops[0].color.a, 0, 0.01);

            background.backgroundGradient = "right";
            compare(plate.gradient.orientation, Gradient.Horizontal);
            fuzzyCompare(plate.gradient.stops[1].color.a, 0, 0.01);
        }

        function test_unknown_direction_paints_flat() {
            background.backgroundGradient = "diagonal";
            compare(plate.gradient.orientation, Gradient.Vertical);
            fuzzyCompare(plate.gradient.stops[0].color.a, 0.5, 0.01);
            fuzzyCompare(plate.gradient.stops[1].color.a, 0.5, 0.01);
        }

        // ── Soft edges ────────────────────────────────────────────────
        function test_crisp_by_default() {
            compare(background._feather, 0);
            compare(background._feathering.blurEnabled, false);
            compare(background._plate.anchors.margins, 0);
        }

        function test_softness_insets_the_plate_and_enables_the_blur() {
            background.backgroundEdgeSoftness = 10;
            // 10 % of the shorter side (200 px here).
            compare(background._feather, 20);
            compare(background._plate.anchors.margins, 20);
            compare(background._feathering.blurEnabled, true);
            compare(background._feathering.blurMax, 20);
        }

        // The effect must never hide the plate when the blur is off:
        // MultiEffect owns its source's visibility, so switching the
        // effect off by `visible` would blank the background entirely.
        function test_effect_stays_instantiated_when_crisp() {
            background.backgroundEnabled = true;
            background.backgroundEdgeSoftness = 0;
            compare(background._feathering.visible, true);
            compare(background._feathering.blurEnabled, false);
        }

        // The colour is the host's config value; changing it must repaint
        // both stops rather than only the one the Rectangle was born with.
        function test_color_change_reaches_the_stops() {
            background.backgroundColor = "#ffffff";
            fuzzyCompare(plate.gradient.stops[0].color.r, 1, 0.01);
            fuzzyCompare(plate.gradient.stops[1].color.r, 1, 0.01);
        }
    }
}
