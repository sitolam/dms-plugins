import QtQuick
import QtTest
import "../Plugins.js" as Plugins

TestCase {
    name: "Plugins"

    readonly property var triggers: ({
            "=": "calculator",
            ";": "emoji"
        })

    function test_no_trigger_returns_null() {
        compare(Plugins.detectTrigger("firefox", triggers), null);
    }

    function test_empty_query_returns_null() {
        compare(Plugins.detectTrigger("", triggers), null);
    }

    function test_trigger_selects_its_plugin() {
        const hit = Plugins.detectTrigger("=2+2", triggers);
        compare(hit.pluginId, "calculator");
        compare(hit.query, "2+2");
    }

    function test_query_is_trimmed_after_the_trigger() {
        compare(Plugins.detectTrigger("=  12 * 30", triggers).query, "12 * 30");
    }

    function test_trigger_alone_yields_an_empty_query() {
        const hit = Plugins.detectTrigger(";", triggers);
        compare(hit.pluginId, "emoji");
        compare(hit.query, "");
    }

    function test_trigger_must_be_a_prefix() {
        compare(Plugins.detectTrigger("2+2=", triggers), null);
    }

    // DMS's own detector takes whichever trigger the engine yields first, so an
    // overlapping pair is a coin toss there. Here the longer one wins.
    function test_longest_trigger_wins() {
        const overlapping = {
            "=": "calculator",
            "==": "units"
        };
        compare(Plugins.detectTrigger("==3ft", overlapping).pluginId, "units");
        compare(Plugins.detectTrigger("=3+1", overlapping).pluginId, "calculator");
    }

    function test_empty_trigger_is_ignored() {
        compare(Plugins.detectTrigger("hello", {
            "": "always-on"
        }), null);
    }

    function test_material_prefix_is_stripped() {
        const icon = Plugins.iconOf({
            icon: "material:calculate"
        });
        compare(icon.name, "calculate");
        compare(icon.type, "material");
    }

    function test_unicode_prefix_is_stripped() {
        const icon = Plugins.iconOf({
            icon: "unicode:π"
        });
        compare(icon.name, "π");
        compare(icon.type, "unicode");
    }

    function test_bare_icon_is_an_icon_theme_name() {
        const icon = Plugins.iconOf({
            icon: "firefox"
        });
        compare(icon.name, "firefox");
        compare(icon.type, "image");
    }

    function test_missing_icon_falls_back() {
        compare(Plugins.iconOf({}).name, "extension");
    }

    // An explicit iconType outranks the prefix: the prefix is a fallback for
    // plugins that never set one.
    function test_explicit_icon_type_wins() {
        compare(Plugins.iconOf({
            icon: "material:foo",
            iconType: "image"
        }).type, "image");
    }

    function test_row_carries_the_item_back_for_execution() {
        const item = {
            name: "360",
            icon: "material:equal",
            comment: "12 * 30 = 360",
            action: "copy:360"
        };
        const row = Plugins.toRow(item, "calculator", "Calculator", 0);
        compare(row.kind, "plugin");
        compare(row.label, "360");
        compare(row.comment, "12 * 30 = 360");
        compare(row.pluginId, "calculator");
        compare(row.data.action, "copy:360");
        verify(!row.disabled);
    }

    function test_row_ids_are_unique_without_item_ids() {
        const rows = Plugins.toRows([
            {
                name: "a"
            },
            {
                name: "b"
            }
        ], "p", "P");
        compare(rows.length, 2);
        verify(rows[0].id !== rows[1].id);
    }

    function test_comment_falls_back_to_the_plugin_name() {
        compare(Plugins.toRow({
            name: "x"
        }, "emoji", "Emoji", 0).comment, "Emoji");
    }

    function test_no_items_is_no_rows() {
        compare(Plugins.toRows(null, "p", "P").length, 0);
    }
}
