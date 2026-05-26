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
//
// Visual: a 32×24 swatch button whose background mirrors the current
// colour. Clicking opens the modal native picker; on accept, the new
// colour is written back to `color` and the `accepted` signal fires.

QQC2.AbstractButton {
    id: root

    property color color: "#000000"
    signal accepted

    implicitWidth: 32
    implicitHeight: 24

    background: Rectangle {
        color: root.color
        border.color: Qt.darker(root.color, 1.5)
        border.width: 1
        radius: 2
    }

    onClicked: dialog.open()

    QtDialogs.ColorDialog {
        id: dialog
        // showAlphaChannel default in QtDialogs.ColorDialog is false
        // (matches the KQuickControls.ColorButton config), so the
        // user can't pick a transparency value that would conflict
        // with the rings' arcOpacity setting.
        selectedColor: root.color
        onAccepted: {
            root.color = dialog.selectedColor;
            root.accepted();
        }
    }
}
