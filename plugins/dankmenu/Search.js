.pragma library

// Written for this plugin. DMS's own launcher scorer lives behind
// AppSearchService/DankLauncherV2 and is not reachable from a plugin, and
// reaching for it would couple the menu to the spotlight it deliberately
// replaces.

var LABEL_WEIGHT = 1.0;
var COMMENT_WEIGHT = 0.6;
var ALIAS_WEIGHT = 0.45;

var BONUS_CONTIGUOUS = 4;
var BONUS_START = 6;
var BONUS_WORD_BOUNDARY = 3;
var BONUS_FULL_PREFIX = 8;
var LENGTH_PENALTY = 0.05;

var BOUNDARY_CHARS = " \t-_./:";

// Subsequence match with position bonuses. Returns -1 when `query`'s
// characters do not appear in order in `text`.
function scoreText(query, text) {
    if (!query)
        return 0;
    if (!text)
        return -1;

    var q = query.toLowerCase();
    var t = text.toLowerCase();

    var score = 0;
    var qi = 0;
    var prev = -2;

    for (var ti = 0; ti < t.length && qi < q.length; ti++) {
        if (t.charAt(ti) !== q.charAt(qi))
            continue;

        var bonus = 1;
        if (prev === ti - 1)
            bonus += BONUS_CONTIGUOUS;
        if (ti === 0)
            bonus += BONUS_START;
        else if (BOUNDARY_CHARS.indexOf(t.charAt(ti - 1)) !== -1)
            bonus += BONUS_WORD_BOUNDARY;

        score += bonus;
        prev = ti;
        qi++;
    }

    if (qi < q.length)
        return -1;

    if (t.indexOf(q) === 0)
        score += BONUS_FULL_PREFIX;

    score -= Math.max(0, t.length - q.length) * LENGTH_PENALTY;
    return score;
}

// Best of label / comment / aliases, weighted so a label hit always outranks
// the same hit in a comment, and a comment hit outranks an alias.
function scoreEntry(query, entry) {
    if (!query)
        return 0;

    var best = -1;

    var labelScore = scoreText(query, entry.label);
    if (labelScore >= 0)
        best = Math.max(best, labelScore * LABEL_WEIGHT);

    var commentScore = scoreText(query, entry.comment || "");
    if (commentScore >= 0)
        best = Math.max(best, commentScore * COMMENT_WEIGHT);

    var aliases = entry.aliases || [];
    for (var i = 0; i < aliases.length; i++) {
        var aliasScore = scoreText(query, aliases[i]);
        if (aliasScore >= 0)
            best = Math.max(best, aliasScore * ALIAS_WEIGHT);
    }

    if (best < 0)
        return -1;

    // Frecency and similar nudges ride on top of a match; they never create
    // one, or a heavily used app would surface for a query it has no letters
    // in common with.
    return best + (entry.boost || 0);
}

function rank(query, entries) {
    var scored = [];

    for (var i = 0; i < entries.length; i++) {
        var s = scoreEntry(query, entries[i]);
        if (s < 0)
            continue;
        entries[i]._score = s;
        scored.push({
            index: i,
            score: s,
            entry: entries[i]
        });
    }

    // Decorated sort: Array.prototype.sort's stability is not something to
    // rely on across engines, and an unfiltered level must read in the order
    // the tree declares.
    scored.sort(function (a, b) {
        if (b.score !== a.score)
            return b.score - a.score;
        return a.index - b.index;
    });

    var out = [];
    for (var k = 0; k < scored.length; k++)
        out.push(scored[k].entry);
    return out;
}
