import QtQuick
import QtTest
import "../../contents/ui/platforms/standalone" as Standalone

// Behaviour tests for the STANDALONE ColorPicker
// (platforms/standalone/ColorPicker.qml) — the Qt.labs-free wrapper around
// QtQuick.Dialogs.ColorDialog used on the standalone host (Plasma uses the
// kquickcontrols adapter, which can't load under qmltestrunner).
//
// SCENARIO (dark text colour not applied, standalone): the dialog's
// `selectedColor` was permanently bound to `color` (`selectedColor:
// root.color`). The live binding kept the selection pinned to `color`, so
// the user's in-dialog pick was lost and `onAccepted` re-read the OLD colour
// → `color` never changed and the swatch ("pastille") never updated. The fix
// seeds `selectedColor` imperatively on open instead. These tests pin the
// contract the shared AppearanceBody wiring relies on.

Item {
    width: 100
    height: 100

    Standalone.ColorPicker {
        id: picker
        color: "#111111"
    }

    // Pristine instance for the decoupling guard: the accept test below
    // breaks the dialog binding on its own instance, so the root-cause guard
    // needs an untouched picker to observe a (re-introduced) live binding.
    Standalone.ColorPicker {
        id: pristine
        color: "#111111"
    }

    TestCase {
        name: "ColorPicker"
        when: windowShown

        function init() {
            picker.color = "#111111";
        }

        // The swatch background tracks `color` (this is the pastille).
        function test_swatch_tracks_color() {
            picker.color = "#3366cc";
            compare(picker.background.color.toString().toLowerCase(), "#3366cc");
        }

        // Confirming a pick lands the chosen colour on `color` and fires
        // `accepted` — the contract AppearanceBody's handler depends on. The
        // dialog must be open() for accept() to emit, mirroring the real flow.
        function test_accept_applies_selected_color_and_emits() {
            const spy = signalSpy.createObject(picker, { target: picker, signalName: "accepted" });
            picker._dialog.open();
            picker._dialog.selectedColor = "#aabbcc";
            picker._dialog.accept();
            compare(picker.color.toString().toLowerCase(), "#aabbcc", "color takes the dialog's selectedColor on accept");
            compare(spy.count, 1, "accepted fires once");
            spy.destroy();
        }

        // Root-cause guard: the dialog selection must NOT be live-bound to
        // `color`. The old `selectedColor: root.color` binding made an
        // external `color` change (e.g. AppearanceBody's Binding re-asserting
        // the model value) hijack the in-progress selection — the dark-swatch
        // bug. Uses the pristine picker so no prior imperative set has already
        // broken the binding.
        function test_selection_not_live_bound_to_color() {
            // Change color WITHOUT first touching selectedColor (an imperative
            // set would break a live binding and mask the bug). A live
            // `selectedColor: color` binding makes selectedColor follow to
            // #222222; the imperative-seed fix leaves it untouched.
            pristine.color = "#222222";
            verify(pristine._dialog.selectedColor.toString().toLowerCase() !== "#222222",
                   "dialog.selectedColor must not track color (a live binding overwrites the user's pick)");
        }

        Component {
            id: signalSpy
            SignalSpy {}
        }
    }
}
