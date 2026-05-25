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

    // Private probe used only by isDarkMode. The widget itself runs in
    // the panel context, where Kirigami.Theme.backgroundColor reflects
    // the panel background (often dark independent of the user's
    // System Settings → Colors choice). To detect the system-level
    // scheme, we read the Window colorSet — what application windows
    // use, which follows the system color scheme directly.
    Item {
        id: _systemSchemeProbe
        Kirigami.Theme.inherit: false
        Kirigami.Theme.colorSet: Kirigami.Theme.Window
        readonly property color windowBackground: Kirigami.Theme.backgroundColor
    }

    // Derived from the system Window background luminance (WCAG
    // relative-luminance formula, threshold 0.5). Reacts when the user
    // switches Plasma color scheme because the probe's backgroundColor
    // itself reacts.
    readonly property bool isDarkMode: {
        const c = _systemSchemeProbe.windowBackground;
        const lum = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
        return lum < 0.5;
    }
}
