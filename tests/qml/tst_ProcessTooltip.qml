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
            tip._show = false;
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

        // SCENARIO (#69 follow-up): the ranked list re-samples every 500 ms, so a
        // width bound straight to live content made the popup yoyo wider/narrower
        // tick-to-tick. The width is now a grow-only high-water mark — it grows on
        // a wider sample and IGNORES a narrower one.
        // NOTE: the grow-only width itself (the tracker raising _maxContentWidth
        // from col.implicitWidth, and the max(mark, implicitWidth) floor) is
        // LIVE-verified only — under QT_QPA_PLATFORM=offscreen the Window popup
        // never realizes, so col never lays out and the popup width never binds.
        // What IS deterministic offscreen is the reset logic below, which is the
        // part that decides whether the mark yoyos back: it's pure property math.
        // See core/CLAUDE.md § "popup behaviour is live-only".

        // Reset on dismiss so a one-off wide sample doesn't pin every later hover.
        // Pure property logic (no layout): _displayed = armed && _show; seed the
        // mark, drop _show, the on_DisplayedChanged reset must zero it.
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
