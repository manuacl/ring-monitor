import QtQuick
import org.kde.kirigami as Kirigami

// Platform adapter: thin wrap of Kirigami.Icon so leaves can use
// themed icons without importing Kirigami directly. A standalone
// build ships a parallel ThemedIcon.qml backed by Image with
// "image://theme/..." source.
Kirigami.Icon {}
