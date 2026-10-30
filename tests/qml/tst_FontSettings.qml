import QtQuick
import QtTest
import "../../contents/ui/core" as Ui

// Tests for FontSettings.qml — the Appearance-page controls for the ring
// text (family / weight / size scale). Covers the property → control
// direction (what a persisted value shows) and the control → property
// direction (what a pick writes back), which is what the cfg_* aliases
// and the standalone bridge map carry.

Item {
    id: root
    width: 400
    height: 300

    Ui.FontSettings {
        id: settings
        anchors.fill: parent
        availableFamilies: ["Alpha Sans", "Beta Serif"]
    }

    TestCase {
        name: "FontSettings"
        when: windowShown

        property var familyCombo: findChild(settings, "fontFamilyCombo")
        property var weightCombo: findChild(settings, "fontWeightCombo")
        property var scaleSlider: findChild(settings, "fontScaleSlider")

        function init() {
            settings.fontFamily = "";
            settings.fontWeight = 300;
            settings.fontScalePercent = 100;
        }

        function test_defaults_keep_the_historic_look() {
            compare(settings.fontFamily, "");
            compare(settings.fontWeight, 300);
            compare(settings.fontScalePercent, 100);
        }

        // ── Family ────────────────────────────────────────────────
        function test_family_list_starts_with_the_system_default() {
            compare(familyCombo.count, 3);
            compare(familyCombo.currentIndex, 0);
        }

        function test_stored_family_selects_its_entry() {
            settings.fontFamily = "Beta Serif";
            compare(familyCombo.currentIndex, 2);
            compare(familyCombo.currentText, "Beta Serif");
        }

        // SCENARIO: a family saved on another machine (or since uninstalled)
        // must show "System default" without clobbering the stored name —
        // only a user pick may write.
        function test_SCENARIO_uninstalled_family_shows_default_without_writing() {
            settings.fontFamily = "Gone Mono";
            compare(familyCombo.currentIndex, 0);
            compare(settings.fontFamily, "Gone Mono");
        }

        function test_picking_a_family_writes_back_its_name() {
            familyCombo.activated(1);
            compare(settings.fontFamily, "Alpha Sans");
        }

        function test_picking_system_default_clears_the_family() {
            settings.fontFamily = "Beta Serif";
            familyCombo.activated(0);
            compare(settings.fontFamily, "");
        }

        // ── Weight ────────────────────────────────────────────────
        function test_default_weight_selects_light() {
            compare(weightCombo.currentIndex, 2);
            compare(weightCombo.currentText, "Light");
        }

        function test_weight_property_drives_the_combo() {
            settings.fontWeight = 700;
            compare(weightCombo.currentText, "Bold");
        }

        // SCENARIO (PR #178 review): the schema allows 100–900 but the combo
        // offered six weights, so a stored 800 showed "Light" while the ring
        // rendered ExtraBold. Every hundred now has its own entry.
        function test_SCENARIO_every_schema_weight_shows_itself() {
            settings.fontWeight = 800;
            compare(weightCombo.currentText, "Extra bold");
            settings.fontWeight = 900;
            compare(weightCombo.currentText, "Black");
        }

        // An off-grid hand-edited weight lands on the nearest entry, never blank.
        function test_off_grid_weight_shows_the_nearest_entry() {
            settings.fontWeight = 320;
            compare(weightCombo.currentText, "Light");
            settings.fontWeight = 5000;
            compare(weightCombo.currentText, "Black");
        }

        function test_picking_a_weight_writes_back_its_qt_value() {
            weightCombo.activated(0);
            compare(settings.fontWeight, 100);
            weightCombo.activated(6);
            compare(settings.fontWeight, 700);
            weightCombo.activated(8);
            compare(settings.fontWeight, 900);
        }

        // ── Size scale ────────────────────────────────────────────
        function test_scale_property_drives_the_slider() {
            settings.fontScalePercent = 130;
            compare(scaleSlider.value, 130);
        }

        function test_scale_slider_range_is_50_to_150() {
            compare(scaleSlider.from, 50);
            compare(scaleSlider.to, 150);
        }

        function test_scale_slider_move_writes_back() {
            scaleSlider.value = 75;
            scaleSlider.moved();
            compare(settings.fontScalePercent, 75);
        }
    }
}
