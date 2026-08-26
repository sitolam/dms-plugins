import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Widgets

PanelWindow {
    id: root

    required property var ydotool
    property bool keyboardVisible: false

    signal keyboardClosed
    // Pin clicked while docked: this window has no way to become a
    // FloatingWindow itself (different Quickshell window class entirely),
    // so it asks the daemon to close this one and open the floating variant.
    signal pinRequested

    function show() {
        keyboardVisible = true
    }

    function hide() {
        if (!keyboardVisible)
            return
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

    exclusiveZone: 0
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

        KeyboardCard {
            id: card

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.spacingL
            ydotool: root.ydotool
            pinned: false
            onPinClicked: root.pinRequested()
            onHideClicked: root.hide()
        }
    }
}
