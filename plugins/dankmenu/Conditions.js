.pragma library

// `labelCmd` is deliberately last: it is the only kind whose *output* is used
// rather than its exit status, and collect()'s order is the order the shell
// script runs in, so a label is computed after the conditions that decide
// whether its row is shown at all.
var KINDS = ["when", "checked", "disabled", "labelCmd"];

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
        if (c.kind === "labelCmd") {
            // The value has to survive as one field of a tab-separated record,
            // so it is clamped to a single line and stripped of tabs. stderr is
            // dropped rather than merged: a warning from the snippet would
            // otherwise end up rendered as the row's label.
            lines.push("__dm=$({ " + c.snippet + " ; } 2>/dev/null | head -n1 | tr -d '\\t\\r\\n'); printf '%s\\t%s\\t%s\\n' " + shellQuote(c.id) + " " + shellQuote(c.kind) + " \"$__dm\"");
        } else {
            lines.push("{ " + c.snippet + " ; } >/dev/null 2>&1; printf '%s\\t%s\\t%s\\n' " + shellQuote(c.id) + " " + shellQuote(c.kind) + " \"$?\"");
        }
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
        // Every kind but labelCmd reports an exit status; labelCmd reports the
        // text itself, which may legitimately be empty.
        results[id][parts[1]] = parts[1] === "labelCmd" ? parts[2] : parseInt(parts[2], 10);
    }

    return results;
}

// Omarchy's semantics: `when` hides unless it succeeds, `checked` ticks when
// it succeeds, `disabled` dims, ticks and blocks selection when it succeeds.
// `labelCmd` is ours: its stdout replaces the row's label, which is the only
// way to put a live value (a temperature, a container's memory use) in front of
// someone -- the menu tree itself is a static file. It is a snapshot taken when
// the level is opened, exactly like the other three, not a running meter.
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

    var label = "";
    if (node.labelCmd) {
        if (r.labelCmd === undefined)
            pending = true;
        else
            label = r.labelCmd;
    }

    return {
        visible: visible,
        checked: checked,
        disabled: disabled,
        label: label,
        pending: pending
    };
}
