import QtQuick
import qs.Common

QtObject {
    id: root

    // --- shared detector-command resolution rule ---------------------------
    // Routing order MUST stay identical (same two candidates, same order) to
    // MouthGuardDaemon.qml's own `_resolveScript` -- copy any change to that
    // function's ROUTING (not the extra verification below) over here too.
    // A startup check that approves a different command than the one the
    // daemon actually launches is worse than no check at all: it lets the
    // plugin activate and then die immediately.
    //
    //   1. <pluginDir>/result/bin/mouthguard-detector -- the flake-built
    //      wrapper (`nix build .#detector` inside the plugin directory).
    //      Self-contained: bundles the pinned interpreter, cv2, OpenVINO and
    //      the MediaPipe model files, so it needs nothing from the ambient
    //      environment.
    //   2. python3 <pluginDir>/detector.py -- portable fallback, for distros
    //      where cv2 and openvino are installed system-wide for python3 and
    //      the models are on disk somewhere resolve_model_dir looks.
    //
    // This copy additionally gates the python3 branch on an explicit import
    // and model-resolution probe, which the daemon's copy does not do.
    // Reason: detector.py's --self-test returns BEFORE its imports and
    // before it resolves a model directory (see detector.py's
    // self_test()/main(), which this file must not modify), so self-test
    // alone passes on that branch even when those are
    // missing -- verified directly: `python3 detector.py --self-test`
    // exits 0 printing a valid "ready" line on this machine's ambient
    // python3, which has neither module installed. That false pass matters
    // here specifically because `[ -x "$W" ]` is false for a dangling/stale
    // `result` symlink (its target fails to stat) exactly the same as for a
    // wrapper that was never built, so a stale symlink already, correctly,
    // routes to this python3 branch -- without the explicit import check
    // here, that would silently rubber-stamp exactly the broken-wrapper
    // case this task exists to catch, instead of failing it. The wrapper
    // branch needs no equivalent gate: `nix build .#detector` guarantees
    // both modules and both model files inside its own closure whenever the
    // resulting binary is actually executable.
    //
    // `dir` is trusted (it comes from this component's own file location,
    // see _pluginDir below), so no extra quoting/escaping is done beyond the
    // plain double-quotes already needed for spaces in the path.
    function _checkScript(dir) {
        const wrapper = dir + "/result/bin/mouthguard-detector"
        const detector = dir + "/detector.py"
        return 'W="' + wrapper + '"; ' +
               'if [ -x "$W" ]; then exec "$W" --self-test; fi; ' +
               'python3 -c "import cv2, openvino" || exit 1; ' +
               // Models are a separate dependency from the modules that read
               // them, and a missing one fails at the first frame rather
               // than at import, so it is probed explicitly here.
               'python3 -c "import sys; sys.path.insert(0, \'' + dir + '\'); ' +
               'import mouthguard_core; mouthguard_core.resolve_model_dir()" || exit 1; ' +
               'exec python3 "' + detector + '" --self-test'
    }

    // pluginService/pluginId -- which MouthGuardDaemon.qml uses via
    // PluginComponent to build its path -- are NOT available here. Verified
    // against DMS 1.5.3's Services/PluginService.qml: runStartupGate()
    // creates this object with `comp.createObject(root)` (Modules/Plugins is
    // never involved, no property dict is passed), and calls `check(done)`
    // with only the callback -- no pluginId argument. So neither a bound
    // `pluginId` property nor a `pluginService` property exists on this
    // object, and there is no way to ask PluginService "what plugin am I"
    // from in here.
    //
    // What IS available: PluginService itself computes
    // startupCheckPath = "<pluginDirectory>/StartupCheck.qml" and loads this
    // file directly from that path (Qt.createComponent("file://" + ...)), so
    // this file always lives in the plugin's own directory alongside
    // detector.py and (once built) result/. Qt.resolvedUrl(".") resolves
    // relative to *this file's own* URL -- confirmed empirically with Qt's
    // `qml` runtime against a file in a subdirectory, which resolved "." to
    // that subdirectory, not the caller's location -- so it gives exactly
    // the plugin directory without needing pluginService at all.
    function _pluginDir() {
        let url = Qt.resolvedUrl(".").toString()
        if (url.endsWith("/"))
            url = url.slice(0, -1)
        return decodeURIComponent(url.replace(/^file:\/\//, ""))
    }

    // Optional async dependency gate, per DMS's StartupCheck contract:
    //   done(null)                       -> allow activation
    //   done({ title, details })         -> block with an expandable details body
    function check(done) {
        const dir = _pluginDir()

        // Verify the CHOSEN command actually runs -- a file existing is not
        // enough. A stale `result` symlink (its nix store path
        // garbage-collected) fails `[ -x "$W" ]` exactly like a wrapper that
        // was never built, so both fall through to the python3 branch below
        // -- see _checkScript's comment for why that branch carries its own
        // explicit module and model probes. `exec 2>&1` merges stderr into the
        // captured stream purely for this one-shot probe, so a failure
        // (missing module, broken exec) is visible in the details pane --
        // this is NOT done in MouthGuardDaemon.qml's copy of the script,
        // which keeps stdout (JSON protocol) and stderr (logs) separate for
        // the long-running process; see that file's comment.
        Proc.runCommand("mouthGuard.depCheck",
            ["sh", "-c", "exec 2>&1; " + _checkScript(dir)],
            (stdout, exitCode) => {
                if (exitCode === 0 && /"ready":\s*true/.test(stdout)) {
                    done(null)
                    return
                }
                done({
                    "title": I18n.tr("MouthGuard detector is not available"),
                    "details": I18n.tr(
                        "MouthGuard needs a working detector: either the flake-built "
                        + "wrapper, or python3 with the cv2 and openvino modules "
                        + "plus the two MediaPipe model files.\n\n"
                        + "Nix (required on NixOS -- the system python3 will not have "
                        + "these modules, and the flake is also what enables the NPU):\n"
                        + "  cd " + dir + " && nix build .#detector\n"
                        + "(already did this? the build may be stale, e.g. its nix "
                        + "store path was garbage-collected -- rebuild it)\n\n"
                        + "Other distros, if cv2/openvino are installed system-wide:\n"
                        + "  Arch:    sudo pacman -S python-opencv python-openvino\n"
                        + "  Fedora:  sudo dnf install python3-opencv python3-openvino\n"
                        + "  Debian:  sudo apt install python3-opencv python3-openvino\n\n"
                        + "The models go in ~/.cache/mouthguard, or anywhere pointed "
                        + "at by MOUTHGUARD_MODEL_DIR -- see the README.\n\n"
                        + "Detail: ") + stdout
                })
            })
    }
}
