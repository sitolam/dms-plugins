import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "barDropdown"

    StyledText {
        width: parent.width
        wrapMode: Text.WordWrap
        text: I18n.tr("Members are bar widgets, named by the id the bar knows them by — systemTray, clock, music, or a plugin's own id such as ambientSound. A plugin variant is written pluginId:variantId. Third-party members must be enabled plugins of type \"widget\"; DMS built-ins need no setup.\n\nA member listed here should not also sit on the bar: it would then be rendered twice. Run 'dms restart' after changing the list.")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

    ListSettingWithInput {
        settingKey: "targets"
        label: I18n.tr("Panel widgets")
        description: I18n.tr("Shown left to right, in this order.")
        defaultValue: []
        fields: [
            {
                "id": "id",
                "label": I18n.tr("Widget id"),
                "placeholder": "systemTray",
                "required": true,
                "width": 240
            }
        ]
    }

    StringSetting {
        settingKey: "icon"
        label: I18n.tr("Button icon")
        description: I18n.tr("Material Symbols name.")
        placeholder: "widgets"
        defaultValue: "widgets"
    }

    SelectionSetting {
        settingKey: "display"
        label: I18n.tr("Button contents")
        description: I18n.tr("Whether the button carries a text label beside its icon.")
        defaultValue: "icon"
        options: [
            {
                "label": I18n.tr("Icon only"),
                "value": "icon"
            },
            {
                "label": I18n.tr("Icon and label"),
                "value": "both"
            }
        ]
    }

    StringSetting {
        settingKey: "label"
        label: I18n.tr("Button label")
        description: I18n.tr("Only shown when the button contents are set to icon and label.")
        placeholder: I18n.tr("Tray")
        defaultValue: ""
    }

    ToggleSetting {
        settingKey: "showChevron"
        label: I18n.tr("Show chevron")
        description: I18n.tr("A small arrow beside the icon, marking the button as one that opens a panel.")
        defaultValue: true
    }
}
