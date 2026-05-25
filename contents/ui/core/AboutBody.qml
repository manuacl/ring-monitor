import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Body of the About config page. Portable (Kirigami-only) so the
// standalone build can reuse it verbatim — the Plasma wrapper
// (configAbout.qml) bridges cfg_* magic to plain properties and feeds
// the UpdateChecker.
//
// Layout (top → bottom):
//   1. Widget name + current version
//   2. Update status block (if checks enabled): "Up to date" or
//      "Update v0.5.0 available" with [Open release] [Got it] buttons
//   3. Installation methods — three subsections (KDE Store / from
//      source / KNewStuff in System Settings)
//   4. Settings — "Check for updates automatically" toggle

Kirigami.FormLayout {
    id: body

    // ── Inputs ──────────────────────────────────────────────────────
    // localVersion comes from Plasmoid.metaData via the wrapper;
    // updateAvailable / remoteVersion come from the shared
    // UpdateChecker instance the wrapper passes in.
    property string localVersion: ""
    property string remoteVersion: ""
    property bool updateAvailable: false
    property bool checkForUpdatesEnabled: true

    // ── Outputs (parent wires these into the UpdateChecker / config) ─
    signal acknowledgeClicked
    signal openStorePageClicked
    signal checkForUpdatesToggled(bool on)

    // ── 1. Version header ───────────────────────────────────────────
    QQC2.Label {
        Kirigami.FormData.label: qsTr("Version:")
        text: body.localVersion || qsTr("unknown")
        font.family: "monospace"
    }

    // ── 2. Update status ────────────────────────────────────────────
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

    // ── 3. Installation methods ─────────────────────────────────────
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

    // ── 4. Settings ─────────────────────────────────────────────────
    QQC2.CheckBox {
        id: checkBox
        Kirigami.FormData.label: qsTr("Updates:")
        text: qsTr("Check for updates automatically (once per day)")
        checked: body.checkForUpdatesEnabled
        onClicked: body.checkForUpdatesToggled(checked)
    }

    // ── Test hooks ──────────────────────────────────────────────────
    readonly property alias _statusLabel: statusLabel
    readonly property alias _openStoreButton: openStoreButton
    readonly property alias _gotItButton: gotItButton
    readonly property alias _checkBox: checkBox
}
