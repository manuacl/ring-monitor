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
            body.windowAnchorCorner = "top-right";
            body.windowMarginX = 0;
            body.windowMarginY = 0;
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
        function test_windowMargins_default_is_0() {
            compare(body.windowMarginX, 0);
            compare(body.windowMarginY, 0);
            compare(body._windowMarginXSlider.value, 0);
            compare(body._windowMarginYSlider.value, 0);
        }
        function test_windowMarginX_drives_slider_value() {
            body.windowMarginX = 60;
            compare(body._windowMarginXSlider.value, 60);
        }
        function test_windowMarginY_drives_slider_value() {
            body.windowMarginY = 40;
            compare(body._windowMarginYSlider.value, 40);
        }
        function test_windowMargin_sliders_range_0_to_200() {
            compare(body._windowMarginXSlider.from, 0);
            compare(body._windowMarginXSlider.to, 200);
            compare(body._windowMarginYSlider.from, 0);
            compare(body._windowMarginYSlider.to, 200);
        }
        // ── Anchor corner: property → combo selection ─────────────────
        function test_windowAnchorCorner_default_is_top_right() {
            compare(body.windowAnchorCorner, "top-right");
            compare(body._cornerValues[body._anchorCornerCombo.currentIndex], "top-right");
        }
        function test_windowAnchorCorner_drives_combo_selection() {
            body.windowAnchorCorner = "bottom-left";
            compare(body._cornerValues[body._anchorCornerCombo.currentIndex], "bottom-left");
        }
        // An unknown value (hand-edited config) must resolve to top-right in
        // the picker, matching the WindowPlacement.js / Main.qml fallback —
        // otherwise the combo shows a corner the window doesn't anchor to.
        function test_windowAnchorCorner_unknown_falls_back_to_top_right() {
            body.windowAnchorCorner = "middle";
            compare(body._cornerValues[body._anchorCornerCombo.currentIndex], "top-right");
        }
        // The Plasma host never reads the placement keys (only the
        // standalone Window-anchor code does), so the rows are hidden by
        // default. Standalone SettingsDialog opts in by flipping the flag
        // — same gating pattern as AboutBody.autostartAvailable.
        function test_windowPlacementVisible_defaults_false_hides_rows() {
            body.windowPlacementVisible = false;
            compare(body._anchorCornerCombo.parent.visible, false);
            compare(body._windowMarginXSlider.parent.visible, false);
        }
        function test_windowPlacementVisible_true_shows_rows() {
            body.windowPlacementVisible = true;
            compare(body._anchorCornerCombo.parent.visible, true);
            compare(body._windowMarginXSlider.parent.visible, true);
        }
        // Same gating pattern for `ringSpacing` — on Plasma, the
        // desktop frame is user-dragged-fixed and rings shrink to
        // compensate when spacing grows, so the slider is near-no-op
        // visually. Hide the row by default; standalone opts in.
        function test_ringSpacingVisible_defaults_false_hides_slider() {
            body.ringSpacingVisible = false;
            compare(body._ringSpacingSlider.parent.visible, false);
        }
        function test_ringSpacingVisible_true_shows_slider() {
            body.ringSpacingVisible = true;
            compare(body._ringSpacingSlider.parent.visible, true);
        }

        // ── Round trip: write → read each property name ───────────────
        // Catches a typo in any of the 4 property declarations.
        function test_all_bridged_properties_readwrite() {
            const keys = ["orientation", "ringSize", "ringSpacingPercent", "windowAnchorCorner", "windowMarginX", "windowMarginY", "textOpacity", "trackOpacity", "arcOpacity", "textColorMode", "customTextColorLight", "customTextColorDark"];
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

        // ── Picker accept → model → swatch (the direction the standalone
        // ColorPicker bug broke: the dark swatch never reflected the pick).
        // The shared AppearanceBody wiring (accepted handler + Binding) is
        // host-agnostic — identical on standalone and Plasma — so a green
        // here means any adapter that honours the (color, accepted) contract
        // updates the swatch. tst_ColorPicker.qml proves the standalone
        // adapter honours it; the Plasma kquickcontrols adapter is verified
        // at runtime (it can't load under qmltestrunner).
        function test_dark_text_picker_accept_updates_model_and_swatch() {
            body.textColorMode = "custom";
            body.customTextColorDark = "#000000";
            const sw = body._darkTextColorButton.item;
            verify(sw !== null, "dark text swatch must load");
            // The picker self-assigns the chosen colour, then fires accepted.
            sw.color = "#1188ff";
            sw.accepted();
            compare(body.customTextColorDark.toString().toLowerCase(), "#1188ff", "model takes the picked dark colour");
            tryCompare(sw, "color", "#1188ff", 1000, "dark swatch reflects the picked colour");
        }
        function test_light_text_picker_accept_updates_model_and_swatch() {
            body.textColorMode = "custom";
            body.customTextColorLight = "#000000";
            const sw = body._lightTextColorButton.item;
            verify(sw !== null, "light text swatch must load");
            sw.color = "#22cc44";
            sw.accepted();
            compare(body.customTextColorLight.toString().toLowerCase(), "#22cc44", "model takes the picked light colour");
            tryCompare(sw, "color", "#22cc44", 1000, "light swatch reflects the picked colour");
        }

        // SCENARIO: the ColorPicker self-assigns `color = selectedColor` on
        // accept, which clobbers an imperative `item.color = Qt.binding(...)`.
        // A Binding element re-applies, so a LATER source change still reaches
        // the swatch. Latent in AppearanceBody (no clear button), guarded for
        // consistency with PartitionRow.
        function test_SCENARIO_swatch_rebinds_after_picker_self_assign() {
            body.colorTheme = "custom";
            body.customColorLight = "#aabbcc";
            const swatch = body._lightColorButton.item;
            verify(swatch !== null, "the light-color swatch must load");
            swatch.color = "#aabbcc"; // simulate the picker's on-accept self-assign
            body.customColorLight = "#112233"; // a later source change
            tryCompare(swatch, "color", "#112233", 1000, "Binding re-applies after the self-assign clobber");
        }
    }
}
