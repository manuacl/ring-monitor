import QtQuick
import QtTest
import "../../contents/ui/core" as Ui

// Smoke tests for AboutBody.qml — verifies the three notification
// states render the right copy and that the action buttons only
// surface when an update is actually available.

Item {
    id: root
    width: 600
    height: 500

    Ui.AboutBody {
        id: body
        anchors.fill: parent
    }

    TestCase {
        name: "AboutBody"
        when: windowShown

        function init() {
            body.localVersion = "0.4.0";
            body.remoteVersion = "";
            body.updateAvailable = false;
            body.checkForUpdatesEnabled = true;
        }

        // ── State 1: still checking (first run, no cached remote yet) ─
        function test_initial_state_says_checking() {
            body.remoteVersion = "";
            body.updateAvailable = false;
            verify(body._statusLabel.text.toLowerCase().indexOf("checking") !== -1, "Expected 'checking' status, got: " + body._statusLabel.text);
            verify(!body._openStoreButton.visible || body._openStoreButton.parent.visible === false);
            verify(!body._gotItButton.visible || body._gotItButton.parent.visible === false);
        }

        // ── State 2: up to date (remote == local) ────────────────────
        function test_up_to_date_says_latest() {
            body.remoteVersion = "v0.4.0";
            body.updateAvailable = false;
            verify(body._statusLabel.text.toLowerCase().indexOf("latest") !== -1, "Expected 'latest' status, got: " + body._statusLabel.text);
        }

        // ── State 3: update available → version + buttons visible ────
        function test_update_available_shows_version_and_buttons() {
            body.remoteVersion = "v0.5.0";
            body.updateAvailable = true;
            verify(body._statusLabel.text.indexOf("v0.5.0") !== -1, "Status should mention the remote version v0.5.0, got: " + body._statusLabel.text);
            verify(body._openStoreButton.visible);
            verify(body._gotItButton.visible);
        }

        // ── State 4: checks disabled ─────────────────────────────────
        function test_disabled_says_disabled() {
            body.checkForUpdatesEnabled = false;
            verify(body._statusLabel.text.toLowerCase().indexOf("disabled") !== -1, "Expected 'disabled' status, got: " + body._statusLabel.text);
        }

        // ── Toggle signal: clicking the checkbox emits checkForUpdatesToggled ─
        function test_checkbox_emits_toggle_signal() {
            body.checkForUpdatesEnabled = true;
            const spy = createTemporaryObject(signalSpyComponent, root, {
                target: body,
                signalName: "checkForUpdatesToggled"
            });
            // Programmatic click on the CheckBox.
            body._checkBox.toggle();
            body._checkBox.clicked();
            compare(spy.count, 1);
            // CheckBox.toggle() flipped the visual state to false; the
            // signal carries that new value.
            compare(spy.signalArguments[0][0], false);
        }

        // ── Action buttons fan out to signals ────────────────────────
        function test_got_it_emits_acknowledge_clicked() {
            body.remoteVersion = "v0.5.0";
            body.updateAvailable = true;
            wait(20);
            const spy = createTemporaryObject(signalSpyComponent, root, {
                target: body,
                signalName: "acknowledgeClicked"
            });
            body._gotItButton.clicked();
            compare(spy.count, 1);
        }

        function test_open_store_emits_open_store_page_clicked() {
            body.remoteVersion = "v0.5.0";
            body.updateAvailable = true;
            wait(20);
            const spy = createTemporaryObject(signalSpyComponent, root, {
                target: body,
                signalName: "openStorePageClicked"
            });
            body._openStoreButton.clicked();
            compare(spy.count, 1);
        }

        // ── Autostart toggle: checked driven by a Binding element ────────
        function test_autostart_checkbox_emits_toggle_signal() {
            body.autostartAvailable = true;
            body.autostartEnabled = false;
            const spy = createTemporaryObject(signalSpyComponent, root, {
                target: body,
                signalName: "autostartToggled"
            });
            body._autostartCheckBox.toggle();
            body._autostartCheckBox.clicked();
            compare(spy.count, 1);
            compare(spy.signalArguments[0][0], true);
        }

        // ── Menu-entry toggle: gated by menuEntryAvailable, emits signal ─
        function test_menu_entry_hidden_until_available() {
            body.menuEntryAvailable = false;
            verify(!body._menuEntryCheckBox.visible, "menu-entry toggle must stay hidden on hosts that don't wire it (e.g. Plasma)");
            body.menuEntryAvailable = true;
            verify(body._menuEntryCheckBox.visible, "menu-entry toggle must show once the standalone host sets menuEntryAvailable");
        }

        function test_menu_entry_checkbox_emits_toggle_signal() {
            body.menuEntryAvailable = true;
            body.menuEntryEnabled = false;
            const spy = createTemporaryObject(signalSpyComponent, root, {
                target: body,
                signalName: "menuEntryToggled"
            });
            body._menuEntryCheckBox.toggle();
            body._menuEntryCheckBox.clicked();
            compare(spy.count, 1);
            compare(spy.signalArguments[0][0], true);
        }
    }

    Component {
        id: signalSpyComponent
        SignalSpy {}
    }
}
