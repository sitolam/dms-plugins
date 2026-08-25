import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Widgets

PanelWindow {
    id: root

    required property var ydotool
    property bool keyboardVisible: false
    property bool pinned: false

    signal keyboardClosed

    function show() {
        keyboardVisible = true
    }

    function hide() {
        keyboardVisible = false
        keyboardClosed()
    }

    visible: keyboardVisible
    color: "transparent"

    anchors {
        bottom: true
        left: true
        right: true
    }

    exclusiveZone: root.pinned ? implicitHeight - Theme.spacingL : 0
    implicitWidth: card.width
    implicitHeight: card.height + Theme.spacingL * 2

    WlrLayershell.namespace: "dms:plugins:virtualKeyboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.keyboardVisible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    mask: Region {
        item: card
    }

    WindowBlur {
        targetWindow: root
        blurX: card.x
        blurY: card.y
        blurWidth: root.keyboardVisible ? card.width : 0
        blurHeight: root.keyboardVisible ? card.height : 0
        blurRadius: Theme.cornerRadius
    }

    FocusScope {
        anchors.fill: parent
        focus: root.keyboardVisible

        Keys.onEscapePressed: root.hide()

        StyledRect {
            id: card

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.spacingL
            width: content.implicitWidth + Theme.spacingL * 2
            height: content.implicitHeight + Theme.spacingL * 2
            radius: Theme.cornerRadius
            color: Theme.readableSurface
            border.width: 1
            border.color: Theme.outlineVariant

            RowLayout {
                id: content
                anchors.centerIn: parent
                spacing: Theme.spacingM

                ColumnLayout {
                    spacing: Theme.spacingXS

                    DankActionButton {
                        iconName: "keep"
                        iconColor: root.pinned ? Theme.primary : Theme.surfaceText
                        tooltipText: root.pinned ? "Unpin" : "Pin"
                        onClicked: root.pinned = !root.pinned
                    }

                    DankActionButton {
                        iconName: "keyboard_hide"
                        tooltipText: "Hide"
                        onClicked: root.hide()
                    }
                }

                Rectangle {
                    Layout.fillHeight: true
                    Layout.topMargin: Theme.spacingM
                    Layout.bottomMargin: Theme.spacingM
                    implicitWidth: 1
                    color: Theme.outlineVariant
                }

                KeyboardLayout {
                    ydotool: root.ydotool
                }
            }
        }
    }
}
