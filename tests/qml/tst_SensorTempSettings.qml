import QtQuick
import QtTest
import "../../contents/ui/core" as Ui

// Tests for SensorTempSettings.qml — the custom hardware temperature
// sub-option: the discoverable sensor picker (editable combo), the live
// validation feedback, the collapsed-until-an-id sub-options, and the
// per-edit signals MetricsSubOptions relies on to reach the persisted
// config keys.

Item {
    id: root
    width: 400
    height: 300

    Ui.SensorTempSettings {
        id: settings
        anchors.fill: parent
        sensorId: ""
        sensorLabel: "SENSOR"
        minC: 20
        maxC: 60
        // Pinned (not "auto") so the tests don't depend on the runner's
        // locale measurement system.
        tempUnit: "celsius"

        // Mirror the production wiring (MetricSubOptions): the component
        // is stateless, so the committed id is written straight back —
        // keeps the combo's display sync consistent while typing.
        onSensorIdEdited: function (value) {
            settings.sensorId = value;
        }
    }

    SignalSpy {
        id: idSpy
        target: settings
        signalName: "sensorIdEdited"
    }

    SignalSpy {
        id: labelSpy
        target: settings
        signalName: "sensorLabelEdited"
    }

    SignalSpy {
        id: minSpy
        target: settings
        signalName: "minCEdited"
    }

    SignalSpy {
        id: maxSpy
        target: settings
        signalName: "maxCEdited"
    }

    TestCase {
        name: "SensorTempSettings"
        when: windowShown

        function init() {
            settings.sensorId = "";
            settings.sensorLabel = "SENSOR";
            settings.minC = 20;
            settings.maxC = 60;
            settings.tempUnit = "celsius";
            settings.availableSensors = [];
            settings.sensorResolved = false;
            settings.sensorLiveValue = NaN;
            idSpy.clear();
            labelSpy.clear();
            minSpy.clear();
            maxSpy.clear();
        }

        function test_public_properties_round_trip() {
            settings.sensorId = "lmsensors/chip/temp1";
            settings.sensorLabel = "LOOP";
            settings.minC = 10;
            settings.maxC = 80;
            compare(settings.sensorId, "lmsensors/chip/temp1");
            compare(settings.sensorLabel, "LOOP");
            compare(settings.minC, 10);
            compare(settings.maxC, 80);
        }

        // ── The picker: editable combo over the discovered sensors ───

        function test_combo_lists_discovered_sensors() {
            settings.availableSensors = [{ id: "cpu/all/averageTemperature", label: "Average" }, { id: "lmsensors/nvme-pci-0100/temp1", label: "Composite" }];
            const combo = findChild(settings, "sensorIdCombo");
            verify(combo, "sensorIdCombo must exist");
            compare(combo.count, 2);
        }

        function test_activating_a_listed_sensor_commits_its_id() {
            settings.availableSensors = [{ id: "cpu/all/averageTemperature", label: "Average" }, { id: "lmsensors/nvme-pci-0100/temp1", label: "Composite" }];
            const combo = findChild(settings, "sensorIdCombo");
            // ComboBox.activate() is not exposed to QML here, so the
            // signal the popup would emit is raised directly — the
            // component's onActivated handler is what is under test.
            combo.activated(1);
            compare(idSpy.count, 1);
            compare(idSpy.signalArguments[0][0], "lmsensors/nvme-pci-0100/temp1");
        }

        function test_listed_sensor_id_displays_its_friendly_label() {
            settings.availableSensors = [{ id: "cpu/all/averageTemperature", label: "Average" }];
            settings.sensorId = "cpu/all/averageTemperature";
            const combo = findChild(settings, "sensorIdCombo");
            compare(combo.editText, "Average");
            // The display sync must not echo back as a user edit.
            compare(idSpy.count, 0);
        }

        function test_unknown_sensor_id_stays_verbatim_in_the_combo() {
            settings.availableSensors = [{ id: "cpu/all/averageTemperature", label: "Average" }];
            settings.sensorId = "lmsensors/exotic/temp9";
            const combo = findChild(settings, "sensorIdCombo");
            compare(combo.editText, "lmsensors/exotic/temp9");
        }

        // The control rewrites editText to the first entry's label when
        // the model is (re)assigned; the deferred re-sync must restore
        // the configured id's text once discovery populates late.
        function test_discovery_populating_late_keeps_a_custom_id_verbatim() {
            settings.sensorId = "lmsensors/exotic/temp9";
            settings.availableSensors = [{ id: "cpu/all/averageTemperature", label: "Average" }];
            const combo = findChild(settings, "sensorIdCombo");
            tryVerify(function () {
                return combo.editText === "lmsensors/exotic/temp9";
            });
            compare(idSpy.count, 0);
        }

        function test_discovery_populating_late_shows_the_label_of_a_listed_id() {
            settings.sensorId = "lmsensors/nvme-pci-0100/temp1";
            settings.availableSensors = [{ id: "cpu/all/averageTemperature", label: "Average" }, { id: "lmsensors/nvme-pci-0100/temp1", label: "Composite" }];
            const combo = findChild(settings, "sensorIdCombo");
            tryVerify(function () {
                return combo.editText === "Composite";
            });
        }

        function test_typing_a_custom_id_commits_verbatim() {
            const field = findChild(settings, "sensorIdField");
            verify(field, "sensorIdField must exist");
            field.forceActiveFocus();
            keyClick(Qt.Key_A);
            keyClick(Qt.Key_B);
            compare(idSpy.count, 2);
            compare(idSpy.signalArguments[1][0], "ab");
        }

        // ── Live validation feedback ─────────────────────────────────

        function test_empty_id_shows_neither_status_nor_error() {
            compare(findChild(settings, "sensorStatusLabel").visible, false);
            compare(findChild(settings, "sensorErrorMessage").visible, false);
        }

        function test_unresolved_id_shows_an_error_message() {
            settings.sensorId = "lmsensors/nope/temp1";
            settings.sensorResolved = false;
            compare(findChild(settings, "sensorErrorMessage").visible, true);
            compare(findChild(settings, "sensorStatusLabel").visible, false);
        }

        function test_resolved_id_shows_the_live_reading() {
            settings.sensorId = "lmsensors/nvme-pci-0100/temp1";
            settings.sensorResolved = true;
            settings.sensorLiveValue = 42.34;
            const status = findChild(settings, "sensorStatusLabel");
            compare(status.visible, true);
            compare(status.text, "Currently 42.3 °C");
            compare(findChild(settings, "sensorErrorMessage").visible, false);
        }

        function test_live_reading_follows_the_temperature_unit() {
            settings.sensorId = "lmsensors/nvme-pci-0100/temp1";
            settings.sensorResolved = true;
            settings.sensorLiveValue = 42.34;
            settings.tempUnit = "fahrenheit";
            // 42.34 °C → 108.2 °F.
            compare(findChild(settings, "sensorStatusLabel").text, "Currently 108.2 °F");
        }

        // ── Sub-options collapse until an id is entered ──────────────

        function test_sub_options_stay_collapsed_until_an_id_is_entered() {
            const section = findChild(settings, "sensorExtraSection");
            verify(section, "sensorExtraSection must exist");
            compare(section.visible, false);
            settings.sensorId = "lmsensors/nvme-pci-0100/temp1";
            compare(section.visible, true);
        }

        function test_bounds_hint_explains_the_sweep_semantics() {
            const hint = findChild(settings, "boundsHintLabel");
            verify(hint, "boundsHintLabel must exist");
            verify(hint.text.length > 0, "the min/max semantics hint must not be empty");
        }

        // ── Per-edit signals (label + spinboxes need an id set: the
        // section is collapsed, hence unfocusable, while sensorId is
        // empty) ──────────────────────────────────────────────────────

        function test_label_field_edits_emit_sensorLabelEdited() {
            settings.sensorId = "lmsensors/chip/temp1";
            const field = findChild(settings, "sensorLabelField");
            verify(field, "sensorLabelField must exist");
            field.forceActiveFocus();
            keyClick(Qt.Key_Z);
            compare(labelSpy.count, 1);
        }

        function test_min_spinbox_emits_minCEdited() {
            settings.sensorId = "lmsensors/chip/temp1";
            const spin = findChild(settings, "minCSpinBox");
            verify(spin, "minCSpinBox must exist");
            spin.forceActiveFocus();
            keyClick(Qt.Key_Up);
            compare(minSpy.count, 1);
            compare(minSpy.signalArguments[0][0], 21);
        }

        function test_max_spinbox_emits_maxCEdited() {
            settings.sensorId = "lmsensors/chip/temp1";
            const spin = findChild(settings, "maxCSpinBox");
            verify(spin, "maxCSpinBox must exist");
            spin.forceActiveFocus();
            keyClick(Qt.Key_Down);
            compare(maxSpy.count, 1);
            compare(maxSpy.signalArguments[0][0], 59);
        }

        // The spinboxes cross-clamp: min can never reach max and vice
        // versa, so the ring's °C→% range stays non-degenerate.
        function test_spinbox_ranges_cross_clamp() {
            const minSpin = findChild(settings, "minCSpinBox");
            const maxSpin = findChild(settings, "maxCSpinBox");
            compare(minSpin.to, settings.maxC - 1);
            compare(maxSpin.from, settings.minC + 1);
            settings.minC = 70;
            compare(maxSpin.from, 71);
        }

        // ── Temperature unit: labels + spinboxes follow tempUnit ─────
        // Bounds stay STORED in °C; only the display/editing converts.
        function test_celsius_labels_and_raw_values() {
            compare(findChild(settings, "minCLabel").text, "Minimum °C:");
            compare(findChild(settings, "maxCLabel").text, "Maximum °C:");
            compare(findChild(settings, "minCSpinBox").value, 20);
            compare(findChild(settings, "maxCSpinBox").value, 60);
        }

        function test_fahrenheit_converts_labels_and_displayed_values() {
            settings.tempUnit = "fahrenheit";
            compare(findChild(settings, "minCLabel").text, "Minimum °F:");
            compare(findChild(settings, "maxCLabel").text, "Maximum °F:");
            // 20 °C → 68 °F, 60 °C → 140 °F.
            compare(findChild(settings, "minCSpinBox").value, 68);
            compare(findChild(settings, "maxCSpinBox").value, 140);
        }

        function test_fahrenheit_edit_converts_back_to_celsius() {
            settings.sensorId = "lmsensors/chip/temp1";
            settings.tempUnit = "fahrenheit";
            const spin = findChild(settings, "minCSpinBox");
            spin.forceActiveFocus();
            // 68 °F → Up → 69 °F → round((69 − 32) × 5/9) = 21 °C stored.
            keyClick(Qt.Key_Up);
            compare(minSpy.count, 1);
            compare(minSpy.signalArguments[0][0], 21);
        }
    }
}
