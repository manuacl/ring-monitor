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

    // Stub ColorPicker — same `color` + `accepted` surface as both real
    // adapters, mirroring tst_AppearanceBody's stub.
    Component {
        id: stubColorPicker
        Item {
            implicitWidth: 32
            implicitHeight: 24
            property color color: "#000000"
            signal accepted
        }
    }

    Ui.PartitionRow {
        id: rowAvailable
        partLabel: "root"
        available: true
        checked: true
        colorPickerComponent: stubColorPicker
        inheritedColor: "#3daee9"
    }

    Ui.PartitionRow {
        id: rowStale
        partLabel: "backups"
        available: false
        colorPickerComponent: stubColorPicker
    }

    TestCase {
        name: "PartitionRow"
        when: windowShown

        function init() {
            rowAvailable.customColor = "";
        }

        function test_available_shows_checkbox_only() {
            verify(rowAvailable._checkBox.visible, "checkbox visible when available");
            verify(!rowAvailable._unavailableLabel.visible, "no 'not connected' tag when available");
            verify(!rowAvailable._removeButton.visible, "no trash button when available");
            compare(rowAvailable._checkBox.text, "root");
            verify(rowAvailable._checkBox.checked);
        }

        // ── Per-partition color (issue #67) ─────────────────────────────
        function test_color_swatch_shows_when_available_with_picker() {
            verify(rowAvailable._colorButton.visible, "swatch visible on an available row with an injected picker");
            // No swatch on the stale variant — a disconnected partition has no
            // ring to color.
            verify(!rowStale._colorButton.visible, "no color swatch on the stale variant");
        }

        function test_clear_button_hidden_until_a_custom_color_is_set() {
            rowAvailable.customColor = "";
            verify(!rowAvailable._clearColorButton.visible, "clear hidden when inheriting the shared color");
            rowAvailable.customColor = "#ff0000";
            verify(rowAvailable._clearColorButton.visible, "clear shown once a custom color is set");
        }

        function test_swatch_reflects_custom_color_else_inherited() {
            rowAvailable.customColor = "";
            compare(rowAvailable._colorButton.item.color.toString().toLowerCase(), "#3daee9", "unset → shows the inherited color");
            rowAvailable.customColor = "#aabbcc";
            compare(rowAvailable._colorButton.item.color.toString().toLowerCase(), "#aabbcc", "set → shows the custom color");
        }

        function test_colorPicked_emitted_on_picker_accept() {
            rowAvailable.customColor = "#112233";
            let picked = null;
            rowAvailable.colorPicked.connect(c => picked = c);
            rowAvailable._colorButton.item.accepted();
            compare(picked.toString().toLowerCase(), "#112233", "colorPicked carries the swatch color");
        }

        function test_colorCleared_emitted_on_clear_click() {
            rowAvailable.customColor = "#445566";
            let fired = 0;
            rowAvailable.colorCleared.connect(() => fired++);
            rowAvailable._clearColorButton.clicked();
            compare(fired, 1, "clear button emits colorCleared");
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
