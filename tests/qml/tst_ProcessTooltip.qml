import QtQuick
import QtTest
import "../../contents/ui/core" as Ui

// Rendering tests for ProcessTooltip.qml — the generic top-processes ring
// tooltip (issue #69). The ranking/formatting math is covered runtime-free in
// process-ranking.test.mjs; this checks the QML view: row count tracks the
// model, the footer renders the injected text, and sampling stays inert until
// the owning ring arms it.
Item {
    id: root
    width: 300
    height: 300

    Ui.ProcessTooltip {
        id: tip
        armed: true
        title: "Top processes — CPU"
        processes: []
        footerText: ""
    }

    TestCase {
        name: "ProcessTooltip"
        when: windowShown

        function init() {
            tip.armed = true;
            tip.processes = [];
            tip.footerText = "";
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

        function test_footer_renders_the_injected_text() {
            tip.footerText = "load  0.82  0.75  0.61";
            compare(tip._footerText, "load  0.82  0.75  0.61");
        }

        // armed=false (every non-owning ring) keeps the HoverHandler disabled,
        // so sampling never engages there — the no-background-polling guarantee.
        function test_not_armed_means_not_sampling() {
            tip.armed = false;
            compare(tip.samplingActive, false);
        }
    }
}
