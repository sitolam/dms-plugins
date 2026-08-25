import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins

PluginComponent {
    id: root

    readonly property bool pinnedOnStartup: pluginService ? pluginService.loadPluginData(pluginId, "pinnedOnStartup", false) : false
    readonly property bool keyboardOpen: windowLoader.item ? windowLoader.item.keyboardVisible : false

    Ydotool {
        id: ydotool
    }

    LazyLoader {
        id: windowLoader
        loading: false

        KeyboardWindow {
            ydotool: ydotool
            pinned: root.pinnedOnStartup
            onKeyboardClosed: {
                windowLoader.loading = false
                PluginService.setGlobalVar(root.pluginId, "open", false)
                ydotool.releaseAllKeys()
            }
        }
    }

    function openKeyboard() {
        windowLoader.loading = true
        windowLoader.item.show()
        PluginService.setGlobalVar(root.pluginId, "open", true)
    }

    function closeKeyboard() {
        if (windowLoader.item)
            windowLoader.item.hide()
    }

    Connections {
        target: PluginService
        function onGlobalVarChanged(pluginId, varName) {
            if (pluginId !== root.pluginId || varName !== "open")
                return
            const wantOpen = PluginService.getGlobalVar(root.pluginId, "open", false)
            if (wantOpen && !root.keyboardOpen)
                root.openKeyboard()
            else if (!wantOpen && root.keyboardOpen)
                root.closeKeyboard()
        }
    }

    IpcHandler {
        target: "virtualKeyboard"

        function toggle(): string {
            if (root.keyboardOpen) {
                root.closeKeyboard()
                return "VIRTUALKEYBOARD_CLOSED"
            }
            root.openKeyboard()
            return "VIRTUALKEYBOARD_OPENED"
        }

        function open(): string {
            root.openKeyboard()
            return "VIRTUALKEYBOARD_OPENED"
        }

        function close(): string {
            root.closeKeyboard()
            return "VIRTUALKEYBOARD_CLOSED"
        }
    }
}
