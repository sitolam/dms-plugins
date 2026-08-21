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
}
