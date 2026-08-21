import QtQuick
import Quickshell.Io
import "Conditions.js" as ConditionsJs

Item {
    id: root

    // { id: { when: rc, checked: rc, disabled: rc } }
    property var results: ({})

    signal settled

    function clear() {
        results = {};
    }

    function evaluate(nodes) {
        const conds = ConditionsJs.collect(nodes);
        if (conds.length === 0) {
            results = {};
            settled();
            return;
        }
        proc.running = false;
        proc.script = ConditionsJs.buildScript(conds);
        proc.running = true;
    }

    Process {
        id: proc

        property string script: ""

        command: ["bash", "-lc", script]

        stdout: StdioCollector {
            onStreamFinished: {
                root.results = ConditionsJs.parseOutput(text);
                root.settled();
            }
        }
    }
}
