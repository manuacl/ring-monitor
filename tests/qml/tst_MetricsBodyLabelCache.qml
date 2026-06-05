import QtQuick
import QtTest
import "../../contents/ui/core" as Ui

// Label-cache staging tests for MetricsBody.qml (issue #132) — split from
// tst_MetricsBody.qml, which sits at the 500-line cap.
//
// SCENARIO (#132): opening the config dialog fires the backend's async
// partition discovery, whose label merge used to write straight into the
// cfg-bridged partitionLabelsJson — dirtying the KCM ("Apply settings?")
// with zero user action whenever the saved cache was missing an entry for
// a referenced partition. The merge now lands in the _stagedLabelsJson
// display copy and is flushed to the cfg property only by a user-gesture
// setter (the page is legitimately dirty there).

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
        name: "MetricsBodyLabelCache"
        when: windowShown

        function init() {
            body.partitionsReady = true;
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

        function test_SCENARIO_discovery_grows_cache_without_dirtying_cfg() {
            // Saved cache knows 1 of the 2 referenced partitions (config was
            // edited outside the dialog / instance swap). Discovery must stage
            // the missing label, NOT touch the cfg-bridged property.
            body.partitionLabelsJson = '{"u-a":"sync"}';
            body.enabledPartitionsCsv = "u-a,u-b";
            body.partitionOrderCsv = "u-a,u-b";
            body.diskPartitions = [{ id: "u-a", label: "sync" }, { id: "u-b", label: "bazzite" }];
            wait(20);
            compare(body.partitionLabelsJson, '{"u-a":"sync"}', "discovery merge must not write the cfg-bridged cache (no user action)");
            compare(JSON.parse(body._stagedLabelsJson)["u-b"], "bazzite", "merged label staged for display");
        }

        function test_SCENARIO_first_user_gesture_flushes_staged_labels() {
            body.partitionLabelsJson = '{"u-a":"sync"}';
            body.enabledPartitionsCsv = "u-a,u-b";
            body.partitionOrderCsv = "u-a,u-b";
            body.diskPartitions = [{ id: "u-a", label: "sync" }, { id: "u-b", label: "bazzite" }, { id: "u-c", label: "photos" }];
            wait(20);
            compare(body.partitionLabelsJson, '{"u-a":"sync"}');
            // One real user toggle → page legitimately dirty → staged flushed.
            body.setPartitionEnabled("u-c", true);
            const saved = JSON.parse(body.partitionLabelsJson);
            compare(saved["u-b"], "bazzite", "staged label flushed on user gesture");
            compare(saved["u-c"], "photos", "newly-toggled partition cached too");
        }

        function test_stale_row_label_comes_from_staged_cache() {
            // A partition discovered this session then unplugged BEFORE any
            // user gesture still shows its friendly name (read from staged).
            body.partitionLabelsJson = "";
            body.enabledPartitionsCsv = "u-a,u-usb";
            body.diskPartitions = [{ id: "u-a", label: "root" }, { id: "u-usb", label: "backups" }];
            wait(20);
            body.diskPartitions = [{ id: "u-a", label: "root" }]; // unplug
            wait(20);
            compare(body.partitionLabelsJson, "", "still no cfg write");
            compare(body.stalePartitionList.length, 1);
            compare(body.stalePartitionList[0].label, "backups", "stale row reads the staged cache");
        }

        function test_default_seeding_is_not_a_user_gesture() {
            // _seedDefaultIfEmpty writes enabledPartitionsCsv programmatically;
            // it must not flush the staged cache into the cfg property.
            body.partitionLabelsJson = "";
            body.diskPartitions = [{ id: "u-home", label: "home" }];
            body.defaultPartitionIds = ["u-home"];
            wait(20);
            verify(body.isPartitionEnabled("u-home"), "default seeded");
            compare(body.partitionLabelsJson, "", "seeding must not flush the label cache");
        }

        function test_external_cfg_write_resyncs_staged_copy() {
            // KCM "Defaults" / config reload reassigns the cfg-bridged property;
            // the staged copy must follow so the display reflects the reset.
            body.partitionLabelsJson = '{"u-a":"sync"}';
            compare(body._stagedLabelsJson, '{"u-a":"sync"}');
            body.partitionLabelsJson = "";
            compare(body._stagedLabelsJson, "", "staged copy resynced on external write");
        }
    }
}
