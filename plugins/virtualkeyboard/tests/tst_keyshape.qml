import QtQuick
import QtTest
import "../KeyShape.js" as KeyShape

TestCase {
    name: "KeyShape"

    function test_width_multiplier_known_shapes() {
        compare(KeyShape.widthMultiplier("tab"), 1.6);
        compare(KeyShape.widthMultiplier("caps"), 1.9);
        compare(KeyShape.widthMultiplier("shift"), 2.5);
        compare(KeyShape.widthMultiplier("control"), 1.3);
        compare(KeyShape.widthMultiplier("normal"), 1);
    }

    function test_width_multiplier_unknown_shape_defaults_to_one() {
        compare(KeyShape.widthMultiplier("bogus"), 1);
    }

    function test_height_multiplier_fn_is_shorter() {
        compare(KeyShape.heightMultiplier("fn"), 0.7);
        compare(KeyShape.heightMultiplier("normal"), 1);
    }

    function test_label_for_plain_mode_uses_base_label() {
        var key = {label: "a", labelShift: "A"};
        compare(KeyShape.labelFor(key, 0), "a");
    }

    function test_label_for_shift_mode_uses_shift_label() {
        var key = {label: "a", labelShift: "A"};
        compare(KeyShape.labelFor(key, 1), "A");
    }

    function test_label_for_shift_mode_falls_back_without_shift_label() {
        var key = {label: "Esc"};
        compare(KeyShape.labelFor(key, 1), "Esc");
    }

    function test_label_for_caps_mode_prefers_caps_label() {
        var key = {label: "Shift", labelShift: "Shift", labelCaps: "Caps"};
        compare(KeyShape.labelFor(key, 2), "Caps");
    }

    function test_label_for_caps_mode_falls_back_to_shift_label() {
        var key = {label: "a", labelShift: "A"};
        compare(KeyShape.labelFor(key, 2), "A");
    }
}
