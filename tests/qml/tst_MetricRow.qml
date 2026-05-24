import QtQuick
import QtQuick.Controls
import QtTest
import "../../contents/ui/core" as Ui

// Tests for MetricRow.qml — asserts that the label / description /
// checked state actually render correctly for each known metric ID.
//
// This catches "labels are empty" regressions before the user does.

Item {
    id: root
    width: 600
    height: 200

    Ui.MetricRow {
        id: row
        anchors.fill: parent
    }

    SignalSpy {
        id: toggleSpy
        target: row
        signalName: "toggled"
    }

    TestCase {
        name: "MetricRow"
        when: windowShown

        function init() {
            // Reset for each test.
            row.metricId = "";
            row.enabled = false;
            row.description = "";
            toggleSpy.clear();
        }

        // ── Label rendering ────────────────────────────────────────
        function test_label_cpu() {
            row.metricId = "cpu";
            compare(row._labelText, "CPU");
        }
        function test_label_ram() {
            row.metricId = "ram";
            compare(row._labelText, "RAM");
        }
        function test_label_swap() {
            row.metricId = "swap";
            compare(row._labelText, "SWAP");
        }
        function test_label_gpu() {
            row.metricId = "gpu";
            compare(row._labelText, "GPU");
        }
        function test_label_disk() {
            row.metricId = "disk";
            compare(row._labelText, "DISK");
        }
        function test_label_empty_id() {
            row.metricId = "";
            compare(row._labelText, "");
        }
        function test_label_unknown_id_falls_back_to_uppercase() {
            // Catalog.labelFor's fallback uppercases the raw id —
            // forces a visible string instead of a blank checkbox.
            row.metricId = "nonexistent";
            compare(row._labelText, "NONEXISTENT");
        }

        // ── Description rendering ──────────────────────────────────
        function test_description_passthrough() {
            row.description = "Some text";
            compare(row._descriptionText, "Some text");
        }
        function test_description_empty_default() {
            compare(row._descriptionText, "");
        }

        // ── Checked state ──────────────────────────────────────────
        function test_checked_reflects_enabled_true() {
            row.enabled = true;
            compare(row._checked, true);
        }
        function test_checked_reflects_enabled_false() {
            row.enabled = false;
            compare(row._checked, false);
        }

        // ── Click → toggled signal ─────────────────────────────────
        function test_click_unchecked_emits_toggled_true() {
            row.metricId = "cpu";
            row.enabled = false;
            mouseClick(row._checkBox);
            compare(toggleSpy.count, 1);
            compare(toggleSpy.signalArguments[0][0], true, "click on an unchecked box should emit toggled(true)");
        }
        function test_click_checked_emits_toggled_false() {
            row.metricId = "cpu";
            row.enabled = true;
            mouseClick(row._checkBox);
            compare(toggleSpy.count, 1);
            compare(toggleSpy.signalArguments[0][0], false, "click on a checked box should emit toggled(false)");
        }

        // ── Disabled-state dimming ─────────────────────────────────
        // The row reads as inactive when not selected — but the checkbox
        // must stay at full opacity so the user can still clearly see
        // (and re-enable) it.
        function test_disabled_dims_description_label() {
            row.metricId = "cpu";
            row.description = "Some description";
            row.enabled = true;
            const enabledOpacity = row._descriptionLabel.opacity;
            row.enabled = false;
            verify(row._descriptionLabel.opacity < enabledOpacity, "description should be more dimmed when disabled, " + "enabled=" + enabledOpacity + " disabled=" + row._descriptionLabel.opacity);
        }
        function test_disabled_does_not_dim_checkbox() {
            row.metricId = "cpu";
            row.enabled = true;
            const enabledOpacity = row._checkBox.opacity;
            row.enabled = false;
            compare(row._checkBox.opacity, enabledOpacity, "checkbox opacity must not change with enabled state");
        }

        // ── Extra content (optional sub-row under the main row) ────
        function test_extraContent_null_loader_inactive() {
            row.extraContent = null;
            compare(row._extraLoader.active, false);
            compare(row._extraLoader.visible, false);
        }
        function test_extraContent_set_loader_active_and_visible() {
            row.extraContent = trivialExtra;
            compare(row._extraLoader.active, true);
            compare(row._extraLoader.visible, true);
        }
        function test_extraContent_grows_implicit_height() {
            row.extraContent = null;
            wait(20);
            const baseHeight = row.implicitHeight;
            row.extraContent = trivialExtra;
            wait(20);
            verify(row.implicitHeight > baseHeight, "implicitHeight should grow when extraContent is set, " + "got base=" + baseHeight + " with-extra=" + row.implicitHeight);
        }

        // ── Disabled cascades into extraContent ───────────────────
        // When the master row is disabled, child controls (e.g. the
        // CPU-cores sub-toggle) must become non-interactive. QML
        // cascades `enabled` to descendants — these tests pin that.
        function test_disabled_master_disables_extraLoader() {
            row.extraContent = checkboxExtra;
            row.enabled = false;
            wait(20);
            compare(row._extraLoader.enabled, false);
        }
        function test_disabled_master_disables_child_checkbox() {
            row.extraContent = checkboxExtra;
            row.enabled = false;
            wait(20);
            verify(row._extraLoader.item, "extra item should be loaded");
            compare(row._extraLoader.item.enabled, false, "child CheckBox should inherit enabled=false");
        }
        function test_enabled_master_keeps_child_checkbox_interactive() {
            row.extraContent = checkboxExtra;
            row.enabled = true;
            wait(20);
            verify(row._extraLoader.item);
            compare(row._extraLoader.item.enabled, true);
        }
    }

    // Stub children for the extraContent tests above.
    Component {
        id: trivialExtra
        Rectangle {
            implicitWidth: 100
            implicitHeight: 24
            color: "transparent"
        }
    }
    Component {
        id: checkboxExtra
        CheckBox {
            text: "child option"
        }
    }
}
