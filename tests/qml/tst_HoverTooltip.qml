import QtQuick
import QtQuick.Layouts
import QtTest
import "../../contents/ui/core" as Ui

// Rendering tests for HoverTooltip.qml — the shared popup chrome (extracted from
// ProcessTooltip, #69, reused by DiskTooltip #68). The Window-popup width /
// placement is LIVE-only (offscreen the popup never realizes — see
// core/CLAUDE.md § "popup behaviour is live-only"); what's deterministic here is
// the arm/show/dismiss state machine and that the injected content loads.
Item {
    id: root
    width: 300
    height: 300

    Ui.HoverTooltip {
        id: tip
        armed: true
        contentComponent: ColumnLayout {
            Item {
                implicitWidth: 60
                implicitHeight: 20
            }
        }
    }

    TestCase {
        name: "HoverTooltip"
        when: windowShown

        function init() {
            tip.armed = true;
            tip._show = false;
            tip._maxContentWidth = 0;
        }

        // armed=false (every non-owning ring) keeps the HoverHandler disabled, so
        // sampling never engages — the no-background-work guarantee.
        function test_not_armed_means_not_sampling() {
            tip.armed = false;
            compare(tip.samplingActive, false);
        }

        // _displayed = armed && _show drives the high-water-mark reset.
        function test_displayed_is_armed_and_show() {
            tip.armed = true;
            tip._show = false;
            compare(tip._displayed, false);
            tip._show = true;
            compare(tip._displayed, true);
            tip.armed = false;
            compare(tip._displayed, false);
        }

        // Reset on dismiss so a one-off wide sample doesn't pin every later hover.
        function test_hiding_resets_the_high_water_mark() {
            tip._show = true;
            tip._maxContentWidth = 250;
            tip._show = false;
            tryCompare(tip, "_maxContentWidth", 0);
        }

        // The OTHER dismissal term: disarming also hides → must reset too.
        function test_disarming_resets_the_high_water_mark() {
            tip._show = true;
            tip._maxContentWidth = 250;
            tip.armed = false;
            tryCompare(tip, "_maxContentWidth", 0);
        }

        // The injected contentComponent is loaded (eagerly, so consumers can read
        // test hooks off contentItem even when the popup is never shown).
        function test_content_component_loads() {
            verify(tip.contentItem !== null);
        }
    }
}
