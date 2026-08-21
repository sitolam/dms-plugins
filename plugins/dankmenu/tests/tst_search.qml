import QtQuick
import QtTest
import "../Search.js" as Search

TestCase {
    name: "Search"

    function entry(label, comment, aliases, boost) {
        return {
            label: label,
            comment: comment || "",
            aliases: aliases || [],
            boost: boost || 0
        };
    }

    function test_empty_query_matches_everything_with_zero_score() {
        compare(Search.scoreText("", "anything"), 0);
    }

    function test_non_subsequence_does_not_match() {
        compare(Search.scoreText("zzz", "System"), -1);
    }

    function test_subsequence_matches() {
        verify(Search.scoreText("sst", "System Settings") > 0);
    }

    function test_prefix_beats_midword() {
        verify(Search.scoreText("re", "Reboot") > Search.scoreText("re", "Screensaver"));
    }

    function test_contiguous_beats_scattered() {
        verify(Search.scoreText("boot", "Reboot") > Search.scoreText("boot", "Big Orange Octopus Tool"));
    }

    function test_word_boundary_beats_interior() {
        verify(Search.scoreText("dns", "Set DNS") > Search.scoreText("dns", "Sedans"));
    }

    function test_shorter_target_wins_on_equal_match() {
        verify(Search.scoreText("lock", "Lock") > Search.scoreText("lock", "Lock The Screen Right Now"));
    }

    function test_case_insensitive() {
        compare(Search.scoreText("LOCK", "lock"), Search.scoreText("lock", "Lock"));
    }

    function test_label_outranks_comment() {
        const a = Search.scoreEntry("dns", entry("DNS", "network"));
        const b = Search.scoreEntry("dns", entry("Network", "DNS"));
        verify(a > b);
    }

    function test_comment_outranks_alias() {
        const a = Search.scoreEntry("wifi", entry("Network", "wifi settings"));
        const b = Search.scoreEntry("wifi", entry("Network", "", ["wifi"]));
        verify(a > b);
    }

    function test_alias_still_matches_when_label_does_not() {
        verify(Search.scoreEntry("power-menu", entry("System", "", ["power-menu"])) > 0);
    }

    function test_boost_is_added() {
        const plain = Search.scoreEntry("fire", entry("Firefox"));
        const boosted = Search.scoreEntry("fire", entry("Firefox", "", [], 10));
        compare(boosted, plain + 10);
    }

    function test_boost_does_not_rescue_a_non_match() {
        compare(Search.scoreEntry("zzz", entry("Firefox", "", [], 1000)), -1);
    }

    function test_rank_drops_non_matches_and_sorts() {
        const items = [entry("Screensaver"), entry("Reboot"), entry("Lock")];
        const out = Search.rank("re", items);
        compare(out.length, 2);
        compare(out[0].label, "Reboot");
        compare(out[1].label, "Screensaver");
    }

    function test_rank_with_empty_query_preserves_order() {
        const items = [entry("C"), entry("A"), entry("B")];
        const out = Search.rank("", items);
        compare(out.map(e => e.label), ["C", "A", "B"]);
    }

    function test_rank_ties_break_on_original_order() {
        const items = [entry("Lock"), entry("Lock")];
        items[0].id = "first";
        items[1].id = "second";
        const out = Search.rank("lock", items);
        compare(out[0].id, "first");
    }

    function test_rank_sets_score_field() {
        const out = Search.rank("lock", [entry("Lock")]);
        verify(out[0]._score > 0);
    }
}
