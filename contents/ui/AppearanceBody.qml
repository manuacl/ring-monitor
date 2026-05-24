import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Body of the Appearance config page. Owns the form layout, the
// RadioButtons, and the three opacity sliders.
//
// Bidirectional state is exposed as plain QML properties; the wrapper
// (configAppearance.qml) bridges them to Plasma's cfg_* magic via
// `property alias` declarations. The body never touches Plasmoid
// configuration directly.
//
// i18n strings use qsTr() rather than Plasma's i18n() — Qt's
// translation framework works in both the Plasma applet runtime and
// a future standalone build, while i18n() requires KF6 runtime. See
// docs/plasma-isolation/plan.md.

Kirigami.FormLayout {
    id: body

    // ── Bridged via aliases in the wrapper (cfg_orientation ↔ body.orientation, etc.) ──
    property string orientation: "horizontal"
    property real textOpacity: 1.0
    property real trackOpacity: 0.15
    property real arcOpacity: 1.0

    RowLayout {
        Kirigami.FormData.label: qsTr("Orientation:")

        QQC2.RadioButton {
            text: qsTr("Horizontal")
            checked: body.orientation === "horizontal"
            onClicked: body.orientation = "horizontal"
        }
        QQC2.RadioButton {
            text: qsTr("Vertical")
            checked: body.orientation === "vertical"
            onClicked: body.orientation = "vertical"
        }
    }

    Item {
        Kirigami.FormData.isSection: true
    }

    RowLayout {
        Kirigami.FormData.label: qsTr("Text opacity:")
        Layout.fillWidth: true

        QQC2.Slider {
            id: textSlider
            from: 0
            to: 1
            stepSize: 0.05
            value: body.textOpacity
            onMoved: body.textOpacity = value
            Layout.fillWidth: true
        }
        QQC2.Label {
            text: Math.round(body.textOpacity * 100) + " %"
            Layout.minimumWidth: Kirigami.Units.gridUnit * 3
            horizontalAlignment: Text.AlignRight
        }
    }

    RowLayout {
        Kirigami.FormData.label: qsTr("Track opacity:")
        Layout.fillWidth: true

        QQC2.Slider {
            id: trackSlider
            from: 0
            to: 1
            stepSize: 0.05
            value: body.trackOpacity
            onMoved: body.trackOpacity = value
            Layout.fillWidth: true
        }
        QQC2.Label {
            text: Math.round(body.trackOpacity * 100) + " %"
            Layout.minimumWidth: Kirigami.Units.gridUnit * 3
            horizontalAlignment: Text.AlignRight
        }
    }

    RowLayout {
        Kirigami.FormData.label: qsTr("Arc opacity:")
        Layout.fillWidth: true

        QQC2.Slider {
            id: arcSlider
            from: 0
            to: 1
            stepSize: 0.05
            value: body.arcOpacity
            onMoved: body.arcOpacity = value
            Layout.fillWidth: true
        }
        QQC2.Label {
            text: Math.round(body.arcOpacity * 100) + " %"
            Layout.minimumWidth: Kirigami.Units.gridUnit * 3
            horizontalAlignment: Text.AlignRight
        }
    }

    // ── Test hooks ──────────────────────────────────────────────────
    readonly property alias _textSlider: textSlider
    readonly property alias _trackSlider: trackSlider
    readonly property alias _arcSlider: arcSlider
}
