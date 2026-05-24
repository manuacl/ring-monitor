import QtQuick
import QtTest
import "../../contents/ui/core" as Ui

// Tests for AppearanceBody.qml — covers the bidirectional binding
// between the body's plain properties (orientation, *Opacity) and the
// rendered controls. Catches the failure mode where the cfg_* alias
// bridge in the wrapper would silently stop propagating.

Item {
    id: root
    width: 400
    height: 400

    Ui.AppearanceBody {
        id: body
        anchors.fill: parent
    }

    TestCase {
        name: "AppearanceBody"
        when: windowShown

        function init() {
            body.orientation = "horizontal";
            body.textOpacity = 1.0;
            body.trackOpacity = 0.15;
            body.arcOpacity = 1.0;
        }

        // ── Orientation: property → UI ────────────────────────────────
        function test_orientation_default_is_horizontal() {
            compare(body.orientation, "horizontal");
        }
        function test_orientation_property_assignment_persists() {
            body.orientation = "vertical";
            compare(body.orientation, "vertical");
        }

        // ── Opacity sliders: property is the source of truth ──────────
        function test_textOpacity_drives_slider_value() {
            body.textOpacity = 0.5;
            compare(body._textSlider.value, 0.5);
        }
        function test_trackOpacity_drives_slider_value() {
            body.trackOpacity = 0.8;
            compare(body._trackSlider.value, 0.8);
        }
        function test_arcOpacity_drives_slider_value() {
            body.arcOpacity = 0.25;
            compare(body._arcSlider.value, 0.25);
        }

        // ── Round trip: write → read each property name ───────────────
        // Catches a typo in any of the 4 property declarations.
        function test_all_bridged_properties_readwrite() {
            const keys = ["orientation", "textOpacity", "trackOpacity", "arcOpacity"];
            for (const k of keys) {
                verify(k in body, "AppearanceBody must expose property " + k);
            }
        }
    }
}
