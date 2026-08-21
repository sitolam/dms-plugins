import QtQuick
import qs.Common
import qs.Widgets

ListView {
    id: root

    // rows: [{ id, label, icon, kind, comment, checked, disabled }]
    property var rows: []
    property int iconSize: 22

    signal activated(var row)

    model: rows
    clip: true
    currentIndex: 0
    // The window owns key handling: the search field has focus, so the list
    // must not also react to arrow keys.
    keyNavigationEnabled: false

    delegate: Rectangle {
        id: delegateRoot

        required property int index
        required property var modelData

        width: ListView.view.width
        height: 44
        radius: Theme.cornerRadius
        color: index === root.currentIndex ? Theme.primary : "transparent"
        opacity: modelData.disabled ? 0.45 : 1

        readonly property color contentColor: index === root.currentIndex ? Theme.surface : Theme.surfaceText
        readonly property color subtleColor: index === root.currentIndex ? Theme.surface : Theme.surfaceVariantText

        MouseArea {
            anchors.fill: parent
            enabled: !delegateRoot.modelData.disabled
            onClicked: {
                root.currentIndex = delegateRoot.index;
                root.activated(delegateRoot.modelData);
            }
        }

        Row {
            anchors.left: parent.left
            anchors.right: chevron.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Theme.spacingM
            anchors.rightMargin: Theme.spacingS
            spacing: Theme.spacingM

            // Two renderers, because the two kinds of icon are unrelated:
            // menu rows name a Material Symbols glyph ("school", "wifi"),
            // while app rows name an icon-theme entry ("firefox"). DankIcon
            // only draws the former -- handing it a theme name renders
            // nothing at all.
            Item {
                anchors.verticalCenter: parent.verticalCenter
                visible: delegateRoot.modelData.icon !== ""
                width: visible ? root.iconSize : 0
                height: root.iconSize

                DankIcon {
                    anchors.centerIn: parent
                    visible: delegateRoot.modelData.kind !== "app"
                    name: delegateRoot.modelData.icon
                    size: Theme.fontSizeLarge
                    color: delegateRoot.contentColor
                }

                AppIconRenderer {
                    anchors.fill: parent
                    visible: delegateRoot.modelData.kind === "app"
                    iconValue: delegateRoot.modelData.icon
                    iconSize: root.iconSize
                    fallbackText: delegateRoot.modelData.label.length > 0 ? delegateRoot.modelData.label.charAt(0).toUpperCase() : "?"
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - (delegateRoot.modelData.icon !== "" ? root.iconSize + Theme.spacingM : 0)

                StyledText {
                    width: parent.width
                    text: delegateRoot.modelData.label + (delegateRoot.modelData.checked ? "  ✓" : "")
                    color: delegateRoot.contentColor
                    font.pixelSize: Theme.fontSizeMedium
                    elide: Text.ElideRight
                }

                StyledText {
                    width: parent.width
                    visible: delegateRoot.modelData.comment !== ""
                    text: delegateRoot.modelData.comment
                    color: delegateRoot.subtleColor
                    font.pixelSize: Theme.fontSizeSmall
                    elide: Text.ElideRight
                }
            }
        }

        // A submenu advertises that Enter goes deeper rather than doing
        // something irreversible.
        DankIcon {
            id: chevron

            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            visible: delegateRoot.modelData.kind === "submenu" || delegateRoot.modelData.kind === "provider"
            width: visible ? implicitWidth : 0
            name: "chevron_right"
            size: Theme.fontSizeMedium
            color: delegateRoot.subtleColor
        }
    }
}
