import QtQuick
import QtTest
import "../../contents/ui/core" as Ui

// Tests for SensorTempSettings.qml — the custom hardware temperature
// sub-option: the public property surface round-trips and every edit
// control emits its dedicated signal (the wiring MetricsSubOptions
// relies on to reach the persisted config keys).

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

        function test_sensor_id_field_edits_emit_sensorIdEdited() {
            const field = findChild(settings, "sensorIdField");
            verify(field, "sensorIdField must exist");
            field.forceActiveFocus();
            keyClick(Qt.Key_A);
            compare(idSpy.count, 1);
            compare(idSpy.signalArguments[0][0], "a");
        }

        function test_label_field_edits_emit_sensorLabelEdited() {
            const field = findChild(settings, "sensorLabelField");
            verify(field, "sensorLabelField must exist");
            field.forceActiveFocus();
            keyClick(Qt.Key_Z);
            compare(labelSpy.count, 1);
        }

        function test_min_spinbox_emits_minCEdited() {
            const spin = findChild(settings, "minCSpinBox");
            verify(spin, "minCSpinBox must exist");
            spin.forceActiveFocus();
            keyClick(Qt.Key_Up);
            compare(minSpy.count, 1);
            compare(minSpy.signalArguments[0][0], 21);
        }

        function test_max_spinbox_emits_maxCEdited() {
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
    }
}
