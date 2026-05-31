import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs as QtDialogs

// Standalone counterpart of platforms/plasma/ColorPicker.qml. Wraps a
// plain Qt Button + QtQuick.Dialogs.ColorDialog so the standalone
// build does not need `org.kde.kquickcontrols` (which is shipped
// only as part of KDE Frameworks and would force an unnecessary
// runtime dep).
//
// Same public surface as the Plasma adapter:
//   - writable `color` property
//   - `accepted` signal fired when the user confirms a new colour
// The two-way binding in core/AppearanceBody.qml works against this
// surface unchanged.

QQC2.AbstractButton {
    id: root

    property color color: "#000000"
    signal accepted

    // Test hook (internal): lets tst_ColorPicker drive the dialog without
    // showing native UI under qmltestrunner.
    readonly property alias _dialog: dialog

    implicitWidth: 32
    implicitHeight: 24

    background: Rectangle {
        color: root.color
        border.color: Qt.darker(root.color, 1.5)
        border.width: 1
        radius: 2
    }

    // Seed the dialog from the current colour on each open — imperatively,
    // NOT via `selectedColor: root.color`. A permanent binding kept
    // selectedColor pinned to `color`, so the user's pick was overwritten
    // and `onAccepted` re-read the old colour → `color` never changed and
    // the swatch never updated (the standalone dark-text-colour bug). See
    // tests/qml/tst_ColorPicker.qml.
    onClicked: {
        dialog.selectedColor = root.color;
        dialog.open();
    }

    QtDialogs.ColorDialog {
        id: dialog
        // showAlphaChannel defaults false here (matches the Plasma
        // ColorButton): no transparency value that would conflict with
        // the rings' arcOpacity.
        onAccepted: {
            root.color = dialog.selectedColor;
            root.accepted();
        }
    }
}
