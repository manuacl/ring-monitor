import QtQuick
import QtTest
import "../../contents/ui/platforms/plasma" as Platform

// Smoke test for the ThemedIcon adapter. Confirms the wrapper accepts
// a source assignment — guards against the wrapper becoming
// unusable (e.g. if a future refactor changes the root type and loses
// the source property).

Item {
    id: root
    width: 50
    height: 50

    Platform.ThemedIcon {
        id: themedIcon
        source: "transform-move"
    }

    TestCase {
        name: "ThemedIcon"
        when: windowShown

        function test_source_property_passthrough() {
            compare(themedIcon.source, "transform-move");
        }
    }
}
