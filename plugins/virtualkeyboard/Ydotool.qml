import QtQuick
import Quickshell.Io

Item {
    id: root

    // 0 = plain, 1 = shift held (single tap, released after the next normal
    // key or a second shift tap outside the caps-lock window), 2 = caps-lock
    // latched (second shift tap within the window).
    property int shiftMode: 0
    readonly property var shiftKeycodes: [42, 54]

    function press(keycode) {
        spawn(keycode + ":1")
    }

    function release(keycode) {
        spawn(keycode + ":0")
    }

    function releaseShiftKeys() {
        root.shiftMode = 0
        for (var i = 0; i < shiftKeycodes.length; i++)
            release(shiftKeycodes[i])
    }

    function releaseAllKeys() {
        releaseShiftKeys()
    }

    function spawn(arg) {
        var proc = ydotoolProcess.createObject(root, {keyArg: arg})
        proc.running = true
    }

    Component {
        id: ydotoolProcess

        Process {
            property string keyArg: ""
            command: ["ydotool", "key", keyArg]
            onExited: exitCode => {
                if (exitCode !== 0)
                    console.warn("virtualKeyboard: ydotool exited", exitCode, "-", keyArg)
                destroy()
            }
        }
    }
}
