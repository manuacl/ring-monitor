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
            body.metricOrderCsv = "cpu,cpuTemp,ram,swap,gpu,gpuTemp,disk,diskIo,sensorTemp";
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
            // 8 catalog ids (mergeWithCatalog appends any missing — the seed
            // CSV omits diskIo, so it's appended at the end).
            compare(body._orderModel.count, 9);
            compare(body._orderModel.get(0).metricId, "cpu");
            compare(body._orderModel.get(6).metricId, "disk");
            compare(body._orderModel.get(7).metricId, "diskIo");
        }

        function test_metricOrderCsv_change_reloads_model_and_appends_missing() {
            // User CSV is partial (pre-0.4 install) — mergeWithCatalog
            // tacks the missing ids onto the end so the config list
            // shows every available metric.
            body.metricOrderCsv = "ram,gpu,cpu";
            wait(20);
            compare(body._orderModel.count, 9);
            compare(body._orderModel.get(0).metricId, "ram");
            compare(body._orderModel.get(1).metricId, "gpu");
            compare(body._orderModel.get(2).metricId, "cpu");
            // Order of appended ids is the catalog canonical sequence.
            compare(body._orderModel.get(3).metricId, "cpuTemp");
        }

        // ── currentOrder + commitOrder: roundtrip ─────────────────────
        function test_currentOrder_reads_model() {
            const order = body.currentOrder();
            compare(order, [
                "cpu",
                "cpuTemp",
                "ram",
                "swap",
                "gpu",
                "gpuTemp",
                "disk",
                "diskIo",
                "sensorTemp"
            ]);
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
            const keys = [
                "metricOrderCsv",
                "enabledMetricsCsv",
                "enabledPartitionsCsv",
                "partitionOrderCsv",
                "showCpuCores",
                "mergeCpuTemp",
                "mergeGpuTemp",
                "tempUnit",
                "sensorTempId",
                "sensorTempLabel",
                "sensorTempMinC",
                "sensorTempMaxC"
            ];
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

        // ── Temperature unit: property → which radio is checked ─────
        // The radios live in the TemperatureUnitSettings child; tests
        // reach them by objectName (tests/CLAUDE.md leaf-control rule).
        function test_tempUnit_default_is_auto_and_drives_radio() {
            // Make sure the row is visible (only shown when at least
            // one temperature metric is enabled) so the radios are
            // realised by the Loader.
            body.enabledMetricsCsv = "cpu,cpuTemp";
            wait(20);
            compare(body.tempUnit, "auto");
            verify(findChild(body, "tempUnitAutoRadio").checked);
            verify(!findChild(body, "tempUnitCelsiusRadio").checked);
            verify(!findChild(body, "tempUnitFahrenheitRadio").checked);
        }

        function test_tempUnit_celsius_swaps_the_checked_radio() {
            body.enabledMetricsCsv = "cpu,cpuTemp";
            wait(20);
            body.tempUnit = "celsius";
            verify(!findChild(body, "tempUnitAutoRadio").checked);
            verify(findChild(body, "tempUnitCelsiusRadio").checked);
            verify(!findChild(body, "tempUnitFahrenheitRadio").checked);
        }

        function test_tempUnit_fahrenheit_swaps_the_checked_radio() {
            body.enabledMetricsCsv = "cpu,cpuTemp";
            wait(20);
            body.tempUnit = "fahrenheit";
            verify(!findChild(body, "tempUnitAutoRadio").checked);
            verify(!findChild(body, "tempUnitCelsiusRadio").checked);
            verify(findChild(body, "tempUnitFahrenheitRadio").checked);
        }

        // ── Descriptions are present + i18n switched to qsTr() ───────
        function test_metricDescriptions_contain_all_catalog_metrics() {
            const desc = body.metricDescriptions;
            for (const id of [
                "cpu",
                "cpuTemp",
                "ram",
                "swap",
                "gpu",
                "gpuTemp",
                "disk",
                "diskIo",
                "sensorTemp"
            ]) {
                verify(desc[id], "metricDescriptions must include " + id);
                verify(typeof desc[id] === "string" && desc[id].length > 0, "description for " + id + " must be a non-empty string");
            }
        }
    }
}
