import QtQuick
import QtTest
import "../layout-us.js" as LayoutUs

TestCase {
    name: "LayoutUs"

    function test_has_six_rows() {
        compare(LayoutUs.rows.length, 6);
    }

    function test_function_row_starts_with_esc() {
        compare(LayoutUs.rows[0][0].label, "Esc");
        compare(LayoutUs.rows[0][0].shape, "fn");
        compare(LayoutUs.rows[0].length, 15);
    }

    function findByLabel(row, label) {
        for (var i = 0; i < row.length; i++)
            if (row[i].label === label)
                return row[i];
        return null;
    }

    function test_letter_a_keycode_and_shift_label() {
        var a = findByLabel(LayoutUs.rows[3], "a");
        compare(a.keycode, 30);
        compare(a.labelShift, "A");
        compare(a.shape, "normal");
    }

    function test_space_key_shape_and_keycode() {
        var row = LayoutUs.rows[5];
        var space = findByLabel(row, "Space");
        compare(space.keycode, 57);
        compare(space.shape, "space");
    }

    function test_shift_key_is_modkey_type() {
        var row = LayoutUs.rows[4];
        compare(row[0].keytype, "modkey");
        compare(row[0].shape, "shift");
        compare(row[0].keycode, 42);
        compare(row[0].labelCaps, "Caps");
    }

    function test_right_shift_shares_shift_keycode_family() {
        var row = LayoutUs.rows[4];
        var rightShift = row[row.length - 1];
        compare(rightShift.keytype, "modkey");
        compare(rightShift.keycode, 54);
    }

    function test_backspace_and_enter_expand_the_row() {
        var backspace = findByLabel(LayoutUs.rows[1], "Backspace");
        compare(backspace.shape, "expand");
        compare(backspace.keycode, 14);
        var enter = findByLabel(LayoutUs.rows[3], "Enter");
        compare(enter.shape, "expand");
        compare(enter.keycode, 28);
    }
}
