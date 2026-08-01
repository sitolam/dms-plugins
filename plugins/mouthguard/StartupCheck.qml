import QtQuick
import qs.Common

QtObject {
    function check(done) {
        // Probe the interpreter the daemon will actually use, so a green check
        // here guarantees the detector can start.
        Proc.runCommand("mouthGuard.depCheck",
            ["sh", "-c", "python3 -c 'import cv2, dlib' 2>&1"],
            (stdout, exitCode) => {
                if (exitCode === 0) {
                    done(null)
                    return
                }
                done({
                    "title": I18n.tr("Python, OpenCV and dlib are required"),
                    "details": I18n.tr(
                        "MouthGuard needs python3 with the cv2 and dlib modules.\n\n" +
                        "Arch:    sudo pacman -S python-opencv python-dlib\n" +
                        "Fedora:  sudo dnf install python3-opencv python3-dlib\n" +
                        "Debian:  sudo apt install python3-opencv python3-dlib\n" +
                        "Nix:     use the flake.nix bundled with this plugin\n\n" +
                        "Detail: ") + stdout
                })
            })
    }
}
