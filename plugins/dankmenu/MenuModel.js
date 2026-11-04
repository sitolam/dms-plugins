.pragma library

// Omarchy's menu files are JSONC: comments and trailing commas, for
// Neovim-friendly editing. Qt has no JSONC reader, so strip to strict JSON
// first. Both strippers are string-aware -- a "//" inside a URL and a comma
// inside a label are data, not syntax.

function stripComments(text) {
    var out = "";
    var i = 0;
    var n = text.length;
    var inString = false;

    while (i < n) {
        var c = text.charAt(i);

        if (inString) {
            out += c;
            if (c === "\\") {
                out += text.charAt(i + 1);
                i += 2;
                continue;
            }
            if (c === '"')
                inString = false;
            i++;
            continue;
        }

        if (c === '"') {
            inString = true;
            out += c;
            i++;
            continue;
        }

        if (c === "/" && text.charAt(i + 1) === "/") {
            while (i < n && text.charAt(i) !== "\n")
                i++;
            continue;
        }

        if (c === "/" && text.charAt(i + 1) === "*") {
            i += 2;
            while (i < n && !(text.charAt(i) === "*" && text.charAt(i + 1) === "/"))
                i++;
            i += 2;
            continue;
        }

        out += c;
        i++;
    }

    return out;
}

function stripTrailingCommas(text) {
    var out = "";
    var i = 0;
    var n = text.length;
    var inString = false;

    while (i < n) {
        var c = text.charAt(i);

        if (inString) {
            out += c;
            if (c === "\\") {
                out += text.charAt(i + 1);
                i += 2;
                continue;
            }
            if (c === '"')
                inString = false;
            i++;
            continue;
        }

        if (c === '"') {
            inString = true;
            out += c;
            i++;
            continue;
        }

        if (c === ",") {
            var j = i + 1;
            while (j < n && " \t\r\n".indexOf(text.charAt(j)) !== -1)
                j++;
            var next = text.charAt(j);
            if (next === "}" || next === "]") {
                i++;
                continue;
            }
        }

        out += c;
        i++;
    }

    return out;
}

function parse(text) {
    return build(JSON.parse(stripTrailingCommas(stripComments(text))));
}

// The file's rows in declaration order, as [id, fields] pairs. Omarchy's form
// is an object keyed by id. The array form carries each id in its row instead,
// for generators that sort an object's keys -- Nix's builtins.toJSON, Go's
// encoding/json with a map, or anything piped through `jq -S` -- but keep a
// list's order.
// The pairs are not folded back into an object: an engine enumerates
// integer-like keys ("2", "10") first and ascending, which would undo the
// array's order for exactly those ids.
function rowsOf(obj) {
    var rows = [];

    if (!Array.isArray(obj)) {
        for (var key in obj)
            rows.push([key, obj[key]]);
        return rows;
    }

    var at = Object.create(null);
    for (var i = 0; i < obj.length; i++) {
        var row = obj[i];
        var id = row && typeof row === "object" ? row.id : undefined;
        // Without an id a row has no place in the tree, so the file is
        // rejected as a JSON syntax error would be.
        if (typeof id !== "string" || id === "")
            throw new Error("row " + i + " of the menu array has no string id");
        // A repeated id replaces the earlier row where it stood, as a repeated
        // key does in the object form.
        if (Object.prototype.hasOwnProperty.call(at, id)) {
            rows[at[id]][1] = row;
            continue;
        }
        at[id] = rows.length;
        rows.push([id, row]);
    }

    return rows;
}

// Dotted ids imply hierarchy: "setup.network.dns" is a child of
// "setup.network". Declaration order in the file is the display order.
function build(obj) {
    var rows = rowsOf(obj);
    var nodes = {};
    var order = [];

    for (var r = 0; r < rows.length; r++) {
        var id = rows[r][0];
        var raw = rows[r][1] || {};
        var dot = id.lastIndexOf(".");
        nodes[id] = {
            id: id,
            parent: dot === -1 ? "" : id.substring(0, dot),
            icon: raw.icon || "",
            iconFont: raw.iconFont || "",
            label: raw.label || id,
            title: raw.title || raw.label || id,
            aliases: raw.aliases || [],
            action: raw.action || "",
            target: raw.target || "",
            provider: raw.provider || "",
            when: raw.when || "",
            checked: raw.checked || "",
            disabled: raw.disabled || "",
            labelCmd: raw.labelCmd || "",
            children: []
        };
        order.push(id);
    }

    var roots = [];
    var orphans = [];

    for (var k = 0; k < order.length; k++) {
        var node = nodes[order[k]];
        if (!node.parent) {
            roots.push(node.id);
            continue;
        }
        if (nodes[node.parent]) {
            nodes[node.parent].children.push(node.id);
            continue;
        }
        // A dotted id whose parent was never declared. Surfacing it at the
        // root beats dropping it silently -- a typo in the tree stays visible.
        orphans.push(node.id);
        roots.push(node.id);
    }

    var aliases = {};
    for (var m = 0; m < order.length; m++) {
        var aliasList = nodes[order[m]].aliases;
        for (var a = 0; a < aliasList.length; a++)
            aliases[aliasList[a]] = order[m];
    }

    return {
        nodes: nodes,
        roots: roots,
        aliases: aliases,
        orphans: orphans
    };
}

function kindOf(node) {
    if (!node)
        return "submenu";
    if (node.action)
        return "action";
    if (node.target)
        return "link";
    if (node.provider)
        return "provider";
    return "submenu";
}

// "" is the root level. An unresolvable route also lands on the root; the
// caller warns.
function resolve(tree, route) {
    if (!route || route === "root")
        return "";
    if (tree.nodes[route])
        return route;
    if (tree.aliases[route])
        return tree.aliases[route];
    return "";
}

function childrenOf(tree, id) {
    var ids = id ? (tree.nodes[id] ? tree.nodes[id].children : []) : tree.roots;
    var out = [];
    for (var i = 0; i < ids.length; i++)
        out.push(tree.nodes[ids[i]]);
    return out;
}

function breadcrumb(tree, id) {
    var parts = [];
    var cur = id;
    while (cur && tree.nodes[cur]) {
        parts.unshift(tree.nodes[cur].label);
        cur = tree.nodes[cur].parent;
    }
    return parts;
}

// Everything runnable at or below `id`, depth-first in file order. Providers
// are excluded: their contents are generated at open time, not declared here.
function leavesUnder(tree, id) {
    var out = [];

    function walk(nodeId) {
        var kids = childrenOf(tree, nodeId);
        for (var i = 0; i < kids.length; i++) {
            var kind = kindOf(kids[i]);
            if (kind === "action" || kind === "link")
                out.push(kids[i]);
            else if (kind === "submenu")
                walk(kids[i].id);
        }
    }

    walk(id);
    return out;
}
