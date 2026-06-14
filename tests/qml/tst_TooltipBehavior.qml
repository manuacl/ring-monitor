import QtQuick
import QtTest
import "../../contents/ui/core" as Ui

// Rendering tests for TooltipBehavior.qml — the non-visual placement + show/hide
// state machine shared by the ring hover tooltips (#149). The Window-popup
// realization (popupType, anchorMarker geometry, width mark growth) is live-only
// — under QT_QPA_PLATFORM=offscreen the popup never realizes — so this covers the
// deterministic property logic: the sampling gate, the show/displayed derivation,
// and the high-water-mark reset on dismiss. See core/CLAUDE.md § "popup behaviour
// is live-only".
Item {
    id: root
    width: 200
    height: 200

    Ui.TooltipBehavior {
        id: behavior
        armed: true
    }

    TestCase {
        name: "TooltipBehavior"
        when: windowShown

        function init() {
            behavior.armed = true;
            behavior._show = false;
            behavior._maxContentWidth = 0;
            behavior.openRight = false;
        }

        // armed=false (every non-owning ring) keeps the HoverHandler disabled, so
        // sampling never engages there — the no-background-polling guarantee.
        function test_not_armed_means_not_sampling() {
            behavior.armed = false;
            compare(behavior.samplingActive, false);
        }

        // _displayed = armed && _show — both terms must be true to show.
        function test_displayed_requires_armed_and_show() {
            behavior.armed = true;
            behavior._show = false;
            compare(behavior._displayed, false);
            behavior._show = true;
            compare(behavior._displayed, true);
        }

        // Reset on dismiss so a one-off wide sample doesn't pin every later hover.
        function test_hiding_resets_the_high_water_mark() {
            behavior._show = true;       // _displayed = armed(true) && true
            behavior._maxContentWidth = 250;
            behavior._show = false;      // _displayed → false
            tryCompare(behavior, "_maxContentWidth", 0);
        }

        // The OTHER dismissal term: disarming also hides, so it must reset too —
        // guards the reset keying on `_displayed`, not `_show` alone.
        function test_disarming_resets_the_high_water_mark() {
            behavior._show = true;
            behavior._maxContentWidth = 250;
            behavior.armed = false;      // _displayed → false
            tryCompare(behavior, "_maxContentWidth", 0);
        }

        function test_openRight_defaults_to_false() {
            compare(behavior.openRight, false);
        }

        // _applyPopupType must be a no-op (no throw) when no tip is injected yet.
        function test_applyPopupType_safe_without_tip() {
            behavior.tip = null;
            behavior._applyPopupType();  // must not throw
            verify(true);
        }

        // The anchor marker is exposed for the owning tooltip to parent its ToolTip
        // to; with no Window popup (offscreen) the shift is inert and it sits at 0.
        function test_anchorMarker_exposed_at_origin() {
            verify(behavior.anchorMarker !== null);
            compare(behavior.anchorMarker.x, 0);
        }

        // In-scene placement is exposed for the tooltip's x/y; with no tip injected
        // both guard to 0 (no NaN, no throw). The live geometry needs a realized
        // popup (Window-only on the small standalone host), so this only pins the
        // safe-default branch — the placement math itself is live-verified on Plasma.
        function test_inScene_placement_safe_without_tip() {
            behavior.tip = null;
            compare(behavior.inSceneX, 0);
            compare(behavior.inSceneY, 0);
        }
    }
}
