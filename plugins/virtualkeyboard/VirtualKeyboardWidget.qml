import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import qs.Services

PluginComponent {
    id: root

    property bool keyboardOpen: PluginService.getGlobalVar(root.pluginId, "open", false)

    Connections {
        target: PluginService
        function onGlobalVarChanged(pluginId, varName) {
            if (pluginId === root.pluginId && varName === "open")
                root.keyboardOpen = PluginService.getGlobalVar(root.pluginId, "open", false)
        }
    }

    pillClickAction: () => {
        PluginService.setGlobalVar(root.pluginId, "open", !root.keyboardOpen)
    }

    horizontalBarPill: Component {
        StyledRect {
            width: parent.widgetThickness
            height: parent.widgetThickness
            radius: Theme.cornerRadius
            color: root.keyboardOpen ? Theme.primaryContainer : Theme.surfaceContainerHigh

            DankIcon {
                anchors.centerIn: parent
                name: "keyboard"
                size: root.iconSize
                color: root.keyboardOpen ? Theme.primary : Theme.surfaceText
            }
        }
    }

    verticalBarPill: Component {
        StyledRect {
            width: parent.widgetThickness
            height: parent.widgetThickness
            radius: Theme.cornerRadius
            color: root.keyboardOpen ? Theme.primaryContainer : Theme.surfaceContainerHigh

            DankIcon {
                anchors.centerIn: parent
                name: "keyboard"
                size: root.iconSize
                color: root.keyboardOpen ? Theme.primary : Theme.surfaceText
            }
        }
    }
}
