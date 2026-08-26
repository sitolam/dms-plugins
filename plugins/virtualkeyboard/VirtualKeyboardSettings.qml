import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "virtualKeyboard"

    StyledText {
        width: parent.width
        text: "Toggle the keyboard with `dms ipc call virtualKeyboard toggle` (bindable to a compositor keybind), or add the optional bar pill to DankBar."
        font.pixelSize: Theme.fontSizeMedium
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    ToggleSetting {
        settingKey: "pinnedOnStartup"
        label: "Float by default"
        description: "Open the keyboard as a movable floating window rather than docked at the bottom of the screen"
        defaultValue: false
    }
}
