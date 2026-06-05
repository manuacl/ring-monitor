import QtQuick
import QtTest
import "../../contents/ui/core" as Ui

// Color-map staging tests for MetricsBody.qml (issue #134) — sibling of
// tst_MetricsBodyLabelCache.qml (#132), same seam for the per-partition
// color map.
//
// SCENARIO (#134): _refreshColorMap used to prune the cfg-bridged
// partitionColorsJson from housekeeping paths (Component.onCompleted,
// onDiskPartitionsChanged). Opening the dialog could (1) dirty the KCM
// with zero user action when a gone partition's color was pruned, and
// (2) at Component.onCompleted diskPartitions is still [] (discovery is
// async), so the keep-set lacked its discovered half and a saved color
// for a discovered-but-unreferenced partition was dropped before
// discovery could vouch for it. The prune now lands in _stagedColorsJson,
// is gated on partitionsReady, and is flushed to the cfg property only
// by a user-gesture setter.

Item {
    id: root
    width: 400
    height: 600

    QtObject {
        id: fakeTheme
        property real unit: 18
        property real smallSpacing: 4
        property real iconSize: 16
        property color highlightColor: "#3daee9"
        property color backgroundColor: "#1e1e1e"
    }

    Ui.MetricsBody {
        id: body
        anchors.fill: parent
        theme: fakeTheme
    }

    TestCase {
        name: "MetricsBodyColorMap"
        when: windowShown

        function init() {
            body.partitionsReady = false;
            body.enabledMetricsCsv = "cpu,ram";
            body.partitionLabelsJson = "";
            body.enabledPartitionsCsv = "";
            body.partitionOrderCsv = "";
            body.partitionOptOutCsv = "";
            body.partitionColorsJson = "";
            body.removablePartitions = [];
            body.diskPartitions = [];
            body.defaultPartitionIds = [];
            wait(20);
        }

        function test_SCENARIO_color_survives_dialog_open_before_discovery() {
            // Saved color for a discovered-but-unreferenced partition (the
            // picker allows coloring any discovered partition before it
            // reaches partitionOrder). Dialog opens while diskPartitions is
            // still [] — the prune must NOT run with the half-empty keep-set.
            body.partitionColorsJson = '{"u-x":"#ff0000"}';
            body.enabledPartitionsCsv = "u-a";
            body.partitionOrderCsv = "u-a";
            wait(20);
            compare(body.partitionColorsJson, '{"u-x":"#ff0000"}', "no prune before discovery settles");
            // Discovery lands and vouches for u-x.
            body.diskPartitions = [{ id: "u-a", label: "root" }, { id: "u-x", label: "games" }];
            body.partitionsReady = true;
            wait(20);
            compare(body.partitionColorsJson, '{"u-x":"#ff0000"}', "discovery must not write the cfg-bridged map");
            compare(body.partitionColor("u-x"), "#ff0000", "saved color survives discovery");
            // A user gesture flushes — u-x is discovered, so its color is kept.
            body.setPartitionEnabled("u-a", true);
            compare(JSON.parse(body.partitionColorsJson)["u-x"], "#ff0000", "flush keeps the discovered partition's color");
        }

        function test_SCENARIO_gone_color_pruned_in_staged_not_cfg() {
            // Saved color whose partition is gone (unplugged, unreferenced):
            // dialog open + settled discovery must prune it from the staged
            // copy ONLY — writing cfg would dirty the KCM with no user action.
            body.partitionColorsJson = '{"u-gone":"#00ff00"}';
            body.enabledPartitionsCsv = "u-a";
            body.partitionsReady = true;
            body.diskPartitions = [{ id: "u-a", label: "root" }];
            wait(20);
            compare(body.partitionColorsJson, '{"u-gone":"#00ff00"}', "prune must not touch the cfg-bridged map (no user action)");
            compare(body.partitionColor("u-gone"), "", "staged copy pruned the gone partition");
            // One real user gesture → page legitimately dirty → prune persists.
            body.setPartitionEnabled("u-a", true);
            verify(JSON.parse(body.partitionColorsJson)["u-gone"] === undefined, "user gesture flushes the staged prune");
        }

        function test_referenced_but_unplugged_color_survives_flush() {
            // The referenced half of the keep-set: a configured partition that
            // is currently unplugged keeps its color so a replug restores it.
            body.partitionColorsJson = '{"u-usb":"#0000ff"}';
            body.enabledPartitionsCsv = "u-a,u-usb";
            body.partitionsReady = true;
            body.diskPartitions = [{ id: "u-a", label: "root" }];
            wait(20);
            body.setEnabled("ram", false);
            compare(JSON.parse(body.partitionColorsJson)["u-usb"], "#0000ff", "referenced color kept through a gesture flush");
        }

        function test_set_and_clear_color_write_cfg_immediately() {
            // The color setters ARE user gestures — they flush to the
            // cfg-bridged property right away, no second gesture needed.
            body.partitionsReady = true;
            body.diskPartitions = [{ id: "u-a", label: "root" }];
            wait(20);
            body.setPartitionColor("u-a", "#ff8800");
            compare(JSON.parse(body.partitionColorsJson)["u-a"], "#ff8800", "setPartitionColor flushes to cfg");
            body.clearPartitionColor("u-a");
            verify(JSON.parse(body.partitionColorsJson || "{}")["u-a"] === undefined, "clearPartitionColor flushes the removal");
        }

        function test_external_cfg_write_resyncs_staged_copy() {
            // KCM "Defaults" / config reload reassigns the cfg-bridged
            // property; the staged copy must follow.
            body.partitionColorsJson = '{"u-a":"#ff0000"}';
            compare(body.partitionColor("u-a"), "#ff0000", "staged copy follows the external write");
            body.partitionColorsJson = "";
            compare(body.partitionColor("u-a"), "", "staged copy resynced on external reset");
        }
    }
}
