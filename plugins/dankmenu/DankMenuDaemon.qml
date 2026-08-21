import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Modules.Plugins
import "MenuModel.js" as MenuModel

PluginComponent {
    id: root

    property var popoutService: null

    // "" means the tree bundled with the plugin. A Nix-managed config points
    // this at a generated file; a hand install leaves it alone and gets the
    // default.
    readonly property string menuPath: (pluginData && pluginData.menuPath) || ""

    property var tree: ({
            nodes: {},
            roots: [],
            aliases: {},
            orphans: []
        })

    FileView {
        id: menuFile

        path: root.menuPath !== "" ? root.menuPath : Qt.resolvedUrl("menu.jsonc").toString().replace("file://", "")
        watchChanges: true

        onFileChanged: reload()

        onLoaded: {
            try {
                root.tree = MenuModel.parse(text());
                if (root.tree.orphans.length > 0)
                    console.warn("dankMenu: orphaned ids in menu file:", root.tree.orphans.join(", "));
            } catch (e) {
                console.warn("dankMenu: cannot parse menu file", path, "-", e);
            }
        }

        onLoadFailed: console.warn("dankMenu: cannot read menu file", path)
    }

    // The window is built on first open, not at shell startup: a daemon plugin
    // is instantiated with the shell, and an unopened menu should cost nothing
    // but this handler.
    LazyLoader {
        id: windowLoader

        loading: false

        MenuWindow {
            tree: root.tree
            onMenuClosed: windowLoader.loading = false
        }
    }

    readonly property bool menuVisible: windowLoader.item ? windowLoader.item.menuVisible : false

    function openAt(route) {
        windowLoader.loading = true;
        windowLoader.item.openAt(route || "root");
    }

    function closeMenu() {
        if (windowLoader.item)
            windowLoader.item.closeMenu();
    }

    IpcHandler {
        target: "dankMenu"

        function toggle(route: string): string {
            if (root.menuVisible) {
                root.closeMenu();
                return "DANKMENU_CLOSED";
            }
            root.openAt(route);
            return "DANKMENU_OPENED: " + (route || "root");
        }

        function open(route: string): string {
            root.openAt(route);
            return "DANKMENU_OPENED: " + (route || "root");
        }

        function close(): string {
            root.closeMenu();
            return "DANKMENU_CLOSED";
        }

        function refresh(): string {
            menuFile.reload();
            return "DANKMENU_REFRESHED";
        }
    }
}
