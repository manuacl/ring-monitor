import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Body of the About config page. Portable (Kirigami-only) so the
// standalone build can reuse it verbatim — the Plasma wrapper
// (configAbout.qml) bridges cfg_* magic to plain properties and feeds
// the UpdateChecker.

Kirigami.FormLayout {
    id: body

    // localVersion comes from Plasmoid.metaData via the wrapper;
    // updateAvailable / remoteVersion come from the shared
    // UpdateChecker instance the wrapper passes in.
    property string localVersion: ""
    property string remoteVersion: ""
    property bool updateAvailable: false
    property bool checkForUpdatesEnabled: true

    // Plasma users get auto-launch via plasmashell, so the wrapper
    // leaves `autostartAvailable: false` and the toggle stays hidden.
    // Standalone wires `true` + the current state — see the
    // platforms/standalone/SettingsDialog.qml Autostart wiring.
    property bool autostartAvailable: false
    property bool autostartEnabled: false

    // Same gate as autostart: only the standalone wrapper sets this
    // true and wires the MenuEntry backend (writes a launcher to
    // ~/.local/share/applications/). Plasma users already get a menu
    // entry from the .plasmoid install, so it stays hidden there.
    property bool menuEntryAvailable: false
    property bool menuEntryEnabled: false

    signal acknowledgeClicked
    signal openStorePageClicked
    signal checkForUpdatesToggled(bool on)
    signal autostartToggled(bool on)
    signal menuEntryToggled(bool on)

    QQC2.Label {
        Kirigami.FormData.label: qsTr("Version:")
        text: body.localVersion || qsTr("unknown")
        font.family: "monospace"
    }

    // Distinct visual treatments for the three states so the user
    // reads at a glance: "you have something to do" vs "nothing to
    // do" vs "check disabled".
    Rectangle {
        Kirigami.FormData.label: qsTr("Status:")
        Layout.fillWidth: true
        implicitHeight: statusContent.implicitHeight + 16
        color: body.updateAvailable ? Qt.alpha(Kirigami.Theme.highlightColor, 0.15) : "transparent"
        border.color: body.updateAvailable ? Kirigami.Theme.highlightColor : Qt.alpha(Kirigami.Theme.textColor, 0.2)
        border.width: 1
        radius: 4

        ColumnLayout {
            id: statusContent
            anchors.fill: parent
            anchors.margins: 8
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                id: statusLabel
                text: {
                    if (!body.checkForUpdatesEnabled)
                        return qsTr("Update checks are disabled.");
                    if (body.updateAvailable)
                        return qsTr("Update available: %1").arg(body.remoteVersion);
                    if (body.remoteVersion === "")
                        return qsTr("Checking for updates…");
                    return qsTr("You are running the latest version.");
                }
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            RowLayout {
                visible: body.updateAvailable
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                QQC2.Button {
                    id: openStoreButton
                    text: qsTr("Open KDE Store")
                    icon.name: "internet-services"
                    onClicked: body.openStorePageClicked()
                }
                QQC2.Button {
                    id: gotItButton
                    text: qsTr("Got it")
                    icon.name: "dialog-ok"
                    onClicked: body.acknowledgeClicked()
                }
                Item {
                    Layout.fillWidth: true
                }
            }
        }
    }

    Item {
        Kirigami.FormData.isSection: true
    }

    QQC2.Label {
        Kirigami.FormData.label: qsTr("KDE Store:")
        text: qsTr("<a href=\"https://www.opendesktop.org/p/2360410\">opendesktop.org/p/2360410</a>")
        onLinkActivated: link => Qt.openUrlExternally(link)
        // Kirigami quirk: hover cursor on link Labels needs an explicit
        // MouseArea overlay (see KDE docs).
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
        }
    }

    QQC2.Label {
        Kirigami.FormData.label: qsTr("From source:")
        text: qsTr("<a href=\"https://github.com/manuacl/ring-monitor#installation\">github.com/manuacl/ring-monitor</a>")
        onLinkActivated: link => Qt.openUrlExternally(link)
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
        }
    }

    QQC2.Label {
        Kirigami.FormData.label: qsTr("Or:")
        text: qsTr("Plasma → Add Widgets → ⋮ → Get New Widgets")
        opacity: 0.7
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }

    Item {
        Kirigami.FormData.isSection: true
    }

    QQC2.CheckBox {
        id: checkBox
        Kirigami.FormData.label: qsTr("Updates:")
        text: qsTr("Check for updates automatically (once per day)")
        checked: body.checkForUpdatesEnabled
        onClicked: body.checkForUpdatesToggled(checked)
    }

    QQC2.CheckBox {
        id: autostartCheckBox
        Kirigami.FormData.label: qsTr("Startup:")
        text: qsTr("Start automatically on login")
        visible: body.autostartAvailable
        onClicked: body.autostartToggled(checked)

        // Same reason as menuEntryCheckBox below: drive `checked` through a
        // Binding element so a failed autostart write (which still emits
        // enabledChanged with `enabled` false) un-ticks the box instead of
        // leaving it lying. A plain `checked:` binding would be severed by
        // QQC2's self-assign on click. See core/CLAUDE.md "Binding a
        // Loader-injected child that also self-assigns".
        Binding {
            target: autostartCheckBox
            property: "checked"
            value: body.autostartEnabled
        }
    }

    QQC2.CheckBox {
        id: menuEntryCheckBox
        text: qsTr("Show in application menu")
        visible: body.menuEntryAvailable
        onClicked: body.menuEntryToggled(checked)

        // Drive `checked` through a Binding element, not a declarative
        // `checked: body.menuEntryEnabled`: QQC2 self-assigns `checked` on
        // the click, which would sever a plain binding. The Binding
        // re-applies on every menuEntryEnabled change, so if the toggle's
        // .desktop write fails (unwritable dir, full disk) the backend
        // emits with `enabled` still false and the box un-ticks instead of
        // lying that an entry was created. See core/CLAUDE.md "Binding a
        // Loader-injected child that also self-assigns".
        Binding {
            target: menuEntryCheckBox
            property: "checked"
            value: body.menuEntryEnabled
        }
    }

    // ── Test hooks ──────────────────────────────────────────────────
    readonly property alias _statusLabel: statusLabel
    readonly property alias _openStoreButton: openStoreButton
    readonly property alias _gotItButton: gotItButton
    readonly property alias _checkBox: checkBox
    readonly property alias _autostartCheckBox: autostartCheckBox
    readonly property alias _menuEntryCheckBox: menuEntryCheckBox
}
