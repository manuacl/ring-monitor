import QtQuick
import QtTest
import "../../contents/ui/core" as Ui

// Tests for BackgroundSettings.qml — the Appearance-page controls for
// the optional background halo (issue #170). Covers the property →
// control direction (what a persisted value shows) and the control →
// property direction (what a click writes back), which is what the
// cfg_* aliases and the standalone bridge map carry.

Item {
    id: root
    width: 400
    height: 300

    // Same stub surface as tst_AppearanceBody's: a writable `color`
    // plus an `accepted` signal, like both real ColorPicker adapters.
    Component {
        id: stubColorPicker
        Item {
            implicitWidth: 32
            implicitHeight: 24
            property color color: "#000000"
            signal accepted
        }
    }

    Ui.BackgroundSettings {
        id: settings
        anchors.fill: parent
        colorPickerComponent: stubColorPicker
    }

    TestCase {
        name: "BackgroundSettings"
        when: windowShown

        property var enabledCheck: findChild(settings, "backgroundEnabledCheck")
        property var opacitySlider: findChild(settings, "backgroundOpacitySlider")
        property var spreadSlider: findChild(settings, "backgroundSpreadSlider")
        property var softnessSlider: findChild(settings, "backgroundEdgeSoftnessSlider")
        property var colorButton: findChild(settings, "backgroundColorButton")

        function init() {
            settings.backgroundEnabled = false;
            settings.backgroundColor = "#000000";
            settings.backgroundOpacity = 0.5;
            settings.backgroundSpread = 0;
            settings.backgroundEdgeSoftness = 0;
        }

        function test_defaults_keep_the_widget_transparent() {
            compare(settings.backgroundEnabled, false);
            compare(settings.backgroundSpread, 0);
        }

        function test_enabled_property_drives_the_checkbox() {
            compare(enabledCheck.checked, false);
            settings.backgroundEnabled = true;
            compare(enabledCheck.checked, true);
        }

        // The colour, opacity, size and softness rows are meaningless while the
        // plate is off — they only appear once it is enabled.
        function test_detail_rows_hidden_while_disabled() {
            compare(opacitySlider.parent.visible, false);
            compare(spreadSlider.parent.visible, false);
            compare(softnessSlider.parent.visible, false);
            settings.backgroundEnabled = true;
            compare(opacitySlider.parent.visible, true);
            compare(spreadSlider.parent.visible, true);
            compare(softnessSlider.parent.visible, true);
        }

        function test_softness_property_drives_the_slider() {
            settings.backgroundEdgeSoftness = 12;
            compare(softnessSlider.value, 12);
        }

        function test_softness_slider_move_writes_back() {
            settings.backgroundEnabled = true;
            softnessSlider.value = 20;
            softnessSlider.moved();
            compare(settings.backgroundEdgeSoftness, 20);
        }

        function test_opacity_property_drives_the_slider() {
            settings.backgroundOpacity = 0.35;
            fuzzyCompare(opacitySlider.value, 0.35, 0.001);
        }

        function test_slider_move_writes_back_the_opacity() {
            settings.backgroundEnabled = true;
            opacitySlider.value = 0.8;
            opacitySlider.moved();
            fuzzyCompare(settings.backgroundOpacity, 0.8, 0.001);
        }

        function test_spread_property_drives_the_slider() {
            settings.backgroundSpread = 40;
            compare(spreadSlider.value, 40);
        }

        function test_spread_slider_move_writes_back() {
            settings.backgroundEnabled = true;
            spreadSlider.value = 60;
            spreadSlider.moved();
            compare(settings.backgroundSpread, 60);
        }

        function test_color_picker_accept_writes_back_the_color() {
            settings.backgroundEnabled = true;
            verify(colorButton.item !== null);
            colorButton.item.color = "#ff8800";
            colorButton.item.accepted();
            compare(settings.backgroundColor.toString(), "#ff8800");
        }

        function test_color_property_drives_the_swatch() {
            settings.backgroundEnabled = true;
            settings.backgroundColor = "#123456";
            compare(colorButton.item.color.toString(), "#123456");
        }
    }
}
