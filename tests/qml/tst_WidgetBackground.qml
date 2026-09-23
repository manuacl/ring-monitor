import QtQuick
import QtTest
import "../../contents/ui/core" as Ui

// Tests for WidgetBackground.qml — the optional halo painted behind the
// rings (issue #170). Covers the enable gate, the stadium shaped on the
// ring layout, the spread past the rings and the fade-to-transparent edge.

Item {
    id: root
    width: 200
    height: 200

    // Stand-in for MainContent: a vertical strip of two 60 px rings in
    // cells taller than the rings, inside a box wider than the strip.
    Item {
        id: fakeRings
        anchors.fill: parent

        Item {
            property real size: Math.min(width, height)
            x: 70
            y: 0
            width: 60
            height: 90
        }
        Item {
            property real size: Math.min(width, height)
            x: 70
            y: 100
            width: 60
            height: 90
        }
        // Not a ring (no `size`) — the Repeater itself lives here too.
        Item {
            x: 0
            y: 0
            width: 200
            height: 200
        }
    }

    Ui.WidgetBackground {
        id: background
        anchors.fill: parent
    }

    TestCase {
        name: "WidgetBackground"
        when: windowShown

        property var shape: background._shape
        // A function, not a binding: gradient stops are not bindable.
        function stops() {
            return background._body.fillGradient.stops;
        }

        function init() {
            background.rings = fakeRings;
            background.backgroundEnabled = false;
            background.backgroundColor = "#204060";
            background.backgroundOpacity = 0.5;
            background.backgroundSpread = 0;
            background.backgroundEdgeSoftness = 0;
        }

        function test_hidden_until_enabled() {
            compare(background.visible, false);
            background.backgroundEnabled = true;
            compare(background.visible, true);
        }

        // ── Shape ─────────────────────────────────────────────────────
        function test_halo_hugs_the_rings_not_the_host() {
            // Rings drawn at y 15..75 and 115..175, x 70..130.
            compare(shape.x, 70);
            compare(shape.y, 15);
            compare(shape.width, 60);
            compare(shape.height, 160);
            // Caps follow the end rings: radius = ring radius.
            compare(background._halo.r, 30);
        }

        function test_without_rings_the_halo_fills_the_item() {
            background.rings = null;
            compare(shape.x, 0);
            compare(shape.width, 200);
            compare(shape.height, 200);
        }

        function test_spread_grows_the_halo_past_the_rings() {
            background.backgroundSpread = 50;
            // 50 % of the 30 px ring radius on every side.
            compare(shape.x, 55);
            compare(shape.y, 0);
            compare(shape.width, 90);
            compare(shape.height, 190);
            compare(background._halo.r, 45);
        }

        // ── Colour and fade ───────────────────────────────────────────
        function test_crisp_edge_by_default() {
            compare(background._feather, 0);
            fuzzyCompare(stops()[0].color.a, 0.5, 0.01);
            fuzzyCompare(stops()[1].color.a, 0.5, 0.01);
        }

        function test_colour_and_opacity_reach_the_core() {
            fuzzyCompare(stops()[1].color.r, background.backgroundColor.r, 0.01);
            fuzzyCompare(stops()[1].color.b, background.backgroundColor.b, 0.01);
            background.backgroundOpacity = 0.2;
            fuzzyCompare(stops()[1].color.a, 0.2, 0.01);
        }

        function test_softness_fades_the_edge_to_transparent() {
            background.backgroundEdgeSoftness = 10;
            // 10 % of the strip's shorter side (60 px).
            compare(background._feather, 6);
            fuzzyCompare(stops()[0].color.a, 0, 0.001);
            fuzzyCompare(stops()[3].color.a, 0, 0.001);
            fuzzyCompare(stops()[1].position, 0.1, 0.001);
            fuzzyCompare(stops()[1].color.a, 0.5, 0.01);
        }

        function test_color_change_reaches_the_stops() {
            background.backgroundColor = "#ffffff";
            fuzzyCompare(stops()[1].color.r, 1, 0.01);
            fuzzyCompare(stops()[2].color.r, 1, 0.01);
        }
    }
}
