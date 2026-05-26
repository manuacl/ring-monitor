import QtQuick
import QtQuick.Window
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import RingMonitor.Standalone
import "../../core" as Core

// Standalone counterpart of the Plasma config dialog
// (contents/ui/config*.qml hosted in System Settings → Plasma's panel
// applet config). Tabbed Window wrapping the same three bodies the
// Plasma side reuses: MetricsBody, AppearanceBody, AboutBody.
//
// Two-way binding pattern. The Plasma side uses SimpleKCM's `cfg_*`
// magic + bidirectional `property alias` to bridge body properties
// to KConfig. Standalone has no SimpleKCM — we bridge by hand:
//
//   1. _pullFromStore() copies configStore.X → body.X at open time
//   2. The body's onXChanged handler (wired in Component.onCompleted
//      via `body.XChanged.connect(...)`) writes back to configStore.X
//
// Because Qt.labs.settings persists Settings property writes on the
// next event-loop pass, write-back is immediate and durable. No
// explicit "Apply" button needed — live editing matches the Plasma
// SimpleKCM behaviour from the user's point of view.
//
// Wired by Main.qml: instantiated once at startup; the right-click
// "Settings…" menu item calls dialog.show().

Window {
    id: dialog

    // Injected by Main.qml.
    property var configStore
    property var theme
    property var updateChecker

    title: qsTr("ring-monitor settings")
    width: 640
    height: 540
    visible: false
    // Track the Kirigami theme so the dialog blends with the user's
    // system colour scheme. Without this the Window defaults to the
    // platform's "no colour set" white, which clashes with a dark
    // Plasma scheme.
    color: dialog.theme ? dialog.theme.backgroundColor : Kirigami.Theme.backgroundColor

    // Centre on the primary screen + wire the two-way bridges at
    // startup. Single Component.onCompleted because QML only allows
    // one per object. Without the centring the window pops at (0, 0)
    // which lands in the corner of the leftmost monitor.
    Component.onCompleted: {
        dialog.x = (Screen.width - dialog.width) / 2;
        dialog.y = (Screen.height - dialog.height) / 2;
        dialog._wireBridges();
    }

    // ColorPicker injected into AppearanceBody as a Component — the
    // body stays platform-agnostic; the standalone ColorPicker wraps
    // a plain Button + QtQuick.Dialogs.ColorDialog instead of
    // KQuickControls.ColorButton (Plasma side).
    Component {
        id: colorPickerComponent
        ColorPicker {}
    }

    // Autostart helper — manages ~/.config/autostart/<id>.desktop.
    // Wired into AboutBody so the "Start automatically on login"
    // toggle reads its current state and writes back on user click.
    // Plasma users don't see this toggle (plasmashell handles it
    // via the panel layout); AboutBody gates the row on
    // `autostartAvailable`, which only this side sets to true.
    Autostart {
        id: autostartHelper
    }

    // ── Layout ──────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing

        QQC2.TabBar {
            id: tabBar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            QQC2.TabButton {
                text: qsTr("Metrics")
            }
            QQC2.TabButton {
                text: qsTr("Appearance")
            }
            QQC2.TabButton {
                text: qsTr("About")
            }
        }

        StackLayout {
            anchors.top: tabBar.bottom
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: Kirigami.Units.smallSpacing
            currentIndex: tabBar.currentIndex

            QQC2.ScrollView {
                Core.MetricsBody {
                    id: metricsBody
                    theme: dialog.theme
                    width: parent.parent.width
                }
            }

            QQC2.ScrollView {
                Core.AppearanceBody {
                    id: appearanceBody
                    width: parent.parent.width
                    colorPickerComponent: colorPickerComponent
                }
            }

            QQC2.ScrollView {
                Core.AboutBody {
                    id: aboutBody
                    width: parent.parent.width
                    localVersion: dialog.configStore ? dialog.configStore.localVersion : ""
                    remoteVersion: dialog.updateChecker ? dialog.updateChecker.remoteVersion : ""
                    updateAvailable: dialog.updateChecker ? dialog.updateChecker.updateAvailable : false
                    checkForUpdatesEnabled: dialog.configStore ? dialog.configStore.checkForUpdatesEnabled : true
                    autostartAvailable: true
                    autostartEnabled: autostartHelper.enabled

                    onAcknowledgeClicked: dialog.updateChecker && dialog.updateChecker.acknowledge()
                    onOpenStorePageClicked: dialog.updateChecker && dialog.updateChecker.openStorePage()
                    onCheckForUpdatesToggled: on => {
                        if (dialog.configStore)
                            dialog.configStore.checkForUpdatesEnabled = on;
                    }
                    onAutostartToggled: on => autostartHelper.setEnabled(on)
                }
            }
        }
    }

    // ── Two-way binding wiring ──────────────────────────────────────
    //
    // Each entry is [body, bodyProp, storeProp]. storeProp defaults
    // to bodyProp when it's the same on both sides; the two CSV
    // properties on MetricsBody have to declare the rename
    // explicitly. The list is the single source of truth — adding a
    // new persisted key means appending one line here AND declaring
    // it in ConfigStore.qml (the standalone-config-store.test.mjs
    // guard catches drift between main.xml and ConfigStore but does
    // not catch drift between ConfigStore and this dialog — see the
    // standalone-settings-dialog.test.mjs text guard for that).
    readonly property var _bridgeMap: [
        // MetricsBody
        [metricsBody, "metricOrderCsv", "metricOrder"], [metricsBody, "enabledMetricsCsv", "enabledMetrics"], [metricsBody, "showCpuCores", "showCpuCores"], [metricsBody, "mergeCpuTemp", "mergeCpuTemp"], [metricsBody, "mergeGpuTemp", "mergeGpuTemp"], [metricsBody, "tempUnit", "tempUnit"],
        // AppearanceBody
        [appearanceBody, "orientation", "orientation"], [appearanceBody, "ringSize", "ringSize"], [appearanceBody, "ringSpacingPercent", "ringSpacingPercent"], [appearanceBody, "windowMargin", "windowMargin"], [appearanceBody, "textOpacity", "textOpacity"], [appearanceBody, "trackOpacity", "trackOpacity"], [appearanceBody, "arcOpacity", "arcOpacity"], [appearanceBody, "colorTheme", "colorTheme"], [appearanceBody, "colorMode", "colorMode"], [appearanceBody, "customColorLight", "customColorLight"], [appearanceBody, "customColorDark", "customColorDark"], [appearanceBody, "textColorMode", "textColorMode"], [appearanceBody, "customTextColorLight", "customTextColorLight"], [appearanceBody, "customTextColorDark", "customTextColorDark"]]

    function _wireBridges() {
        if (!dialog.configStore)
            return;
        for (let i = 0; i < _bridgeMap.length; i++) {
            let body = _bridgeMap[i][0];
            let bodyProp = _bridgeMap[i][1];
            let storeProp = _bridgeMap[i][2];
            // 1. Initial pull from the store.
            body[bodyProp] = dialog.configStore[storeProp];
            // 2. Write-back on body change. Closing over loop vars via
            //    an IIFE so each handler captures its own pair.
            (function (b, bp, sp) {
                    b[bp + "Changed"].connect(function () {
                        dialog.configStore[sp] = b[bp];
                    });
                })(body, bodyProp, storeProp);
        }
        // MetricsBody needs an explicit loadOrder() after metricOrderCsv
        // is set — that's what populates the displayed ListModel.
        metricsBody.loadOrder();
    }
}
