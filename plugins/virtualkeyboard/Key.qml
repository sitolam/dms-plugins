import QtQuick
import qs.Common
import qs.Widgets
import "KeyShape.js" as KeyShape

StyledRect {
    id: root

    required property var keyData
    property var ydotool: null

    readonly property string keytype: keyData.keytype
    readonly property string shape: keyData.shape
    readonly property int keycode: keyData.keycode || 0
    readonly property bool isEmpty: shape === "empty"
    readonly property bool isShiftKey: !!ydotool && ydotool.shiftKeycodes.indexOf(keycode) !== -1
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
    // A light accent tint rather than a neutral grey tile -- keys pick up
    // DMS's own primary color at low alpha (same family as Theme.primaryHover),
    // so the keyboard reads as part of the theme instead of a flat grid of
    // grey blocks pasted over the blurred card.
    color: isPressed ? Theme.primaryPressed : latched ? Theme.primarySelected : Theme.withAlpha(Theme.primary, 0.08)

    DankIcon {
        anchors.centerIn: parent
        visible: root.isBackspace || root.isEnter
        name: root.isBackspace ? "backspace" : "keyboard_return"
        size: Theme.iconSize
        color: root.latched ? Theme.primary : Theme.surfaceText
    }

    // Letters skip the corner label -- shift+letter is just the uppercase
    // form, obvious without a hint. Only symbol/number keys (whose shifted
    // character isn't guessable) get one.
    readonly property bool isLetter: /^[a-zA-Z]$/.test(keyData.label)
    readonly property bool showsSecondaryLabel: !isBackspace && !isEnter && !isShiftKey && !isLetter && !!keyData.labelShift

    StyledText {
        anchors.centerIn: parent
        visible: !root.isBackspace && !root.isEnter
        text: KeyShape.labelFor(root.keyData, root.ydotool ? root.ydotool.shiftMode : 0)
        font.pixelSize: root.shape === "fn" ? Theme.fontSizeSmall : Theme.fontSizeMedium
        color: root.latched ? Theme.primary : Theme.surfaceText
    }

    // A physical keycap shows both characters at once (main centered, the
    // shifted one small in the corner) rather than only revealing it once
    // shift is actually held -- otherwise there's no way to tell `1` gives
    // `!` without pressing shift first.
    StyledText {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 3
        visible: root.showsSecondaryLabel
        text: !root.ydotool ? "" : (root.ydotool.shiftMode === 0 ? (root.keyData.labelShift || "") : root.keyData.label)
        font.pixelSize: Theme.fontSizeSmall - 2
        color: root.latched ? Theme.primary : Theme.surfaceVariantText
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
                if (root.modToggled)
                    root.ydotool.retainHeld(root.keycode)
                else
                    root.ydotool.releaseHeld(root.keycode)
            }
        }
    }
}
