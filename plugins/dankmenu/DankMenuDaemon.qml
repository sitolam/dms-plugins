import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Modules.Plugins

PluginComponent {
    id: root

    property var popoutService: null

    // Task 11 replaces this with the bundled menu.jsonc / the menuPath
    // override. Until then it is enough tree to navigate.
    readonly property var tree: ({
            nodes: {},
            roots: [],
            aliases: {},
            orphans: []
        })

    // The window is built on first open, not at shell startup: a daemon plugin
    // is instantiated with the shell, and an unopened menu should cost nothing
    // but this handler.
    LazyLoader {
        id: windowLoader

        loading: false

        MenuWindow {
            tree: root.tree
            onClosed: windowLoader.loading = false
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
            return "DANKMENU_REFRESHED";
        }
    }
}
