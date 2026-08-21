import QtQuick
import qs.Common
import qs.Widgets

FocusScope {
    id: root

    property var pluginService: null

    function save(key, value) {
        if (pluginService)
            pluginService.savePluginData("dankMenu", key, value);
    }

    function load(key, fallback) {
        return pluginService ? pluginService.loadPluginData("dankMenu", key, fallback) : fallback;
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Theme.spacingM

        StyledText {
            text: "Menu file"
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeMedium
        }

        StyledText {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Absolute path to a JSONC menu tree. Leave empty to use the tree bundled with the plugin. " + "The file is watched, so edits apply without restarting the shell.\n\n" + "On NixOS this is set from your configuration, and edits made here will not stick."
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
        }

        Rectangle {
            width: parent.width
            height: 36
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            TextInput {
                id: pathInput

                anchors.fill: parent
                anchors.leftMargin: Theme.spacingM
                anchors.rightMargin: Theme.spacingM
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeMedium
                clip: true
                text: root.load("menuPath", "")
                onEditingFinished: root.save("menuPath", text)

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: pathInput.text === ""
                    text: "(bundled menu.jsonc)"
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeMedium
                }
            }
        }
    }
}
