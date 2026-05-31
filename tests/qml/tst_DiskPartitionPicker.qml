import QtQuick
import QtTest
import "../../contents/ui/core" as Ui

// Tests for DiskPartitionPicker.qml — the disk-partition picker view extracted
// from MetricsBody. It holds no state: it renders the controller's partition
// model and forwards every action back to the controller. So the test drives a
// REAL MetricsBody as the controller (both are Plasma-free, qmltestrunner-safe)
// and asserts the view wiring: empty-vs-populated visibility, and that the
// per-partition color swatch round-trips through the controller (issue #67).

Item {
    id: root
    width: 400
    height: 400

    QtObject {
        id: fakeTheme
        property real unit: 18
        property real smallSpacing: 4
        property real iconSize: 16
        property color highlightColor: "#3daee9"
        property color backgroundColor: "#1e1e1e"
    }

    Component {
        id: stubColorPicker
        Item {
            implicitWidth: 32
            implicitHeight: 24
            property color color: "#000000"
            signal accepted
        }
    }

    // The controller is a real MetricsBody — the picker delegates to it.
    Ui.MetricsBody {
        id: controller
        theme: fakeTheme
        colorPickerComponent: stubColorPicker
    }

    Ui.DiskPartitionPicker {
        id: picker
        controller: controller
        width: 360
        height: 200
    }

    TestCase {
        name: "DiskPartitionPicker"
        when: windowShown

        function init() {
            controller.enabledPartitionsCsv = "";
            controller.partitionOrderCsv = "";
            controller.partitionOptOutCsv = "";
            controller.partitionColorsJson = "";
            controller.removablePartitions = [];
            controller.defaultPartitionIds = [];
            controller.diskPartitions = [];
            controller.partitionsReady = true;
            wait(20);
        }

        function test_empty_shows_hint_and_hides_list() {
            controller.diskPartitions = [];
            wait(20);
            verify(picker._emptyLabel.visible, "the 'No partitions detected' hint shows when nothing is discovered");
            verify(!picker._partitionList.visible, "the draggable list hides when empty");
        }

        function test_populated_shows_list_and_hides_hint() {
            controller.diskPartitions = [{ id: "u-root", label: "root" }, { id: "u-ph", label: "photos" }];
            wait(20);
            verify(picker._partitionList.visible, "the draggable list shows once partitions are discovered");
            verify(!picker._emptyLabel.visible, "the hint hides once partitions exist");
            compare(controller._partitionOrderModel.count, 2, "the picker binds the controller's partition model");
        }

        function test_per_partition_color_round_trips_through_controller() {
            // The swatch's onColorPicked / onColorCleared forward to the
            // controller; assert via the controller's color map (the view's
            // single source of truth). Logic-level coverage is in
            // disk-colors.test.mjs; row rendering is in tst_PartitionRow.
            controller.diskPartitions = [{ id: "u-root", label: "root" }];
            wait(20);
            compare(controller.partitionColor("u-root"), "", "no override by default");
            controller.setPartitionColor("u-root", "#ff8800");
            compare(controller.partitionColor("u-root"), "#ff8800");
            controller.clearPartitionColor("u-root");
            compare(controller.partitionColor("u-root"), "", "cleared → back to the general color");
        }

        // SCENARIO: after picking a color once, clearing the override updated
        // the ring but left the picker SWATCH frozen on the old color. The
        // platform ColorPicker assigns `color = selectedColor` on accept, which
        // clobbered the swatch's imperatively-installed `item.color` binding — so
        // a later external change (the clear button → customColor "") no longer
        // reached the swatch. PartitionRow now drives the swatch via a Binding
        // element that survives the self-assign. This walks the rendered row by
        // objectName (immune to DraggableList's internal delegate structure).
        function test_SCENARIO_swatch_reverts_after_pick_then_clear() {
            controller.diskPartitions = [{ id: "u-root", label: "root" }];
            wait(20);
            const rowItem = findChild(picker, "diskPartitionRow");
            verify(rowItem !== null, "the partition row must render (found by objectName)");
            const swatch = rowItem._colorButton.item;
            verify(swatch !== null, "the color swatch must load");

            // Pick a color: the controller records it AND the real picker
            // self-assigns swatch.color on accept — simulate that clobber here
            // (the test stub doesn't self-assign).
            controller.setPartitionColor("u-root", "#ff8800");
            swatch.color = "#ff8800";
            tryCompare(rowItem, "customColor", "#ff8800", 1000);

            // Clear → the swatch MUST revert to the inherited color despite the
            // earlier self-assign that clobbered the initial binding.
            controller.clearPartitionColor("u-root");
            tryCompare(rowItem, "customColor", "", 1000);
            tryCompare(swatch, "color", fakeTheme.highlightColor, 1000, "swatch reverts to the inherited color after clear");
            verify(!rowItem._clearColorButton.visible, "clear button hides once the override is gone");
        }
    }
}
