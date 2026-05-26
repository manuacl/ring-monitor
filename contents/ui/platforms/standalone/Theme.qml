import QtQuick
import org.kde.kirigami as Kirigami

// Standalone counterpart of platforms/plasma/Theme.qml. Same property
// surface, same implementation — Kirigami is a KF6 framework that
// runs on any Qt 6 desktop, so a standalone build pulls it in as a
// runtime dep and the adapter looks identical to its Plasma sibling.
//
// The duplication is intentional, not accidental: the platform seam
// is "one adapter per platform", and even if today's bodies are
// byte-for-byte identical, the standalone branch is free to diverge
// later (e.g. expose a user-picked theme override that takes
// precedence over Kirigami.Theme).
//
// Implemented as an Item, not a pragma Singleton: Kirigami.Theme is
// an attached property and needs an Item to attach to — a singleton
// QtObject can't resolve it.

Item {
    id: root

    readonly property color textColor: Kirigami.Theme.textColor
    readonly property color highlightColor: Kirigami.Theme.highlightColor
    readonly property color backgroundColor: Kirigami.Theme.backgroundColor
    readonly property real unit: Kirigami.Units.gridUnit
    readonly property real smallSpacing: Kirigami.Units.smallSpacing
    readonly property real iconSize: Kirigami.Units.iconSizes.small

    // Same Qt.styleHints subscription pattern as the Plasma adapter
    // (see ../plasma/Theme.qml for the full rationale): the property
    // itself has no NOTIFY signal, so we watch colorSchemeChanged and
    // proxy through an intermediate _qtScheme to keep isDarkMode
    // reactive and readonly. Outside plasmashell this works without
    // any caveat — the Vapor / look-and-feel quirk that motivated the
    // explicit Light/Dark override is Plasma-shell-specific.
    property int _qtScheme: Qt.styleHints.colorScheme
    readonly property bool isDarkMode: root._qtScheme === Qt.Dark

    Connections {
        target: Qt.styleHints
        function onColorSchemeChanged(scheme) {
            root._qtScheme = scheme;
        }
    }
}
