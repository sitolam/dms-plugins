import QtQuick
import QtTest
import "../Conditions.js" as Conditions

TestCase {
    name: "Conditions"

    function node(id, when, checked, disabled) {
        return {
            id: id,
            when: when || "",
            checked: checked || "",
            disabled: disabled || ""
        };
    }

    function test_collect_skips_nodes_without_conditions() {
        const out = Conditions.collect([node("a"), node("b", "true")]);
        compare(out.length, 1);
        compare(out[0].id, "b");
        compare(out[0].kind, "when");
    }

    function test_collect_returns_all_three_kinds_in_order() {
        const out = Conditions.collect([node("a", "w", "c", "d")]);
        compare(out.map(c => c.kind), ["when", "checked", "disabled"]);
    }

    function test_shell_quote_wraps_and_escapes() {
        compare(Conditions.shellQuote("plain"), "'plain'");
        compare(Conditions.shellQuote("it's"), "'it'\\''s'");
    }

    function test_build_script_redirects_snippet_output_only() {
        const script = Conditions.buildScript([
            {
                id: "a",
                kind: "when",
                snippet: "grep -q x /etc/f"
            }
        ]);
        compare(script, "{ grep -q x /etc/f ; } >/dev/null 2>&1; printf '%s\\t%s\\t%s\\n' 'a' 'when' \"$?\"");
    }

    function test_build_script_one_line_per_condition() {
        const script = Conditions.buildScript([
            {
                id: "a",
                kind: "when",
                snippet: "true"
            },
            {
                id: "b",
                kind: "checked",
                snippet: "false"
            }
        ]);
        compare(script.split("\n").length, 2);
    }

    function test_build_script_empty_is_empty_string() {
        compare(Conditions.buildScript([]), "");
    }

    function test_parse_output() {
        const results = Conditions.parseOutput("a\twhen\t0\nb\tchecked\t1\n");
        compare(results["a"].when, 0);
        compare(results["b"].checked, 1);
    }

    function test_parse_output_ignores_junk_lines() {
        const results = Conditions.parseOutput("noise\na\twhen\t0\n\n");
        compare(Object.keys(results).length, 1);
        compare(results["a"].when, 0);
    }

    function test_apply_no_conditions_is_visible_unchecked_enabled() {
        const state = Conditions.applyTo(node("a"), {});
        compare(state.visible, true);
        compare(state.checked, false);
        compare(state.disabled, false);
    }

    function test_apply_when_failing_hides_row() {
        const state = Conditions.applyTo(node("a", "cmd"), {
            a: {
                when: 1
            }
        });
        compare(state.visible, false);
    }

    function test_apply_when_succeeding_shows_row() {
        const state = Conditions.applyTo(node("a", "cmd"), {
            a: {
                when: 0
            }
        });
        compare(state.visible, true);
    }

    function test_apply_checked_and_disabled() {
        const state = Conditions.applyTo(node("a", "", "cmd", "cmd2"), {
            a: {
                checked: 0,
                disabled: 0
            }
        });
        compare(state.checked, true);
        compare(state.disabled, true);
    }

    function test_pending_result_keeps_row_visible() {
        // Results have not arrived yet: a row with a `when` must not flicker
        // out of the list and back in.
        const state = Conditions.applyTo(node("a", "cmd"), {});
        compare(state.visible, true);
        compare(state.pending, true);
    }
}
