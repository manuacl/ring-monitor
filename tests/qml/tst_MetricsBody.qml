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
                    label: "bazzite"
                },
                {
                    id: "uuid-b",
                    label: "photos"
                }
            ];
            compare(body.diskPartitions.length, 2);
            compare(body.diskPartitions[0].label, "bazzite");
        }

        // ── Partition order model: default alphabetical + reorder commit ──
        function test_partition_order_model_defaults_alphabetical() {
            body.diskPartitions = [
                {
                    id: "u-sync",
                    label: "sync"
                },
                {
                    id: "u-baz",
                    label: "bazzite"
                },
                {
                    id: "u-ph",
                    label: "photos"
                }
            ];
            body.partitionOrderCsv = "";
            wait(20);
            compare(body._partitionOrderModel.count, 3);
            // Alphabetical by label: bazzite, photos, sync.
            compare(body._partitionOrderModel.get(0).partId, "u-baz");
            compare(body._partitionOrderModel.get(1).partId, "u-ph");
            compare(body._partitionOrderModel.get(2).partId, "u-sync");
        }

        function test_partition_order_model_respects_saved_csv() {
            body.diskPartitions = [
                {
                    id: "u-sync",
                    label: "sync"
                },
                {
                    id: "u-baz",
                    label: "bazzite"
                },
                {
                    id: "u-ph",
                    label: "photos"
                }
            ];
            body.partitionOrderCsv = "u-sync,u-baz,u-ph";
            wait(20);
            compare(body._partitionOrderModel.get(0).partId, "u-sync");
            compare(body._partitionOrderModel.get(1).partId, "u-baz");
        }

        function test_empty_selection_seeds_the_default() {
            // SCENARIO (review #5): with no partition selected, the widget
            // renders the default ($HOME) ring — the picker must reflect it as
            // a checked row rather than showing everything unchecked. Setting
            // a non-empty default while the CSV is empty seeds it.
            body.enabledPartitionsCsv = "";
            body.diskPartitions = [
                {
                    id: "u-baz",
                    label: "bazzite"
                },
                {
                    id: "u-ph",
                    label: "photos"
                }
            ];
            body.defaultPartitionIds = ["u-baz"];
            wait(20);
            verify(body.isPartitionEnabled("u-baz"), "the default partition must be seeded as enabled");
        }

        function test_empty_default_does_not_seed() {
            // Plasma default is [] (aggregate) → nothing seeded, picker stays
            // unchecked, the disk ring stays the aggregate gauge.
            body.enabledPartitionsCsv = "";
            body.diskPartitions = [
                {
                    id: "u-baz",
                    label: "bazzite"
                }
            ];
            body.defaultPartitionIds = [];
            wait(20);
            compare(body.enabledPartitionsCsv, "");
        }

        function test_commitPartitionOrder_writes_csv_in_model_order() {
            body.diskPartitions = [
                {
                    id: "u-baz",
                    label: "bazzite"
                },
                {
                    id: "u-ph",
                    label: "photos"
                }
            ];
            body.partitionOrderCsv = "";
            wait(20);
            body.commitPartitionOrder();
            // Model is alphabetical (bazzite, photos) → CSV reflects it.
            compare(body.partitionOrderCsv, "u-baz,u-ph");
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
                    id: "u-baz",
                    label: "bazzite"
                }
            ];
            body.enabledPartitionsCsv = "u-baz,u-usb";
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
            body.enabledPartitionsCsv = "u-baz,u-usb";
            compare(body.stalePartitionList.length, 0);
        }

        function test_unplugged_enabled_partition_surfaces_with_cached_label() {
            // SCENARIO (#49): u-usb is selected and discovered (label cached),
            // then unplugged → it must surface as a stale row keeping the
            // friendly name, not vanish silently.
            body.partitionsReady = true;
            body.enabledPartitionsCsv = "u-usb,u-baz";
            body.diskPartitions = [
                {
                    id: "u-usb",
                    label: "backups"
                },
                {
                    id: "u-baz",
                    label: "bazzite"
                }
            ];
            // Both discovered → nothing stale.
            compare(body.stalePartitionList.length, 0);

            // Unplug u-usb.
            body.diskPartitions = [
                {
                    id: "u-baz",
                    label: "bazzite"
                }
            ];
            compare(body.stalePartitionList.length, 1);
            compare(body.stalePartitionList[0].id, "u-usb");
            compare(body.stalePartitionList[0].label, "backups", "stale row keeps the last-known label from the cache");
        }

        function test_SCENARIO_check_an_autoshown_removable_then_unplug_greys_it() {
            // SCENARIO (2026-05-29 live test): a removable is auto-shown (ring
            // visible, picker row UNCHECKED — auto-show never ticks the box).
            // The user CHECKS it in the picker, then unplugs. It must surface
            // as a greyed stale row — NOT silently vanish. Uses the real
            // setPartitionEnabled setter (what the checkbox calls) to be
            // faithful to the live flow, and mutates diskPartitions the way the
            // Plasma backend's mountedAvailablePartitions does on unmount.
            body.partitionsReady = true;
            body.enabledPartitionsCsv = "u-baz"; // a fixed disk already selected
            body.diskPartitions = [
                { id: "u-baz", label: "bazzite" },
                { id: "u-usb", label: "MYUSB" } // removable, mounted + discovered
            ];
            wait(20);
            // The auto-shown removable starts UNCHECKED in the picker.
            verify(!body.isPartitionEnabled("u-usb"), "auto-show must not pre-check the box");
            compare(body.stalePartitionList.length, 0, "nothing stale while mounted");

            // User ticks the checkbox → this is exactly PartitionRow.onToggled.
            body.setPartitionEnabled("u-usb", true);
            verify(body.isPartitionEnabled("u-usb"), "checking the box must persist to enabledPartitions");
            compare(body.stalePartitionList.length, 0, "still mounted → still not stale");

            // Unplug: the mount-gated list drops u-usb (what
            // MetricsBackend.mountedAvailablePartitions does live).
            body.diskPartitions = [{ id: "u-baz", label: "bazzite" }];
            wait(20);
            compare(body.stalePartitionList.length, 1, "checked-then-unplugged removable must surface as a greyed stale row");
            compare(body.stalePartitionList[0].id, "u-usb");
        }

        function test_SCENARIO_unchecked_autoshown_removable_just_disappears() {
            // Counterpart: a removable that was only auto-shown (never checked)
            // is NOT in enabledPartitions, so on unplug it correctly vanishes
            // with no stale row (nothing to clean up). This is what the live
            // test actually exercised — hence "no greyed row" was correct there.
            body.partitionsReady = true;
            body.enabledPartitionsCsv = "u-baz"; // u-usb deliberately NOT checked
            body.diskPartitions = [
                { id: "u-baz", label: "bazzite" },
                { id: "u-usb", label: "MYUSB" }
            ];
            wait(20);
            compare(body.stalePartitionList.length, 0);
            body.diskPartitions = [{ id: "u-baz", label: "bazzite" }]; // unplug
            wait(20);
            compare(body.stalePartitionList.length, 0, "an unchecked auto-shown removable leaves no stale row");
        }

        function test_removeStalePartition_clears_csvs_and_cache() {
            body.partitionsReady = true;
            body.enabledPartitionsCsv = "u-usb,u-baz";
            body.partitionOrderCsv = "u-usb,u-baz";
            body.diskPartitions = [
                {
                    id: "u-usb",
                    label: "backups"
                },
                {
                    id: "u-baz",
                    label: "bazzite"
                }
            ];
            body.diskPartitions = [
                {
                    id: "u-baz",
                    label: "bazzite"
                }
            ];
            verify(body.stalePartitionList.length === 1, "u-usb must be stale before removal");

            body.removeStalePartition("u-usb");
            verify(body.enabledPartitionsCsv.split(",").indexOf("u-usb") === -1, "removed from enabledPartitions");
            verify(body.partitionOrderCsv.split(",").indexOf("u-usb") === -1, "removed from partitionOrder");
            compare(body.stalePartitionList.length, 0, "no longer surfaced after removal");
            verify(JSON.parse(body.partitionLabelsJson || "{}")["u-usb"] === undefined, "label cache entry pruned");
        }

        function test_label_cache_not_written_on_open_for_empty_default() {
            // _refreshLabelCache must treat "" and "{}" as equal so merely
            // opening the dialog (no user action) doesn't dirty partitionLabels.
            body.partitionLabelsJson = "";
            body.enabledPartitionsCsv = "";
            body.partitionOrderCsv = "";
            body.diskPartitions = [
                {
                    id: "u-baz",
                    label: "bazzite"
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
