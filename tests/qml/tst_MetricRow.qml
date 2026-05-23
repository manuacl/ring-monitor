import QtQuick
import QtQuick.Controls
import QtTest
import "../../contents/ui" as Ui

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
    }
}
