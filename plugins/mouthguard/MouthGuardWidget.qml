import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property var popoutService: null
    readonly property var daemon: pluginService
        ? pluginService.pluginInstances[pluginId] : null
    readonly property string mouthState: daemon ? daemon.mouthState : "inactive"

    readonly property var iconFor: ({
        "inactive": "videocam_off",
        "closed": "sentiment_satisfied",
        "open": "warning",
        "noface": "face_retouching_off",
        "paused": "pause_circle"
    })

    readonly property color stateColor: mouthState === "open"
        ? Theme.error
        : (mouthState === "closed" ? Theme.surfaceText : Theme.surfaceVariantText)

    horizontalBarPill: Component {
        StyledRect {
            width: icon.implicitWidth + Theme.spacingM * 2
            height: parent.widgetThickness
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            DankIcon {
                id: icon
                anchors.centerIn: parent
                name: root.iconFor[root.mouthState]
                size: Theme.iconSizeSmall
                color: root.stateColor
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.daemon?.toggle()
            }
        }
    }

    verticalBarPill: Component {
        StyledRect {
            width: parent.widgetThickness
            height: vicon.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            DankIcon {
                id: vicon
                anchors.centerIn: parent
                name: root.iconFor[root.mouthState]
                size: Theme.iconSizeSmall
                color: root.stateColor
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.daemon?.toggle()
            }
        }
    }
}
