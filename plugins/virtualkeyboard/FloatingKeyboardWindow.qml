import QtQuick
import Quickshell
import qs.Common

FloatingWindow {
    id: root

    required property var ydotool
    property bool keyboardVisible: false

    signal keyboardClosed
    // Pin clicked while floating: hand back to the daemon to close this
    // window and reopen the docked PanelWindow variant.
    signal unpinRequested

    // `visible` is assigned, never bound: closing the window from the
    // titlebar makes the compositor write `visible` itself, which would
    // destroy a binding here and leave every later show()/hide() with no
    // effect on screen -- a floating keyboard that can't be dismissed again.
    function show() {
        keyboardVisible = true
        root.visible = true
    }

    function hide() {
        if (!keyboardVisible)
            return
        keyboardVisible = false
        root.visible = false
        keyboardClosed()
    }

    title: "Virtual Keyboard"
    color: "transparent"
    visible: false
    width: card.width
    height: card.height
    minimumSize: Qt.size(card.width, card.height)
    maximumSize: Qt.size(card.width, card.height)

    onClosed: hide()

    Keys.onEscapePressed: root.hide()

    KeyboardCard {
        id: card

        anchors.centerIn: parent
        ydotool: root.ydotool
        pinned: true
        targetWindow: root
        onPinClicked: root.unpinRequested()
        onHideClicked: root.hide()
    }
}
