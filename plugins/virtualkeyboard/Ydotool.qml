import QtQuick
import Quickshell.Io

Item {
    id: root

    // 0 = plain, 1 = shift held (single tap, released after the next normal
    // key or a second shift tap outside the caps-lock window), 2 = caps-lock
    // latched (second shift tap within the window).
    property int shiftMode: 0
    readonly property var shiftKeycodes: [42, 54]
    // Keycodes currently held down by a latched mod key. Tracked here rather
    // than on the keys themselves because the window owning them is destroyed
    // on close and on a pin/unpin swap, and a keycode still held at the kernel
    // level after its key is gone can never be released by pressing it again.
    property var heldKeycodes: []

    // The press itself already went out on the key's own press event -- this
    // only records that it was never released.
    function retainHeld(keycode) {
        if (heldKeycodes.indexOf(keycode) === -1)
            heldKeycodes = heldKeycodes.concat([keycode])
    }

    function releaseHeld(keycode) {
        release(keycode)
        heldKeycodes = heldKeycodes.filter(k => k !== keycode)
    }

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
        for (var i = 0; i < heldKeycodes.length; i++)
            release(heldKeycodes[i])
        heldKeycodes = []
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
