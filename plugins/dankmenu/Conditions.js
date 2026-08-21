.pragma library

var KINDS = ["when", "checked", "disabled"];

function collect(nodes) {
    var out = [];
    for (var i = 0; i < nodes.length; i++) {
        for (var k = 0; k < KINDS.length; k++) {
            var kind = KINDS[k];
            var snippet = nodes[i][kind];
            if (snippet)
                out.push({
                    id: nodes[i].id,
                    kind: kind,
                    snippet: snippet
                });
        }
    }
    return out;
}

function shellQuote(s) {
    return "'" + String(s).split("'").join("'\\''") + "'";
}

// One script per menu level, not one process per row: a level with a dozen
// conditioned rows would otherwise mean a dozen spawns every time it opens.
// The braces group the snippet so its own stdout/stderr are discarded while
// the printf that reports its status still reaches us.
function buildScript(conds) {
    var lines = [];
    for (var i = 0; i < conds.length; i++) {
        var c = conds[i];
        lines.push("{ " + c.snippet + " ; } >/dev/null 2>&1; printf '%s\\t%s\\t%s\\n' " + shellQuote(c.id) + " " + shellQuote(c.kind) + " \"$?\"");
    }
    return lines.join("\n");
}

function parseOutput(text) {
    var results = {};
    var lines = String(text).split("\n");

    for (var i = 0; i < lines.length; i++) {
        var parts = lines[i].split("\t");
        if (parts.length !== 3)
            continue;
        var id = parts[0];
        if (!results[id])
            results[id] = {};
        results[id][parts[1]] = parseInt(parts[2], 10);
    }

    return results;
}

// Omarchy's semantics: `when` hides unless it succeeds, `checked` ticks when
// it succeeds, `disabled` dims, ticks and blocks selection when it succeeds.
// Until results land, rows stay visible and unadorned -- a row that vanished
// and reappeared would be worse than one that settles a frame late.
function applyTo(node, results) {
    var r = results[node.id] || {};
    var pending = false;

    var visible = true;
    if (node.when) {
        if (r.when === undefined)
            pending = true;
        else
            visible = r.when === 0;
    }

    var checked = false;
    if (node.checked) {
        if (r.checked === undefined)
            pending = true;
        else
            checked = r.checked === 0;
    }

    var disabled = false;
    if (node.disabled) {
        if (r.disabled === undefined)
            pending = true;
        else
            disabled = r.disabled === 0;
    }

    return {
        visible: visible,
        checked: checked,
        disabled: disabled,
        pending: pending
    };
}
