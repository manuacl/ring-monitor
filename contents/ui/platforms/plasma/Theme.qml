import QtQuick
import org.kde.kirigami as Kirigami

// Platform adapter: re-exports Kirigami theme tokens under a stable
// surface that leaf components consume. Leaves never import Kirigami
// directly — they receive these values via properties from the
// top-level file that instantiates this adapter.
//
// A standalone (non-Plasma) build would ship a parallel Theme.qml in
// contents/ui/platforms/standalone/ exposing the same property surface
// backed by hardcoded values or Qt.labs.settings.
//
// Implemented as an Item, not a pragma Singleton: Kirigami.Theme is
// an attached property and needs an Item to attach to — a singleton
// QtObject can't resolve it.

Item {
    readonly property color textColor: Kirigami.Theme.textColor
    readonly property color highlightColor: Kirigami.Theme.highlightColor
    readonly property color backgroundColor: Kirigami.Theme.backgroundColor
    readonly property real unit: Kirigami.Units.gridUnit
    readonly property real smallSpacing: Kirigami.Units.smallSpacing
    readonly property real iconSize: Kirigami.Units.iconSizes.small

    // Derived from the background luminance (WCAG relative-luminance
    // formula, threshold 0.5). Reacts to Plasma color-scheme changes
    // because Kirigami.Theme.backgroundColor itself reacts.
    readonly property bool isDarkMode: {
        const c = Kirigami.Theme.backgroundColor;
        const lum = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
        return lum < 0.5;
    }
}
