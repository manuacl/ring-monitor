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

    // Stub ColorPicker — the body imports zero platform-namespaced
    // QML now, so the test provides the Component the wrapper would.
    // Same `color` property + `accepted` signal surface as both real
    // adapters (platforms/plasma/ColorPicker.qml and
    // platforms/standalone/ColorPicker.qml).
    Component {
        id: stubColorPicker
        Item {
            // Mirrors the implicit dimensions both real adapters
            // declare (platforms/plasma/ColorPicker.qml and
            // platforms/standalone/ColorPicker.qml both set
            // `implicitWidth: 32; implicitHeight: 24`). Today the
            // tests only assert `Loader.item.color`, but if a
            // future test exercises layout (the button row in
            // AppearanceBody.qml), a 0×0 stub would collapse the
            // surrounding RowLayout and the geometry assertions
            // would fail for the wrong reason.
            implicitWidth: 32
            implicitHeight: 24
            property color color: "#000000"
            signal accepted
        }
    }

    Ui.AppearanceBody {
        id: body
        anchors.fill: parent
        colorPickerComponent: stubColorPicker
    }

    TestCase {
        name: "AppearanceBody"
        when: windowShown

        function init() {
            body.orientation = "horizontal";
            body.ringSize = 180;
            body.ringSpacingPercent = 7;
            body.windowMargin = 0;
            body.textOpacity = 1.0;
            body.trackOpacity = 0.15;
            body.arcOpacity = 1.0;
            body.textColorMode = "system";
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
        function test_ringSize_drives_slider_value() {
            body.ringSize = 240;
            compare(body._ringSizeSlider.value, 240);
        }
        function test_ringSize_default_is_180() {
            compare(body.ringSize, 180);
            compare(body._ringSizeSlider.value, 180);
        }
        function test_ringSize_slider_range_80_to_800() {
            compare(body._ringSizeSlider.from, 80);
            compare(body._ringSizeSlider.to, 800);
        }
        function test_ringSpacing_default_is_7_percent() {
            compare(body.ringSpacingPercent, 7);
            compare(body._ringSpacingSlider.value, 7);
        }
        function test_ringSpacing_drives_slider_value() {
            body.ringSpacingPercent = 15;
            compare(body._ringSpacingSlider.value, 15);
        }
        function test_ringSpacing_slider_range_0_to_25() {
            compare(body._ringSpacingSlider.from, 0);
            compare(body._ringSpacingSlider.to, 25);
        }
        function test_windowMargin_default_is_0() {
            compare(body.windowMargin, 0);
            compare(body._windowMarginSlider.value, 0);
        }
        function test_windowMargin_drives_slider_value() {
            body.windowMargin = 60;
            compare(body._windowMarginSlider.value, 60);
        }
        function test_windowMargin_slider_range_0_to_200() {
            compare(body._windowMarginSlider.from, 0);
            compare(body._windowMarginSlider.to, 200);
        }
        // The Plasma host never reads `windowMargin` (only the
        // standalone Window-anchor code does), so the slider's row
        // is hidden by default. Standalone SettingsDialog opts in by
        // flipping the flag — same gating pattern as
        // AboutBody.autostartAvailable.
        function test_windowMarginVisible_defaults_false_hides_slider() {
            body.windowMarginVisible = false;
            compare(body._windowMarginSlider.parent.visible, false);
        }
        function test_windowMarginVisible_true_shows_slider() {
            body.windowMarginVisible = true;
            compare(body._windowMarginSlider.parent.visible, true);
        }

        // ── Round trip: write → read each property name ───────────────
        // Catches a typo in any of the 4 property declarations.
        function test_all_bridged_properties_readwrite() {
            const keys = ["orientation", "ringSize", "ringSpacingPercent", "windowMargin", "textOpacity", "trackOpacity", "arcOpacity", "textColorMode", "customTextColorLight", "customTextColorDark"];
            for (const k of keys) {
                verify(k in body, "AppearanceBody must expose property " + k);
            }
        }

        // ── Text color mode: property → radio + custom pickers visibility
        function test_textColorMode_default_is_system() {
            compare(body.textColorMode, "system");
            verify(body._textColorSystem.checked);
            verify(!body._textColorCustom.checked);
        }
        function test_textColorMode_custom_drives_radio() {
            body.textColorMode = "custom";
            verify(body._textColorCustom.checked);
            verify(!body._textColorSystem.checked);
        }
        function test_custom_text_color_round_trips_through_pickers() {
            body.customTextColorLight = "#aabbcc";
            body.customTextColorDark = "#112233";
            // _lightTextColorButton is a Loader since the Component-
            // injection refactor; the picker swatch lives on .item.
            compare(body._lightTextColorButton.item.color.toString().toLowerCase(), "#aabbcc");
            compare(body._darkTextColorButton.item.color.toString().toLowerCase(), "#112233");
        }
    }
}
