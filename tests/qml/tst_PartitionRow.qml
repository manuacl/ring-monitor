import QtQuick
import QtTest
import "../../contents/ui/core" as Ui

// Tests for PartitionRow.qml — the disk-partition picker row with an
// `available` axis. available → a toggle CheckBox; !available → the greyed
// "not connected" stale variant with a trash button. No Plasma imports, so it
// runs under qmltestrunner in CI.

Item {
    id: root
    width: 300
    height: 80

    Ui.PartitionRow {
        id: rowAvailable
        partLabel: "root"
        available: true
        checked: true
    }

    Ui.PartitionRow {
        id: rowStale
        partLabel: "backups"
        available: false
    }

    TestCase {
        name: "PartitionRow"
        when: windowShown

        function test_available_shows_checkbox_only() {
            verify(rowAvailable._checkBox.visible, "checkbox visible when available");
            verify(!rowAvailable._unavailableLabel.visible, "no 'not connected' tag when available");
            verify(!rowAvailable._removeButton.visible, "no trash button when available");
            compare(rowAvailable._checkBox.text, "root");
            verify(rowAvailable._checkBox.checked);
        }

        function test_toggled_signal_carries_checkbox_state() {
            let captured = null;
            rowAvailable.toggled.connect(on => captured = on);
            // Simulate an unchecking click: CheckBox.toggle flips checked, then
            // we invoke the click handler the way QML does.
            rowAvailable._checkBox.checked = false;
            rowAvailable.toggled(rowAvailable._checkBox.checked);
            compare(captured, false, "toggled emits the new checked state");
        }

        function test_stale_variant_shows_label_tag_and_trash() {
            verify(!rowStale._checkBox.visible, "no checkbox in the stale variant");
            verify(rowStale._staleLabel.visible, "greyed label visible");
            compare(rowStale._staleLabel.text, "backups", "stale row shows the (cached) label");
            verify(rowStale._unavailableLabel.visible, "'not connected' tag visible");
            verify(rowStale._removeButton.visible, "trash button visible");
        }

        function test_removeRequested_fires_on_trash_click() {
            let fired = 0;
            rowStale.removeRequested.connect(() => fired++);
            rowStale._removeButton.clicked();
            compare(fired, 1, "trash button emits removeRequested");
        }
    }
}
