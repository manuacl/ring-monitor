import QtQuick
import QtTest
import "../../contents/ui/core" as Ui

// Tests for TempRangeSettings.qml — the shared min/max bounds editor
// (issue #164 section 5) used by the sensorTemp, cpuTemp and gpuTemp
// rows. Covers the public surface (props + per-edit signals), the
// cross-clamping ranges and the display-unit conversion.

Item {
    id: root
    width: 400
    height: 300

    Ui.TempRangeSettings {
        id: settings
        anchors.fill: parent
        minC: 30
        maxC: 90
        // Pinned (not "auto") so the tests don't depend on the runner's
        // locale measurement system.
        tempUnit: "celsius"
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
        name: "TempRangeSettings"
        when: windowShown

        function init() {
            settings.minC = 30;
            settings.maxC = 90;
            settings.tempUnit = "celsius";
            minSpy.clear();
            maxSpy.clear();
        }

        function test_public_properties_round_trip() {
            settings.minC = 10;
            settings.maxC = 80;
            compare(settings.minC, 10);
            compare(settings.maxC, 80);
        }

        function test_bounds_hint_explains_the_sweep_semantics() {
            const hint = findChild(settings, "boundsHintLabel");
            verify(hint, "boundsHintLabel must exist");
            verify(hint.text.length > 0, "the min/max semantics hint must not be empty");
        }

        function test_min_spinbox_emits_minCEdited() {
            const spin = findChild(settings, "minCSpinBox");
            verify(spin, "minCSpinBox must exist");
            spin.forceActiveFocus();
            keyClick(Qt.Key_Up);
            compare(minSpy.count, 1);
            compare(minSpy.signalArguments[0][0], 31);
        }

        function test_max_spinbox_emits_maxCEdited() {
            const spin = findChild(settings, "maxCSpinBox");
            verify(spin, "maxCSpinBox must exist");
            spin.forceActiveFocus();
            keyClick(Qt.Key_Down);
            compare(maxSpy.count, 1);
            compare(maxSpy.signalArguments[0][0], 89);
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
            compare(findChild(settings, "minCSpinBox").value, 30);
            compare(findChild(settings, "maxCSpinBox").value, 90);
        }

        function test_fahrenheit_converts_labels_and_displayed_values() {
            settings.tempUnit = "fahrenheit";
            compare(findChild(settings, "minCLabel").text, "Minimum °F:");
            compare(findChild(settings, "maxCLabel").text, "Maximum °F:");
            // 30 °C → 86 °F, 90 °C → 194 °F.
            compare(findChild(settings, "minCSpinBox").value, 86);
            compare(findChild(settings, "maxCSpinBox").value, 194);
        }

        function test_fahrenheit_edit_converts_back_to_celsius() {
            settings.tempUnit = "fahrenheit";
            const spin = findChild(settings, "minCSpinBox");
            spin.forceActiveFocus();
            // 86 °F → Up → 87 °F → round((87 − 32) × 5/9) = 31 °C stored.
            keyClick(Qt.Key_Up);
            compare(minSpy.count, 1);
            compare(minSpy.signalArguments[0][0], 31);
        }
    }
}
