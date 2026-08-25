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
        label: "Pin on startup"
        description: "Reserve screen space for the keyboard immediately, instead of only once pinned by hand"
        defaultValue: false
    }
}
