import QtQuick
import QtTest
import "../../contents/ui/core" as Ui

// Tests for TemperatureUnitSettings.qml — the temp-unit radio row:
// the tempUnit property drives which radio is checked and a radio
// click emits tempUnitEdited with the new mode. The radios are leaf
// controls, reached by objectName (tests/CLAUDE.md leaf-control rule).

Item {
    id: root
    width: 400
    height: 50

    Ui.TemperatureUnitSettings {
        id: settings
        anchors.fill: parent
        tempUnit: "auto"
    }

    SignalSpy {
        id: unitSpy
        target: settings
        signalName: "tempUnitEdited"
    }

    TestCase {
        name: "TemperatureUnitSettings"
        when: windowShown

        function init() {
            settings.tempUnit = "auto";
            unitSpy.clear();
        }

        function test_tempUnit_drives_the_checked_radio() {
            const auto = findChild(settings, "tempUnitAutoRadio");
            const celsius = findChild(settings, "tempUnitCelsiusRadio");
            const fahrenheit = findChild(settings, "tempUnitFahrenheitRadio");
            verify(auto && celsius && fahrenheit, "all three radios must be findable");
            verify(auto.checked);
            verify(!celsius.checked);
            verify(!fahrenheit.checked);
            settings.tempUnit = "celsius";
            verify(!auto.checked);
            verify(celsius.checked);
            settings.tempUnit = "fahrenheit";
            verify(fahrenheit.checked);
            verify(!celsius.checked);
        }

        function test_radio_click_emits_tempUnitEdited() {
            mouseClick(findChild(settings, "tempUnitCelsiusRadio"));
            compare(unitSpy.count, 1);
            compare(unitSpy.signalArguments[0][0], "celsius");
            mouseClick(findChild(settings, "tempUnitFahrenheitRadio"));
            compare(unitSpy.count, 2);
            compare(unitSpy.signalArguments[1][0], "fahrenheit");
            mouseClick(findChild(settings, "tempUnitAutoRadio"));
            compare(unitSpy.count, 3);
            compare(unitSpy.signalArguments[2][0], "auto");
        }
    }
}
