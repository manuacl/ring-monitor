import QtQuick
import QtTest
import "../../contents/ui/core" as Ui

// Rendering tests for DiskTooltip.qml — the per-disk hover tooltip (#68). The
// string formatting is covered runtime-free in disk-tooltip-model.test.mjs; this
// checks the QML view: the row count tracks `details`, the model is built from
// the pure helper, and sampling stays inert until the disk ring arms it.
Item {
    id: root
    width: 320
    height: 320

    readonly property real giB: 1024 * 1024 * 1024

    Ui.DiskTooltip {
        id: tip
        armed: true
        details: []
        colors: []
    }

    TestCase {
        name: "DiskTooltip"
        when: windowShown

        function init() {
            tip.armed = true;
            tip._show = false;
            tip.details = [];
            tip.colors = [];
        }

        function test_row_count_tracks_details() {
            tip.details = [
                {
                    id: "a",
                    label: "root",
                    mountpoint: "/",
                    fstype: "btrfs",
                    usedPercent: 12,
                    totalBytes: 466 * root.giB,
                    freeBytes: 410 * root.giB,
                    removable: false
                },
                {
                    id: "b",
                    label: "USB",
                    mountpoint: "/run/media/u/USB",
                    fstype: "vfat",
                    usedPercent: 30,
                    totalBytes: 16 * root.giB,
                    freeBytes: 11 * root.giB,
                    removable: true
                }
            ];
            compare(tip._rowCount, 2);
        }

        function test_empty_details_renders_no_rows() {
            tip.details = [];
            compare(tip._rowCount, 0);
        }

        // armed=false (every non-disk ring) keeps sampling inert.
        function test_not_armed_means_not_sampling() {
            tip.armed = false;
            compare(tip.samplingActive, false);
        }

        // _rows is the pure DiskTooltipModel.buildRows output: label kept, the
        // usage line composed, the removable icon chosen.
        function test_rows_built_from_the_pure_model() {
            tip.details = [
                {
                    id: "a",
                    label: "root",
                    mountpoint: "/",
                    fstype: "ext4",
                    usedPercent: 12,
                    totalBytes: 466 * root.giB,
                    freeBytes: 410 * root.giB,
                    removable: false
                }
            ];
            compare(tip._rows.length, 1);
            compare(tip._rows[0].label, "root");
            compare(tip._rows[0].subLabel, "/ · ext4");
            compare(tip._rows[0].usageText, "12% · 56 GiB / 466 GiB");
            compare(tip._rows[0].iconName, "drive-harddisk");
        }

        // ── openRight placement property ───────────────────────────────
        // openRight controls which side of the ring the Window-popup opens toward
        // (left-anchored widget → open right, right-anchored → open left/default).
        // The anchorMarker.x binding (root.openRight ? root.width : 0) is covered
        // by the text guard in tooltip-placement-sync.test.mjs.

        function test_openRight_defaults_to_false() {
            compare(tip.openRight, false);
        }

        function test_openRight_can_be_set_to_true() {
            tip.openRight = true;
            compare(tip.openRight, true);
            tip.openRight = false;   // shared instance — restore default for other tests
        }

        function test_openRight_can_be_set_back_to_false() {
            tip.openRight = true;
            tip.openRight = false;
            compare(tip.openRight, false);
        }
    }
}
