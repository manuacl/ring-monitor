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
    id: root

    readonly property color textColor: Kirigami.Theme.textColor
    readonly property color highlightColor: Kirigami.Theme.highlightColor
    readonly property color backgroundColor: Kirigami.Theme.backgroundColor
    readonly property real unit: Kirigami.Units.gridUnit
    readonly property real smallSpacing: Kirigami.Units.smallSpacing
    readonly property real iconSize: Kirigami.Units.iconSizes.small

    // System light/dark detection.
    //
    // Source of truth: Qt.styleHints.colorScheme (Qt 6.5+). This is
    // the canonical KDE signal since KF 6.22, where KColorScheme was
    // reworked to use the Qt API directly. We read .colorScheme for
    // the initial value, and subscribe to colorSchemeChanged for
    // live updates — Qt's own documentation warns the property
    // itself has no NOTIFY, so binding it would never re-evaluate.
    //
    // _qtScheme is an intermediate QML property so isDarkMode can
    // stay readonly (the Connections handler writes to _qtScheme,
    // isDarkMode binds reactively to it).
    //
    // Caveat: plasmashell on some Plasma 6 setups (notably with
    // third-party look-and-feel themes like Vapor) does not actually
    // emit the colorSchemeChanged signal live to running panel
    // widgets — the user must then use the explicit "Always light"
    // / "Always dark" override in the config page.
    property int _qtScheme: Qt.styleHints.colorScheme
    readonly property bool isDarkMode: root._qtScheme === Qt.Dark

    Connections {
        target: Qt.styleHints
        function onColorSchemeChanged(scheme) {
            root._qtScheme = scheme;
        }
    }
}
