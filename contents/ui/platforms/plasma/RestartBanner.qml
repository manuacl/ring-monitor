import QtQuick
import org.kde.kirigami as Kirigami

// Config-dialog banner shown while an installed update waits for a
// plasmashell restart (#172). The dialog loads the NEW pages from disk
// while the widget still runs the old code, so new settings appear but do
// nothing: this is where users hit the confusion. Header of every page
// through PlaceholderKCM.

Kirigami.InlineMessage {
    id: banner

    type: Kirigami.MessageType.Warning
    visible: restart.restartPending
    text: qsTr("A Ring Monitor update is installed but not loaded yet. Restart Plasma to apply it: until then, new settings have no effect.")
    actions: [
        Kirigami.Action {
            text: qsTr("Restart Plasma")
            icon.name: "view-refresh"
            onTriggered: restart.restartPlasma()
        }
    ]

    RestartPending {
        id: restart
    }
}
