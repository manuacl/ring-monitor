import QtQuick
import QtTest
import "../../contents/ui/core" as Ui

// Rendering tests for ProcessTooltip.qml — the CPU-ring top-processes tooltip
// (issue #69). The ranking/formatting math is covered runtime-free in
// process-ranking.test.mjs; this checks the QML view: row count tracks the
// model, the footer formats the load averages, and sampling stays inert until
// the CPU ring arms it.
Item {
    id: root
    width: 300
    height: 300

    Ui.ProcessTooltip {
        id: tip
        armed: true
        processes: []
        loadAverages: [0, 0, 0]
    }

    TestCase {
        name: "ProcessTooltip"
        when: windowShown

        function init() {
            tip.armed = true;
            tip.processes = [];
            tip.loadAverages = [0, 0, 0];
        }

        function test_row_count_tracks_the_model() {
            tip.processes = [
                { pid: 3821, name: "firefox", cpuPercent: 42.3 },
                { pid: 1290, name: "Xorg", cpuPercent: 9.4 },
                { pid: 8120, name: "node", cpuPercent: 6.2 }
            ];
            compare(tip._rowCount, 3);
        }

        function test_empty_model_renders_no_rows() {
            tip.processes = [];
            compare(tip._rowCount, 0);
        }

        function test_footer_formats_the_load_averages() {
            tip.loadAverages = [0.82, 0.75, 0.61];
            verify(tip._footerText.indexOf("0.82") !== -1);
            verify(tip._footerText.indexOf("0.75") !== -1);
            verify(tip._footerText.indexOf("0.61") !== -1);
        }

        // armed=false (every non-CPU ring) keeps the HoverHandler disabled, so
        // sampling never engages there — the no-background-polling guarantee.
        function test_not_armed_means_not_sampling() {
            tip.armed = false;
            compare(tip.samplingActive, false);
        }
    }
}
