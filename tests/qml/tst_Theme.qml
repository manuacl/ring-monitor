import QtQuick
import QtTest
import "../../contents/ui/platforms/plasma" as Platform

// Smoke tests for the Theme adapter (PR 1 of plasma-isolation).
// Asserts the adapter exposes the property surface the leaf components
// rely on. Catches typos / removed re-exports — if any of these break,
// the leaves would silently render with their hardcoded fallback
// values in production.

Item {
    id: root
    width: 50
    height: 50

    Platform.Theme {
        id: theme
    }

    TestCase {
        name: "Theme"
        when: windowShown

        function test_exposes_color_tokens() {
            verify(theme.textColor !== undefined, "textColor must be defined");
            verify(theme.highlightColor !== undefined, "highlightColor must be defined");
            verify(theme.backgroundColor !== undefined, "backgroundColor must be defined");
        }

        function test_exposes_size_tokens() {
            verify(theme.unit > 0, "unit must be a positive number, got " + theme.unit);
            verify(theme.smallSpacing > 0, "smallSpacing must be a positive number, got " + theme.smallSpacing);
            verify(theme.iconSize > 0, "iconSize must be a positive number, got " + theme.iconSize);
        }
    }
}
