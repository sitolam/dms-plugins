import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins

PluginComponent {
    id: root

    readonly property bool pinnedOnStartup: pluginService ? pluginService.loadPluginData(pluginId, "pinnedOnStartup", false) : false
    property bool pinned: pinnedOnStartup
    readonly property bool keyboardOpen: (dockedLoader.item && dockedLoader.item.keyboardVisible) || (floatingLoader.item && floatingLoader.item.keyboardVisible)

    // Not named `ydotool`: see the comment below on why that collides with
    // a same-named property being initialized on the windows that consume
    // it, silently breaking every level of the hand-off.
    Ydotool {
        id: ydotoolService
    }

    // `active`, not `loading`: `loading` only starts a background load and
    // does nothing once the item exists, so it can never take a window back
    // down. `active` is the property that creates and destroys the item, and
    // it loads synchronously, which openKeyboard() relies on when it touches
    // `item` on the line right after.
    LazyLoader {
        id: dockedLoader
        active: false

        KeyboardWindow {
            ydotool: ydotoolService
            onPinRequested: {
                root.pinned = true
                Qt.callLater(root.switchWindowMode)
            }
            onKeyboardClosed: {
                PluginService.setGlobalVar(root.pluginId, "open", false)
                ydotoolService.releaseAllKeys()
                Qt.callLater(root.releaseIdleWindows)
            }
        }
    }

    LazyLoader {
        id: floatingLoader
        active: false

        FloatingKeyboardWindow {
            ydotool: ydotoolService
            onUnpinRequested: {
                root.pinned = false
                Qt.callLater(root.switchWindowMode)
            }
            onKeyboardClosed: {
                PluginService.setGlobalVar(root.pluginId, "open", false)
                ydotoolService.releaseAllKeys()
                Qt.callLater(root.releaseIdleWindows)
            }
        }
    }

    // Pin/unpin swaps which window class is showing the keyboard (docked
    // PanelWindow vs floating FloatingWindow -- two different Quickshell
    // window types, not a property toggle on one window). Unloading the
    // loader that owns the window currently running *its own* pinRequested/
    // unpinRequested handler needs to happen after that handler returns, not
    // from inside it -- hence the Qt.callLater at each call site landing
    // here rather than touching the loaders directly.
    function switchWindowMode() {
        // The window carrying the latched-modifier buttons is about to be
        // destroyed, so anything it is holding down has to come up first.
        ydotoolService.releaseAllKeys()
        dockedLoader.active = false
        floatingLoader.active = false
        openKeyboard()
    }

    // Closing frees the window, but only once it is certain nothing reopened
    // it in the meantime -- this runs a tick after keyboardClosed, and a
    // toggle-spam or close-then-open in that gap would otherwise destroy the
    // window that was just created.
    function releaseIdleWindows() {
        if (root.keyboardOpen)
            return
        dockedLoader.active = false
        floatingLoader.active = false
    }

    function openKeyboard() {
        if (root.pinned) {
            floatingLoader.active = true
            floatingLoader.item.show()
        } else {
            dockedLoader.active = true
            dockedLoader.item.show()
        }
        PluginService.setGlobalVar(root.pluginId, "open", true)
    }

    function closeKeyboard() {
        if (dockedLoader.item)
            dockedLoader.item.hide()
        if (floatingLoader.item)
            floatingLoader.item.hide()
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
