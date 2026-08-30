import QtQuick
import qs.Services
import "Plugins.js" as Plugins

// DMS's `type: launcher` plugins -- calculator, emoji, and the rest -- as menu
// rows. The menu owns its own window and its own search (see AppSource.qml),
// but the launcher plugins are not spotlight's private property: PluginService
// hands out their components and AppSearchService will drive one for any caller.
// So a trigger typed here does what it does in spotlight, and a plugin
// configured with no trigger contributes to a root search the same way.
//
// Not reimplemented: the plugin instance itself. AppSearchService reuses the
// shell's persistent instance where there is one, and a plugin holding state
// between calls (a calculator's history, a running qalc process) would lose it
// against a second instance of our own.
Item {
    id: root

    readonly property bool available: typeof PluginService !== "undefined" && typeof AppSearchService !== "undefined"

    function triggers() {
        if (!available || typeof PluginService.getAllPluginTriggers !== "function")
            return {};
        return PluginService.getAllPluginTriggers() || {};
    }

    // null when the query fires no trigger, so the caller falls through to its
    // ordinary rows.
    function detect(query) {
        if (!available)
            return null;
        return Plugins.detectTrigger(query, triggers());
    }

    function nameOf(pluginId) {
        const plugin = PluginService.getLauncherPlugin ? PluginService.getLauncherPlugin(pluginId) : null;
        return (plugin && plugin.name) || pluginId;
    }

    function rowsFrom(pluginId, query) {
        if (!available)
            return [];
        try {
            const items = AppSearchService.getPluginItemsForPlugin(pluginId, query || "");
            return Plugins.toRows(items, pluginId, nameOf(pluginId));
        } catch (e) {
            console.warn("dankMenu: plugin", pluginId, "failed to produce items:", e);
            return [];
        }
    }

    // Plugins whose trigger has been cleared in DMS's settings ("always active"
    // mode). They answer every query, so they are the only plugins that may
    // appear in a search nobody prefixed.
    function untriggeredRows(query) {
        if (!available || !query || typeof PluginService.getPluginsWithEmptyTrigger !== "function")
            return [];

        const ids = PluginService.getPluginsWithEmptyTrigger() || [];
        const out = [];
        for (let i = 0; i < ids.length; i++)
            out.push.apply(out, rowsFrom(ids[i], query));
        return out;
    }

    // A launcher plugin may answer twice: the calculator's qalc engine returns
    // a "Calculating..." placeholder row and the real result once its process
    // replies. PluginService announces the second answer with
    // requestLauncherUpdate -- DMS's own launcher rebuilds its list on it
    // (Modals/DankLauncherV2/Controller.qml) -- so a caller that only rebuilds
    // on keystrokes shows the placeholder forever.
    signal itemsUpdated(string pluginId)

    Connections {
        target: root.available ? PluginService : null
        function onRequestLauncherUpdate(pluginId) {
            root.itemsUpdated(pluginId);
        }
    }

    function run(row) {
        if (!available)
            return false;
        try {
            return AppSearchService.executePluginItem(row.data, row.pluginId) === true;
        } catch (e) {
            console.warn("dankMenu: plugin", row.pluginId, "failed to execute item:", e);
            return false;
        }
    }
}
