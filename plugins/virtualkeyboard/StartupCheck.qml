import QtQuick
import qs.Common

QtObject {
    function check(done) {
        Proc.runCommand("virtualKeyboard.depCheck", ["sh", "-c", "command -v ydotool"], (stdout, exitCode) => {
            if (exitCode === 0) {
                done(null)
                return
            }
            done({
                title: "ydotool is required",
                details: "virtualKeyboard types by driving ydotool, which is not on your PATH.\n\nInstall ydotool, then make sure its ydotoold service is enabled and running (e.g. `systemctl --user enable --now ydotool` or your distro's equivalent — some distros run ydotoold as a system service instead), then re-enable this plugin."
            })
        })
    }
}
