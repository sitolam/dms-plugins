import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Plugins

PluginComponent {
    id: root

    property var popoutService: null
    property bool active: false
    property string mouthState: "inactive"

    function toggle() {
        active = !active
        mouthState = active ? "closed" : "inactive"
    }

    // Register this instance so the widget surface — which is created once per
    // bar, per monitor — can find the single daemon rather than each spawning
    // its own detector.
    Component.onCompleted: {
        if (!pluginService) return
        const next = Object.assign({}, pluginService.pluginInstances)
        next[pluginId] = root
        pluginService.pluginInstances = next
    }

    Component.onDestruction: {
        if (!pluginService) return
        if (pluginService.pluginInstances[pluginId] !== root) return
        const next = Object.assign({}, pluginService.pluginInstances)
        delete next[pluginId]
        pluginService.pluginInstances = next
    }
}
