import QtQuick
import QtTest
import "../../contents/ui/core" as Ui

// Rendering tests for GpuTooltip.qml — the GPU-ring hover tooltip (issue #71).
// The formatting/ranking math is covered runtime-free in gpu-tooltip-model.test.mjs;
// this checks the QML view: stat row count tracks the detail object, process row
// count tracks the processes array, and sampling stays inert until the owning ring
// arms it.
Item {
    id: root
    width: 300
    height: 300

    Ui.GpuTooltip {
        id: tip
        armed: true
        detail: ({})
        processes: []
    }

    TestCase {
        name: "GpuTooltip"
        when: windowShown

        function init() {
            tip.armed = true;
            tip._show = false;
            tip.detail = ({});
            tip.processes = [];
        }

        // Stat rows track the detail object: a fully-populated detail yields all
        // six rows (Model, Usage, VRAM, Temperature, Power, Clock).
        function test_stat_rows_track_detail() {
            tip.detail = { model: "NVIDIA RTX 4090", usagePercent: 73, vramUsedBytes: 6442450944, vramTotalBytes: 25769803776, tempC: 64, powerW: 142.5, clockMhz: 1815 };
            compare(tip._statRowCount, 6);
        }

        // Absent fields are skipped; only the rows whose sensor is present appear.
        function test_sparse_detail_skips_absent_rows() {
            tip.detail = { usagePercent: 30, tempC: 55 };
            compare(tip._statRowCount, 2);
        }

        // An empty detail object yields no stat rows (shows the "Gathering…" placeholder).
        function test_empty_detail_renders_no_stat_rows() {
            tip.detail = ({});
            compare(tip._statRowCount, 0);
        }

        // Process rows track the processes array.
        function test_process_rows_track_processes() {
            tip.processes = [
                { pid: 3821, name: "blender", vramBytes: 2147483648 },
                { pid: 1290, name: "firefox", vramBytes: 536870912 }
            ];
            compare(tip._procRowCount, 2);
        }

        // Empty processes array → no process rows (section hidden).
        function test_no_processes_means_no_process_rows() {
            tip.processes = [];
            compare(tip._procRowCount, 0);
        }

        // armed=false (every non-owning ring) keeps the HoverHandler disabled,
        // so sampling never engages there — the no-background-polling guarantee.
        function test_not_armed_means_not_sampling() {
            tip.armed = false;
            compare(tip.samplingActive, false);
        }

        // SCENARIO (#69 follow-up, same pattern here): the stat list re-samples on
        // each backend tick, so the width must be a grow-only high-water mark reset
        // on dismiss — not a bare implicitWidth bind that yoyos tick-to-tick.
        // NOTE: the grow-only width itself is LIVE-verified only — under
        // QT_QPA_PLATFORM=offscreen the Window popup never realizes. What IS
        // deterministic offscreen is the reset logic below (pure property math).

        // Reset on dismiss so a one-off wide sample doesn't pin every later hover.
        function test_hiding_resets_the_high_water_mark() {
            tip._show = true; // _displayed = armed(true) && true
            tip._maxContentWidth = 250;
            tip._show = false; // _displayed → false
            tryCompare(tip, "_maxContentWidth", 0);
        }

        // The OTHER dismissal term: disarming (armed→false) also hides the popup,
        // so it must reset too — else a re-armed ring would open at a stale width.
        // Guards the reset keying on `_displayed`, not `_show` alone.
        function test_disarming_resets_the_high_water_mark() {
            tip._show = true;
            tip._maxContentWidth = 250;
            tip.armed = false; // _displayed → false
            tryCompare(tip, "_maxContentWidth", 0);
        }

        // ── openRight placement property ───────────────────────────────
        // openRight controls which side of the ring the Window-popup opens toward
        // so it grows into the screen (left-anchored widget → open right; the
        // standalone Main.qml passes this from _tooltipOpenRight via MainContent).

        function test_openRight_defaults_to_false() {
            compare(tip.openRight, false);
        }

        function test_openRight_can_be_set_to_true() {
            tip.openRight = true;
            compare(tip.openRight, true);
            tip.openRight = false; // shared instance — restore default for other tests
        }

        function test_openRight_can_be_set_back_to_false() {
            tip.openRight = true;
            tip.openRight = false;
            compare(tip.openRight, false);
        }
    }
}
