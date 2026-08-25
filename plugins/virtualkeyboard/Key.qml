import QtQuick
import qs.Common
import qs.Widgets
import "KeyShape.js" as KeyShape

StyledRect {
    id: root

    required property var keyData
    required property var ydotool

    readonly property string keytype: keyData.keytype
    readonly property string shape: keyData.shape
    readonly property int keycode: keyData.keycode || 0
    readonly property bool isEmpty: shape === "empty"
    readonly property bool isShiftKey: ydotool.shiftKeycodes.indexOf(keycode) !== -1
    readonly property bool isBackspace: keyData.label === "Backspace"
    readonly property bool isEnter: keyData.label === "Enter"
    readonly property bool latched: (isShiftKey && ydotool.shiftMode > 0) || (keytype === "modkey" && !isShiftKey && modToggled)

    // Sticky modkeys (Ctrl/Alt) latch on the first tap and release on the
    // second, same as upstream's OskKey "modkey" branch.
    property bool modToggled: false
    property bool isPressed: false

    readonly property real baseWidth: 45
    readonly property real baseHeight: 45

    width: baseWidth * KeyShape.widthMultiplier(shape)
    height: baseHeight * KeyShape.heightMultiplier(shape)
    visible: !isEmpty
    enabled: !isEmpty
    radius: Theme.cornerRadius
    color: isPressed ? Theme.primaryPressed : latched ? Theme.primaryContainer : Theme.surfaceContainerHigh

    DankIcon {
        anchors.centerIn: parent
        visible: root.isBackspace || root.isEnter
        name: root.isBackspace ? "backspace" : "keyboard_return"
        size: Theme.iconSize
        color: root.latched ? Theme.primary : Theme.surfaceText
    }

    StyledText {
        anchors.centerIn: parent
        visible: !root.isBackspace && !root.isEnter
        text: KeyShape.labelFor(root.keyData, root.isShiftKey ? root.ydotool.shiftMode : 0)
        font.pixelSize: root.shape === "fn" ? Theme.fontSizeSmall : Theme.fontSizeMedium
        color: root.latched ? Theme.primary : Theme.surfaceText
    }

    Timer {
        id: capsLockTimer
        interval: 300
        property bool hasStarted: false
        property bool canCaps: false
        onTriggered: canCaps = false
        function startWaiting() {
            hasStarted = true
            canCaps = true
            restart()
        }
    }

    Connections {
        target: root.ydotool
        function onShiftModeChanged() {
            if (root.ydotool.shiftMode === 0)
                capsLockTimer.hasStarted = false
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: !root.isEmpty
        onPressed: {
            root.isPressed = true
            root.ydotool.press(root.keycode)
            if (root.isShiftKey && root.ydotool.shiftMode === 0)
                root.ydotool.shiftMode = 1
        }
        onReleased: {
            root.isPressed = false
            if (root.keytype === "normal") {
                root.ydotool.release(root.keycode)
                if (root.ydotool.shiftMode === 1)
                    root.ydotool.releaseShiftKeys()
            } else if (root.isShiftKey) {
                if (root.ydotool.shiftMode === 1) {
                    if (!capsLockTimer.hasStarted)
                        capsLockTimer.startWaiting()
                    else if (capsLockTimer.canCaps)
                        root.ydotool.shiftMode = 2
                    else
                        root.ydotool.releaseShiftKeys()
                } else if (root.ydotool.shiftMode === 2) {
                    root.ydotool.releaseShiftKeys()
                }
            } else if (root.keytype === "modkey") {
                root.modToggled = !root.modToggled
                if (!root.modToggled)
                    root.ydotool.release(root.keycode)
            }
        }
    }
}
