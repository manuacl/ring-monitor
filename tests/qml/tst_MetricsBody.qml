import QtQuick
import QtTest
import "../../contents/ui/core" as Ui

// Tests for MetricsBody.qml — covers:
//   - cfg_* alias surface: metricOrderCsv, enabledMetricsCsv, showCpuCores
//     are plain read/write properties (the wrapper aliases cfg_X to them)
//   - loadOrder rebuilds the internal orderModel from metricOrderCsv
//   - commitOrder serialises orderModel back to metricOrderCsv
//   - isEnabled / setEnabled round-trip enabledMetricsCsv correctly
//
// MetricsBody is independent of Plasma — it only uses QtQuick.Controls,
// Kirigami, and the pure JS modules. No org.kde.plasma.* imports here,
// so the test runs cleanly under qmltestrunner in CI.

Item {
    id: root
    width: 400
    height: 600

    // A minimal fake theme to satisfy MetricsBody's `theme.X` reads.
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
        name: "MetricsBody"
        when: windowShown

        function init() {
            body.metricOrderCsv = "cpu,cpuTemp,ram,swap,gpu,gpuTemp,disk";
            body.enabledMetricsCsv = "cpu,ram";
            body.enabledPartitionsCsv = "";
            body.partitionOrderCsv = "";
            body.partitionOptOutCsv = "";
            body.partitionColorsJson = "";
            body.removablePartitions = [];
            body.diskPartitions = [];
            body.defaultPartitionIds = [];
            body.showCpuCores = false;
            body.mergeCpuTemp = false;
            body.mergeGpuTemp = false;
            body.tempUnit = "auto";
            body.availableMetrics = null;
            wait(20);
        }

        // ── loadOrder: CSV → orderModel ───────────────────────────────
        function test_loadOrder_populates_model_from_csv() {
            // 7 catalog ids (mergeWithCatalog appends any missing).
            compare(body._orderModel.count, 7);
            compare(body._orderModel.get(0).metricId, "cpu");
            compare(body._orderModel.get(6).metricId, "disk");
        }

        function test_metricOrderCsv_change_reloads_model_and_appends_missing() {
            // User CSV is partial (pre-0.4 install) — mergeWithCatalog
            // tacks the missing ids onto the end so the config list
            // shows every available metric.
            body.metricOrderCsv = "ram,gpu,cpu";
            wait(20);
            compare(body._orderModel.count, 7);
            compare(body._orderModel.get(0).metricId, "ram");
            compare(body._orderModel.get(1).metricId, "gpu");
            compare(body._orderModel.get(2).metricId, "cpu");
            // Order of appended ids is the catalog canonical sequence.
            compare(body._orderModel.get(3).metricId, "cpuTemp");
        }

        // ── currentOrder + commitOrder: roundtrip ─────────────────────
        function test_currentOrder_reads_model() {
            const order = body.currentOrder();
            compare(order, ["cpu", "cpuTemp", "ram", "swap", "gpu", "gpuTemp", "disk"]);
        }

        function test_commitOrder_writes_back_to_csv() {
            body._orderModel.clear();
            const fresh = ["gpu", "ram", "cpu"];
            for (let i = 0; i < fresh.length; i++)
                body._orderModel.append({
                    metricId: fresh[i]
                });
            body.commitOrder();
            compare(body.metricOrderCsv, "gpu,ram,cpu");
        }

        // ── isEnabled / setEnabled: enabledMetricsCsv roundtrip ──────
        function test_isEnabled_reflects_csv() {
            compare(body.isEnabled("cpu"), true);
            compare(body.isEnabled("ram"), true);
            compare(body.isEnabled("disk"), false);
        }

        function test_setEnabled_true_appends_to_csv() {
            body.setEnabled("disk", true);
            verify(body.enabledMetricsCsv.split(",").indexOf("disk") !== -1);
        }

        function test_setEnabled_false_removes_from_csv() {
            body.setEnabled("cpu", false);
            verify(body.enabledMetricsCsv.split(",").indexOf("cpu") === -1);
        }

        // ── Property surface (catches typos in the bridge spec) ──────
        function test_all_bridged_properties_present() {
            const keys = ["metricOrderCsv", "enabledMetricsCsv", "enabledPartitionsCsv", "partitionOrderCsv", "showCpuCores", "mergeCpuTemp", "mergeGpuTemp", "tempUnit"];
            for (const k of keys) {
                verify(k in body, "MetricsBody must expose property " + k);
            }
        }

        // ── Availability: isMetricAvailable drives the row grey-out ──
        function test_isMetricAvailable_null_means_all_available() {
            // Default: backend hasn't reported (or host predates the surface)
            // → every metric is enable-able.
            body.availableMetrics = null;
            verify(body.isMetricAvailable("gpu"));
            verify(body.isMetricAvailable("swap"));
        }

        function test_isMetricAvailable_reflects_injected_list() {
            body.availableMetrics = ["cpu", "ram", "disk"];
            verify(body.isMetricAvailable("cpu"));
            verify(!body.isMetricAvailable("gpu"), "gpu not in the list → unavailable");
            verify(!body.isMetricAvailable("swap"), "swap not in the list → unavailable");
        }

        function test_isMetricAvailable_empty_list_means_none() {
            body.availableMetrics = [];
            verify(!body.isMetricAvailable("cpu"));
        }

        // ── Disk partition picker: enabledPartitionsCsv roundtrip ────
        function test_isPartitionEnabled_reflects_csv() {
            body.enabledPartitionsCsv = "uuid-a,uuid-c";
            verify(body.isPartitionEnabled("uuid-a"));
            verify(!body.isPartitionEnabled("uuid-b"));
            verify(body.isPartitionEnabled("uuid-c"));
        }

        function test_setPartitionEnabled_toggles_csv() {
            body.setPartitionEnabled("uuid-b", true);
            verify(body.enabledPartitionsCsv.split(",").indexOf("uuid-b") !== -1);
            body.setPartitionEnabled("uuid-b", false);
            verify(body.enabledPartitionsCsv.split(",").indexOf("uuid-b") === -1);
        }

        function test_diskPartitions_property_accepts_injected_list() {
            // The platform wrapper injects [{id,label}]; the picker renders
            // one row each. We can't easily count delegates from here, but
            // the property must round-trip so the binding reaches the list.
            body.diskPartitions = [
                {
                    id: "uuid-a",
                    label: "root"
                },
                {
                    id: "uuid-b",
                    label: "photos"
                }
            ];
            compare(body.diskPartitions.length, 2);
            compare(body.diskPartitions[0].label, "root");
        }

        // ── Partition order model: default alphabetical + reorder commit ──
        function test_partition_order_model_defaults_alphabetical() {
            body.diskPartitions = [
                {
                    id: "u-sync",
                    label: "sync"
                },
                {
                    id: "u-root",
                    label: "root"
                },
                {
                    id: "u-ph",
                    label: "photos"
                }
            ];
            body.partitionOrderCsv = "";
            wait(20);
            compare(body._partitionOrderModel.count, 3);
            // Alphabetical by label: photos, root, sync.
            compare(body._partitionOrderModel.get(0).partId, "u-ph");
            compare(body._partitionOrderModel.get(1).partId, "u-root");
            compare(body._partitionOrderModel.get(2).partId, "u-sync");
        }

        function test_partition_order_model_respects_saved_csv() {
            body.diskPartitions = [
                {
                    id: "u-sync",
                    label: "sync"
                },
                {
                    id: "u-root",
                    label: "root"
                },
                {
                    id: "u-ph",
                    label: "photos"
                }
            ];
            body.partitionOrderCsv = "u-sync,u-root,u-ph";
            wait(20);
            compare(body._partitionOrderModel.get(0).partId, "u-sync");
            compare(body._partitionOrderModel.get(1).partId, "u-root");
        }

        function test_empty_selection_seeds_the_default() {
            // SCENARIO (review #5): with no partition selected, the widget
            // renders the default ($HOME) ring — the picker must reflect it as
            // a checked row rather than showing everything unchecked. Setting
            // a non-empty default while the CSV is empty seeds it.
            body.enabledPartitionsCsv = "";
            body.diskPartitions = [
                {
                    id: "u-root",
                    label: "root"
                },
                {
                    id: "u-ph",
                    label: "photos"
                }
            ];
            body.defaultPartitionIds = ["u-root"];
            wait(20);
            verify(body.isPartitionEnabled("u-root"), "the default partition must be seeded as enabled");
        }

        function test_empty_default_does_not_seed() {
            // Plasma default is [] (aggregate) → nothing seeded, picker stays
            // unchecked, the disk ring stays the aggregate gauge.
            body.enabledPartitionsCsv = "";
            body.diskPartitions = [
                {
                    id: "u-root",
                    label: "root"
                }
            ];
            body.defaultPartitionIds = [];
            wait(20);
            compare(body.enabledPartitionsCsv, "");
        }

        function test_commitPartitionOrder_writes_csv_in_model_order() {
            body.diskPartitions = [
                {
                    id: "u-root",
                    label: "root"
                },
                {
                    id: "u-ph",
                    label: "photos"
                }
            ];
            body.partitionOrderCsv = "";
            wait(20);
            body.commitPartitionOrder();
            // Model is alphabetical (photos, root) → CSV reflects it.
            compare(body.partitionOrderCsv, "u-ph,u-root");
        }

        // ── Stale (unplugged) partitions (#49) ──────────────────────
        // partitionsReady is the wrapper-injected "discovery settled" gate
        // (DiskPartitions.ready on Plasma, always true on standalone).
        function test_stale_list_suppressed_until_ready() {
            // Until the wrapper confirms discovery settled, a not-yet-enumerated
            // partition must NOT surface as stale (the trash action is destructive).
            body.partitionsReady = false;
            body.diskPartitions = [
                {
                    id: "u-root",
                    label: "root"
                }
            ];
            body.enabledPartitionsCsv = "u-root,u-usb";
            compare(body.stalePartitionList.length, 0, "no stale rows while discovery is not ready");
            body.partitionsReady = true;
            compare(body.stalePartitionList.length, 1, "u-usb surfaces once ready");
            compare(body.stalePartitionList[0].id, "u-usb");
        }

        function test_stale_list_suppressed_when_no_partitions_discovered() {
            // Empty diskPartitions = nothing discovered; can't conclude stale
            // even when ready.
            body.partitionsReady = true;
            body.diskPartitions = [];
            body.enabledPartitionsCsv = "u-root,u-usb";
            compare(body.stalePartitionList.length, 0);
        }

        function test_unplugged_enabled_partition_surfaces_with_cached_label() {
            // SCENARIO (#49): u-usb is selected and discovered (label cached),
            // then unplugged → it must surface as a stale row keeping the
            // friendly name, not vanish silently.
            body.partitionsReady = true;
            body.enabledPartitionsCsv = "u-usb,u-root";
            body.diskPartitions = [
                {
                    id: "u-usb",
                    label: "backups"
                },
                {
                    id: "u-root",
                    label: "root"
                }
            ];
            // Both discovered → nothing stale.
            compare(body.stalePartitionList.length, 0);

            // Unplug u-usb.
            body.diskPartitions = [
                {
                    id: "u-root",
                    label: "root"
                }
            ];
            compare(body.stalePartitionList.length, 1);
            compare(body.stalePartitionList[0].id, "u-usb");
            compare(body.stalePartitionList[0].label, "backups", "stale row keeps the last-known label from the cache");
        }

        // ── Checkbox reflects ring visibility (auto-show + opt-out) ──
        // A mounted removable is auto-shown → its box reads CHECKED even though
        // it isn't in the manual selection; unchecking opts it out (and keeps it
        // out of the manual list), re-checking resumes auto-show; a fixed disk
        // toggles the manual selection only.
        function test_removable_is_checked_by_default_auto_show() {
            body.removablePartitions = [{ id: "u-usb", label: "MYUSB" }];
            body.enabledPartitionsCsv = "u-root";
            verify(body.isPartitionEnabled("u-usb"), "auto-shown removable → box checked");
            verify(body.isPartitionEnabled("u-root"), "manually-enabled fixed disk → box checked");
        }

        function test_uncheck_removable_opts_it_out_and_stays_out_of_manual() {
            body.removablePartitions = [{ id: "u-usb", label: "MYUSB" }];
            body.enabledPartitionsCsv = "u-root";
            body.setPartitionEnabled("u-usb", false);
            verify(!body.isPartitionEnabled("u-usb"), "unchecked removable → box unchecked");
            verify(body.partitionOptOutCsv.split(",").indexOf("u-usb") !== -1, "u-usb added to the opt-out list");
            verify(body.enabledPartitionsCsv.split(",").indexOf("u-usb") === -1, "a removable is never written into the manual selection");
            body.setPartitionEnabled("u-usb", true);
            verify(body.isPartitionEnabled("u-usb"), "re-checked removable → box checked");
            verify(body.partitionOptOutCsv.split(",").indexOf("u-usb") === -1, "u-usb removed from the opt-out list");
        }

        function test_fixed_disk_toggle_uses_manual_selection_not_optout() {
            body.removablePartitions = [];
            body.enabledPartitionsCsv = "";
            body.setPartitionEnabled("u-root", true);
            verify(body.isPartitionEnabled("u-root"));
            verify(body.enabledPartitionsCsv.split(",").indexOf("u-root") !== -1, "fixed disk → manual selection");
            compare(body.partitionOptOutCsv, "", "fixed disk toggle must not touch the opt-out list");
            body.setPartitionEnabled("u-root", false);
            verify(!body.isPartitionEnabled("u-root"));
        }

        function test_SCENARIO_check_a_partition_then_unplug_greys_it() {
            // A selected partition that drops out of the mounted set (what
            // MetricsBackend.mountedAvailablePartitions does live on unmount)
            // must surface as a greyed stale row, not vanish.
            body.partitionsReady = true;
            body.enabledPartitionsCsv = "u-root";
            body.diskPartitions = [{ id: "u-root", label: "root" }, { id: "u-usb", label: "MYUSB" }];
            wait(20);
            body.setPartitionEnabled("u-usb", true);
            verify(body.isPartitionEnabled("u-usb"), "checking persists to enabledPartitions");
            compare(body.stalePartitionList.length, 0, "still mounted → not stale");
            body.diskPartitions = [{ id: "u-root", label: "root" }]; // unplug
            wait(20);
            compare(body.stalePartitionList.length, 1, "checked-then-unplugged → greyed stale row");
            compare(body.stalePartitionList[0].id, "u-usb");
        }

        function test_SCENARIO_unchecked_autoshown_removable_just_disappears() {
            // Counterpart: a removable that was only auto-shown (never checked)
            // is NOT in enabledPartitions, so on unplug it correctly vanishes
            // with no stale row (nothing to clean up). This is what the live
            // test actually exercised — hence "no greyed row" was correct there.
            body.partitionsReady = true;
            body.enabledPartitionsCsv = "u-root"; // u-usb deliberately NOT checked
            body.diskPartitions = [
                { id: "u-root", label: "root" },
                { id: "u-usb", label: "MYUSB" }
            ];
            wait(20);
            compare(body.stalePartitionList.length, 0);
            body.diskPartitions = [{ id: "u-root", label: "root" }]; // unplug
            wait(20);
            compare(body.stalePartitionList.length, 0, "an unchecked auto-shown removable leaves no stale row");
        }

        function test_removeStalePartition_clears_csvs_and_cache() {
            body.partitionsReady = true;
            body.enabledPartitionsCsv = "u-usb,u-root";
            body.partitionOrderCsv = "u-usb,u-root";
            // Per-partition color round-trip (issue #67) + cleared on removal.
            compare(body.partitionColor("u-usb"), "", "no override by default");
            body.setPartitionColor("u-usb", "#ff0000");
            compare(body.partitionColor("u-usb"), "#ff0000", "setPartitionColor round-trips");
            body.diskPartitions = [
                {
                    id: "u-usb",
                    label: "backups"
                },
                {
                    id: "u-root",
                    label: "root"
                }
            ];
            body.diskPartitions = [
                {
                    id: "u-root",
                    label: "root"
                }
            ];
            verify(body.stalePartitionList.length === 1, "u-usb must be stale before removal");

            body.removeStalePartition("u-usb");
            verify(body.enabledPartitionsCsv.split(",").indexOf("u-usb") === -1, "removed from enabledPartitions");
            verify(body.partitionOrderCsv.split(",").indexOf("u-usb") === -1, "removed from partitionOrder");
            compare(body.stalePartitionList.length, 0, "no longer surfaced after removal");
            verify(JSON.parse(body.partitionLabelsJson || "{}")["u-usb"] === undefined, "label cache entry pruned");
            compare(body.partitionColor("u-usb"), "", "custom color forgotten on removal → back to the general color");
        }

        function test_label_cache_not_written_on_open_for_empty_default() {
            // _refreshLabelCache must treat "" and "{}" as equal so merely
            // opening the dialog (no user action) doesn't dirty partitionLabels.
            body.partitionLabelsJson = "";
            body.enabledPartitionsCsv = "";
            body.partitionOrderCsv = "";
            body.diskPartitions = [
                {
                    id: "u-root",
                    label: "root"
                }
            ];
            wait(20);
            compare(body.partitionLabelsJson, "", "empty cache must stay \"\" — no spurious config write");
        }

        // ── Temperature unit: property → which radio is checked ─────
        function test_tempUnit_default_is_auto_and_drives_radio() {
            // Make sure the row is visible (only shown when at least
            // one temperature metric is enabled) so the radios are
            // realised by the Loader.
            body.enabledMetricsCsv = "cpu,cpuTemp";
            wait(20);
            compare(body.tempUnit, "auto");
            verify(body._tempUnitAuto.checked);
            verify(!body._tempUnitCelsius.checked);
            verify(!body._tempUnitFahrenheit.checked);
        }

        function test_tempUnit_celsius_swaps_the_checked_radio() {
            body.enabledMetricsCsv = "cpu,cpuTemp";
            wait(20);
            body.tempUnit = "celsius";
            verify(!body._tempUnitAuto.checked);
            verify(body._tempUnitCelsius.checked);
            verify(!body._tempUnitFahrenheit.checked);
        }

        function test_tempUnit_fahrenheit_swaps_the_checked_radio() {
            body.enabledMetricsCsv = "cpu,cpuTemp";
            wait(20);
            body.tempUnit = "fahrenheit";
            verify(!body._tempUnitAuto.checked);
            verify(!body._tempUnitCelsius.checked);
            verify(body._tempUnitFahrenheit.checked);
        }

        // ── Descriptions are present + i18n switched to qsTr() ───────
        function test_metricDescriptions_contain_all_catalog_metrics() {
            const desc = body.metricDescriptions;
            for (const id of ["cpu", "cpuTemp", "ram", "swap", "gpu", "gpuTemp", "disk"]) {
                verify(desc[id], "metricDescriptions must include " + id);
                verify(typeof desc[id] === "string" && desc[id].length > 0, "description for " + id + " must be a non-empty string");
            }
        }
    }
}
