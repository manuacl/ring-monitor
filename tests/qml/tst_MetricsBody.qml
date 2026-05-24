import QtQuick
import QtTest
import "../../contents/ui" as Ui

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
            body.metricOrderCsv = "cpu,ram,swap,gpu,disk";
            body.enabledMetricsCsv = "cpu,ram";
            body.showCpuCores = false;
            wait(20);
        }

        // ── loadOrder: CSV → orderModel ───────────────────────────────
        function test_loadOrder_populates_model_from_csv() {
            compare(body._orderModel.count, 5);
            compare(body._orderModel.get(0).metricId, "cpu");
            compare(body._orderModel.get(4).metricId, "disk");
        }

        function test_metricOrderCsv_change_reloads_model() {
            body.metricOrderCsv = "ram,gpu,cpu";
            wait(20);
            compare(body._orderModel.count, 3);
            compare(body._orderModel.get(0).metricId, "ram");
            compare(body._orderModel.get(1).metricId, "gpu");
            compare(body._orderModel.get(2).metricId, "cpu");
        }

        // ── currentOrder + commitOrder: roundtrip ─────────────────────
        function test_currentOrder_reads_model() {
            const order = body.currentOrder();
            compare(order, ["cpu", "ram", "swap", "gpu", "disk"]);
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
            const keys = ["metricOrderCsv", "enabledMetricsCsv", "showCpuCores"];
            for (const k of keys) {
                verify(k in body, "MetricsBody must expose property " + k);
            }
        }

        // ── Descriptions are present + i18n switched to qsTr() ───────
        function test_metricDescriptions_contain_all_5_metrics() {
            const desc = body.metricDescriptions;
            for (const id of ["cpu", "ram", "swap", "gpu", "disk"]) {
                verify(desc[id], "metricDescriptions must include " + id);
                verify(typeof desc[id] === "string" && desc[id].length > 0, "description for " + id + " must be a non-empty string");
            }
        }
    }
}
