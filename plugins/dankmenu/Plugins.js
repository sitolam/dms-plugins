.pragma library

// Launcher-plugin glue, kept free of QML types so the tests exercise this file
// rather than a copy. PluginSource.qml is the thin shell that talks to
// PluginService and AppSearchService; everything decidable without them --
// which trigger a query fires, what a plugin item looks like as a menu row --
// is decided here.

// Longest trigger wins. DMS's own detector walks the trigger map in whatever
// order the engine yields keys, so with both "=" and "==" registered the match
// is a coin toss; here "==" always beats "=" for a query starting "==".
function detectTrigger(query, triggers) {
    if (!query || !triggers)
        return null;

    var best = null;
    for (var trigger in triggers) {
        if (!trigger || !triggers[trigger])
            continue;
        if (query.indexOf(trigger) !== 0)
            continue;
        if (best && best.trigger.length >= trigger.length)
            continue;
        best = {
            trigger: trigger,
            pluginId: triggers[trigger],
            query: query.substring(trigger.length).trim()
        };
    }
    return best;
}

// DMS prefixes a plugin icon with the renderer it wants: "material:calculate"
// is a Material Symbols glyph, "unicode:π" is literal text, and anything else
// (or an explicit "image:") is an icon-theme name. MenuList carries the type
// through because the two renderers are unrelated -- handing an icon-theme name
// to DankIcon draws nothing at all.
function iconOf(item) {
    var raw = (item && item.icon) || "extension";
    var type = (item && item.iconType) || "";

    if (raw.indexOf("unicode:") === 0)
        return { name: raw.substring(8), type: type || "unicode" };
    if (raw.indexOf("material:") === 0)
        return { name: raw.substring(9), type: type || "material" };
    if (raw.indexOf("image:") === 0)
        return { name: raw.substring(6), type: type || "image" };
    return { name: raw, type: type || "image" };
}

// A menu row out of a plugin item. `data` is the item verbatim: executeItem
// takes the plugin's own object back, not our projection of it.
function toRow(item, pluginId, pluginName, index) {
    var icon = iconOf(item);
    return {
        id: "plugin:" + pluginId + ":" + (item.id || item.name || index),
        label: item.name || "",
        icon: icon.name,
        iconType: icon.type,
        comment: item.comment || item.description || pluginName || "",
        kind: "plugin",
        aliases: item.keywords || [],
        checked: false,
        disabled: false,
        pluginId: pluginId,
        data: item
    };
}

function toRows(items, pluginId, pluginName) {
    var out = [];
    for (var i = 0; i < (items || []).length; i++)
        out.push(toRow(items[i], pluginId, pluginName, i));
    return out;
}
