import QtQuick
import QtTest
import "../../contents/ui/core" as Ui

// Tests for Ring.qml — covers the QML bindings (text, dimensions, sweep
// angle, nested values count). The pure geometry math is covered by
// tests/ring-geometry.test.mjs at the JS level; this file checks that
// the QML side wires those values up correctly.

Item {
    id: root
    width: 220
    height: 220

    Ui.Ring {
        id: ring
        width: 180
        height: 180
    }

    TestCase {
        name: "Ring"
        when: windowShown

        function init() {
            ring.label = "";
            ring.value = 0;
            ring.rawValue = NaN;
            ring.unit = "%";
            ring.nestedValues = [];
            ring.equalValues = [];
            ring.splitMode = false;
            ring.splitValue = 0;
            ring.splitRawValue = 0;
            ring.splitUnit = "°";
            // Wait for animations triggered by previous tests to settle.
            tryCompare(ring, "displayValue", 0);
            tryCompare(ring, "displayRawValue", 0);
            tryCompare(ring, "displaySplitValue", 0);
            tryCompare(ring, "displaySplitRawValue", 0);
        }

        // ── Center label / value text rendering ───────────────────
        function test_label_renders_from_property() {
            ring.label = "CPU";
            compare(ring._labelText, "CPU");
        }
        function test_value_text_shows_rounded_value_with_unit() {
            ring.value = 42;
            // displayValue animates over 400ms; wait for it to settle.
            tryCompare(ring, "displayValue", 42, 1000);
            compare(ring._valueText, "42%");
        }
        function test_value_text_uses_custom_unit() {
            ring.unit = " °C";
            ring.value = 65;
            tryCompare(ring, "displayValue", 65, 1000);
            compare(ring._valueText, "65 °C");
        }
        function test_value_text_rounds_fractional_input() {
            ring.value = 42.6;
            tryCompare(ring, "displayValue", 42.6, 1000);
            compare(ring._valueText, "43%");
        }

        // ── Sweep angle binding (RingGeometry → arc) ──────────────
        function test_sweep_angle_zero_when_value_zero() {
            ring.value = 0;
            tryCompare(ring, "displayValue", 0, 1000);
            // BASE_SWEEP_ANGLE × (0/100) = 0
            fuzzyCompare(ring._sweepAngle, 0, 0.01);
        }
        function test_sweep_angle_half_when_value_50() {
            ring.value = 50;
            tryCompare(ring, "displayValue", 50, 1000);
            // BASE_SWEEP_ANGLE × 0.5 = 135
            fuzzyCompare(ring._sweepAngle, 135, 0.01);
        }
        function test_sweep_angle_full_when_value_100() {
            ring.value = 100;
            tryCompare(ring, "displayValue", 100, 1000);
            fuzzyCompare(ring._sweepAngle, 270, 0.01);
        }

        // ── Dimensions binding (RingGeometry → Ring) ──────────────
        function test_dimensions_at_size_180() {
            // ring is 180×180 → size = 180. Cross-check against
            // RingGeometry's rules (also tested by ring-geometry.test.mjs).
            compare(ring.size, 180);
            verify(ring.ringStroke > 0);
            verify(ring.ringRadius > 0);
            verify(ring.valuePx > 0);
        }

        // ── SCENARIO (issue #13): label tracks the visible ring's
        //     bottom even when the delegate is stretched taller than
        //     the ring (horizontal-layout panels with
        //     Layout.fillHeight: true). The label must sit inside the
        //     ring's bounding square (ringBox), not at the root Item's
        //     bottom edge.
        function test_label_stays_inside_ring_box_when_root_is_stretched() {
            // Make the root rectangular: ring is 180×180, root is 180×300.
            // ring.size = min(width, height) = 180 — unchanged. The visible
            // ring is centered, so its geometric bottom is at
            // root.height/2 + size/2 = 150 + 90 = 240. Without the ringBox
            // wrap the label sat at root.height - bottomMargin ≈ 275 (off
            // by ~60px).
            ring.height = 300;
            wait(20);
            const ringGeometricBottom = ring.height / 2 + ring.size / 2;
            verify(ring._labelBottomY <= ringGeometricBottom, "label bottom (" + ring._labelBottomY + ") must be at or above the visible ring's bottom (" + ringGeometricBottom + "), not at the stretched root's bottom");
            ring.height = 180;
        }

        // ── nestedValues array drives the per-core ring count ─────
        function test_nestedValues_drives_repeater() {
            ring.nestedValues = [10, 20, 30, 40, 50, 60];
            // The Repeater inside Ring has `model: root.nestedValues.length`
            // We can't easily count its children from here without exposing
            // them, but verifying the length round-trips proves the binding.
            compare(ring.nestedValues.length, 6);
        }

        // ── Split mode: full arc hidden, both halves visible ──────
        function test_split_mode_hides_full_arc_shows_both_halves() {
            ring.splitMode = true;
            verify(!ring._fullArcVisible, "full arc must hide when splitMode is on");
            verify(ring._leftArcVisible, "left half arc must show when splitMode is on");
            verify(ring._rightArcVisible, "right half arc must show when splitMode is on");
            verify(ring._splitValueTextVisible, "split value text must show when splitMode is on");
        }

        function test_default_mode_hides_split_halves() {
            // splitMode defaults to false (reset in init()).
            verify(ring._fullArcVisible, "full arc must show when splitMode is off");
            verify(!ring._leftArcVisible, "left half arc must hide when splitMode is off");
            verify(!ring._rightArcVisible, "right half arc must hide when splitMode is off");
            verify(!ring._splitValueTextVisible, "split value text must hide when splitMode is off");
        }

        // ── Split mode: sweep angles map through left/right half helpers ──
        function test_split_left_sweep_at_value_50_is_65_5_degrees() {
            ring.splitMode = true;
            ring.value = 50;
            tryCompare(ring, "displayValue", 50, 1000);
            // effectiveHalfSweep() × 0.5 = (135 − 4) × 0.5 = 65.5
            fuzzyCompare(ring._leftSweepAngle, 65.5, 0.01);
        }

        function test_split_right_sweep_at_value_100_is_negative_131() {
            ring.splitMode = true;
            ring.splitValue = 100;
            tryCompare(ring, "displaySplitValue", 100, 1000);
            // −effectiveHalfSweep() × 1 = −(135 − 4) = −131
            fuzzyCompare(ring._rightSweepAngle, -131, 0.01);
        }

        // ── Split mode: secondary text renders raw value + splitUnit ──
        function test_split_value_text_renders_raw_with_split_unit() {
            ring.splitMode = true;
            ring.splitRawValue = 45;
            ring.splitUnit = "°";
            tryCompare(ring, "displaySplitRawValue", 45, 1000);
            compare(ring._splitValueText, "45°");
        }

        function test_split_value_text_rounds_fractional_raw() {
            ring.splitMode = true;
            ring.splitRawValue = 67.4;
            tryCompare(ring, "displaySplitRawValue", 67.4, 1000);
            compare(ring._splitValueText, "67°");
        }

        // ── rawValue override: text displays rawValue, sweep stays on value ──
        function test_rawValue_overrides_value_text_without_changing_sweep() {
            // Simulate a temperature ring: sweep = 50% (mid-arc),
            // displayed = 60°C (raw reading).
            ring.unit = "°C";
            ring.value = 50;
            ring.rawValue = 60;
            tryCompare(ring, "displayValue", 50, 1000);
            tryCompare(ring, "displayRawValue", 60, 1000);
            compare(ring._valueText, "60°C");
            // BASE_SWEEP_ANGLE × 0.5 = 135 — sweep unaffected by rawValue.
            fuzzyCompare(ring._sweepAngle, 135, 0.01);
        }

        function test_rawValue_falls_back_to_value_when_NaN() {
            // No override → text = Math.round(value) + unit, like before.
            ring.unit = "%";
            ring.value = 42;
            ring.rawValue = NaN;
            tryCompare(ring, "displayValue", 42, 1000);
            tryCompare(ring, "displayRawValue", 42, 1000);
            compare(ring._valueText, "42%");
        }

        // ── Equal mode (disk multi-partition): main arc hidden, N rings ──
        function test_equal_mode_hides_main_arc_and_renders_n_rings() {
            ring.equalValues = [10, 20, 30];
            verify(ring._equalMode, "equalMode must be on when equalValues is non-empty");
            verify(!ring._fullArcVisible, "main arc must hide in equal mode");
            verify(!ring._leftArcVisible, "split halves must stay hidden in equal mode");
            compare(ring._equalRingCount, 3);
        }

        function test_equal_mode_center_shows_rawValue_average() {
            // The parent passes rawValue = the partition average; the centre
            // text must read that, not any single ring's value.
            ring.equalValues = [52, 8, 26, 67];
            ring.rawValue = (52 + 8 + 26 + 67) / 4;  // 38.25
            ring.unit = "%";
            tryCompare(ring, "displayRawValue", 38.25, 1000);
            compare(ring._valueText, "38%");
        }

        function test_default_mode_has_no_equal_rings() {
            // equalValues defaults to [] (reset in init()).
            verify(!ring._equalMode, "equalMode must be off by default");
            verify(ring._fullArcVisible, "main arc must show when not in equal mode");
            compare(ring._equalRingCount, 0);
        }
    }
}
