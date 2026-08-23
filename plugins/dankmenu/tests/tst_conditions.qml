import QtQuick
import QtTest
import "../Conditions.js" as Conditions

TestCase {
    name: "Conditions"

    function node(id, when, checked, disabled, labelCmd) {
        return {
            id: id,
            when: when || "",
            checked: checked || "",
            disabled: disabled || "",
            labelCmd: labelCmd || ""
        };
    }

    function test_collect_skips_nodes_without_conditions() {
        const out = Conditions.collect([node("a"), node("b", "true")]);
        compare(out.length, 1);
        compare(out[0].id, "b");
        compare(out[0].kind, "when");
    }

    function test_collect_returns_all_kinds_in_order() {
        const out = Conditions.collect([node("a", "w", "c", "d", "l")]);
        compare(out.map(c => c.kind), ["when", "checked", "disabled", "labelCmd"]);
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

    // labelCmd is the one kind whose *output* matters rather than its exit
    // status, so it gets its own line shape.
    function test_build_script_label_cmd_captures_stdout() {
        const script = Conditions.buildScript([
            {
                id: "a",
                kind: "labelCmd",
                snippet: "echo hi"
            }
        ]);
        verify(script.indexOf("$(") !== -1);
        verify(script.indexOf("'a'") !== -1);
        verify(script.indexOf("'labelCmd'") !== -1);
        // stderr must not reach the label, and the value must stay on one line
        // or it would break the tab-separated record.
        verify(script.indexOf("2>/dev/null") !== -1);
        verify(script.indexOf("head -n1") !== -1);
    }

    function test_parse_output_keeps_label_cmd_as_text() {
        const results = Conditions.parseOutput("a\tlabelCmd\tCPU 4%\nb\twhen\t0\n");
        compare(results["a"].labelCmd, "CPU 4%");
        compare(results["b"].when, 0);
    }

    function test_parse_output_allows_empty_label() {
        const results = Conditions.parseOutput("a\tlabelCmd\t\n");
        compare(results["a"].labelCmd, "");
    }

    function test_apply_label_cmd_overrides_label() {
        const n = node("a", "", "", "", "echo x");
        const state = Conditions.applyTo(n, {
            a: {
                labelCmd: "RAM 2.1G"
            }
        });
        compare(state.label, "RAM 2.1G");
    }

    function test_apply_label_cmd_empty_output_falls_back() {
        const n = node("a", "", "", "", "echo x");
        const state = Conditions.applyTo(n, {
            a: {
                labelCmd: ""
            }
        });
        compare(state.label, "");
        compare(state.pending, false);
    }

    function test_apply_label_cmd_pending_until_result() {
        const n = node("a", "", "", "", "echo x");
        const state = Conditions.applyTo(n, {});
        compare(state.pending, true);
        compare(state.label, "");
    }
}
