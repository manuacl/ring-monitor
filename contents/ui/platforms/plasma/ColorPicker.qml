import QtQuick
import org.kde.kquickcontrols as KQuickControls

// Platform adapter: thin wrap of KQuickControls.ColorButton so leaves
// can let the user pick a color without importing
// org.kde.kquickcontrols directly. A standalone build ships a parallel
// ColorPicker.qml backed by a plain Button + QtQuick.Dialogs.ColorDialog.
//
// Surface: re-exposes the `color` property of ColorButton and forces
// showAlphaChannel=false (the rings already have arcOpacity for that).
KQuickControls.ColorButton {
    showAlphaChannel: false
}
