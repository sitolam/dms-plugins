import QtQuick
import QtTest
import "../MenuModel.js" as MenuModel

// MenuModel.js has no QML types, no Theme and no Quickshell imports, so the
// exact file the plugin loads is exercised here rather than a copy.
TestCase {
    name: "MenuModel"

    function test_strip_line_comment() {
        const src = '{\n  // a comment\n  "a": {"label":"A"}\n}';
        compare(JSON.parse(MenuModel.stripComments(src)).a.label, "A");
    }

    function test_strip_block_comment() {
        const src = '{ /* gone\n still gone */ "a": {"label":"A"} }';
        compare(JSON.parse(MenuModel.stripComments(src)).a.label, "A");
    }

    function test_keeps_double_slash_inside_string() {
        const src = '{ "a": {"target":"https://omarchy.org/manual/"} }';
        const out = JSON.parse(MenuModel.stripComments(src));
        compare(out.a.target, "https://omarchy.org/manual/");
    }

    function test_keeps_escaped_quote_inside_string() {
        const src = '{ "a": {"label":"say \\"hi\\" // now"} }';
        const out = JSON.parse(MenuModel.stripComments(src));
        compare(out.a.label, 'say "hi" // now');
    }

    function test_strip_trailing_comma_object_and_array() {
        const src = '{ "a": {"aliases":["x","y",],}, }';
        const out = JSON.parse(MenuModel.stripTrailingCommas(src));
        compare(out.a.aliases.length, 2);
    }

    function test_keeps_comma_inside_string() {
        const src = '{ "a": {"label":"one, two"} }';
        const out = JSON.parse(MenuModel.stripTrailingCommas(src));
        compare(out.a.label, "one, two");
    }

    property string sample: '{\n' + '  // root\n' + '  "system": {"icon":"","label":"System","aliases":["power-menu"]},\n' + '  "system.lock": {"icon":"","label":"Lock","action":"loginctl lock-session"},\n' + '  "system.reboot": {"label":"Reboot","action":"systemctl reboot","when":"true"},\n' + '  "learn": {"label":"Learn"},\n' + '  "learn.niri": {"label":"Niri","target":"https://github.com/YaLTeR/niri/wiki"},\n' + '  "apps": {"label":"Apps","provider":"apps"},\n' + '}'

    function test_build_roots_in_file_order() {
        const tree = MenuModel.parse(sample);
        compare(tree.roots, ["system", "learn", "apps"]);
    }

    function test_build_children_from_dotted_ids() {
        const tree = MenuModel.parse(sample);
        compare(tree.nodes["system"].children, ["system.lock", "system.reboot"]);
    }

    function test_kind_inference() {
        const tree = MenuModel.parse(sample);
        compare(MenuModel.kindOf(tree.nodes["system.lock"]), "action");
        compare(MenuModel.kindOf(tree.nodes["learn.niri"]), "link");
        compare(MenuModel.kindOf(tree.nodes["apps"]), "provider");
        compare(MenuModel.kindOf(tree.nodes["learn"]), "submenu");
    }

    function test_resolve_by_id_alias_and_root() {
        const tree = MenuModel.parse(sample);
        compare(MenuModel.resolve(tree, "system.lock"), "system.lock");
        compare(MenuModel.resolve(tree, "power-menu"), "system");
        compare(MenuModel.resolve(tree, "root"), "");
        compare(MenuModel.resolve(tree, "nope"), "");
    }

    function test_children_of_root_are_the_roots() {
        const tree = MenuModel.parse(sample);
        const kids = MenuModel.childrenOf(tree, "");
        compare(kids.length, 3);
        compare(kids[0].label, "System");
    }

    function test_breadcrumb() {
        const tree = MenuModel.parse(sample);
        compare(MenuModel.breadcrumb(tree, "system.lock"), ["System", "Lock"]);
        compare(MenuModel.breadcrumb(tree, ""), []);
    }

    function test_leaves_under_is_recursive_and_skips_submenus() {
        const tree = MenuModel.parse(sample);
        const leaves = MenuModel.leavesUnder(tree, "").map(n => n.id);
        compare(leaves, ["system.lock", "system.reboot", "learn.niri"]);
    }

    function test_defaults_are_empty_strings_not_undefined() {
        const tree = MenuModel.parse(sample);
        compare(tree.nodes["learn"].action, "");
        compare(tree.nodes["learn"].when, "");
        compare(tree.nodes["learn"].aliases.length, 0);
    }

    function test_orphan_becomes_a_root_and_is_recorded() {
        const tree = MenuModel.parse('{ "a.b": {"label":"Orphan"} }');
        compare(tree.roots, ["a.b"]);
        compare(tree.orphans, ["a.b"]);
    }

    // The array form: each row carries its id, and the array sets the order.
    property string arraySample: '[\n' + '  // root\n' + '  {"id":"system","label":"System","aliases":["power-menu"]},\n' + '  {"id":"system.suspend","label":"Suspend","action":"systemctl suspend"},\n' + '  {"id":"apps","label":"Apps","provider":"apps"},\n' + '  {"id":"system.lock","label":"Lock","action":"loginctl lock-session"},\n' + ']'

    function test_array_builds_the_same_tree_as_the_object() {
        const obj = JSON.parse(MenuModel.stripTrailingCommas(MenuModel.stripComments(sample)));
        const rows = [];
        for (const id in obj) {
            const row = Object.assign({}, obj[id]);
            row.id = id;
            rows.push(row);
        }
        compare(MenuModel.build(rows), MenuModel.build(obj));
    }

    function test_array_order_is_display_order() {
        const tree = MenuModel.parse(arraySample);
        compare(tree.roots, ["system", "apps"]);
        compare(tree.nodes["system"].children, ["system.suspend", "system.lock"]);
        compare(MenuModel.resolve(tree, "power-menu"), "system");
    }

    function test_array_order_holds_for_numeric_ids() {
        const tree = MenuModel.parse('[{"id":"10"},{"id":"2"},{"id":"b"},{"id":"a"}]');
        compare(tree.roots, ["10", "2", "b", "a"]);
    }

    function test_array_nests_by_dotted_id() {
        const tree = MenuModel.parse('[{"id":"setup","label":"Setup"},{"id":"setup.network","label":"Network"},' + '{"id":"setup.network.dns","label":"DNS","action":"true"}]');
        compare(tree.roots, ["setup"]);
        compare(tree.nodes["setup.network"].parent, "setup");
        compare(tree.nodes["setup.network"].children, ["setup.network.dns"]);
        compare(MenuModel.breadcrumb(tree, "setup.network.dns"), ["Setup", "Network", "DNS"]);
    }

    function test_array_orphan_becomes_a_root_and_is_recorded() {
        const tree = MenuModel.parse('[{"id":"a","label":"A"},{"id":"b.c","label":"Orphan"}]');
        compare(tree.roots, ["a", "b.c"]);
        compare(tree.orphans, ["b.c"]);
    }

    function test_array_repeated_id_replaces_the_row_in_place() {
        const tree = MenuModel.parse('[{"id":"a","label":"First"},{"id":"b"},{"id":"a","label":"Second"}]');
        compare(tree.roots, ["a", "b"]);
        compare(tree.nodes["a"].label, "Second");
    }

    function test_array_row_without_a_string_id_rejects_the_file() {
        const bad = ['[{"label":"No id"}]', '[{"id":3}]', '[{"id":""}]', '[null]', '["system"]', '[[]]', '[{"id":"a"},{"label":"No id"}]'];
        for (let i = 0; i < bad.length; i++) {
            let error = "";
            try {
                MenuModel.parse(bad[i]);
            } catch (e) {
                error = String(e);
            }
            verify(error.indexOf("of the menu array has no string id") !== -1, bad[i]);
        }
    }

    function test_empty_array_is_an_empty_menu() {
        const tree = MenuModel.parse("[]");
        compare(tree.roots, []);
        compare(tree.orphans, []);
    }
}
