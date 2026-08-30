import QtQuick
import Quickshell.Io
import "Conditions.js" as ConditionsJs

Item {
    id: root

    // { id: { when: rc, checked: rc, disabled: rc } }
    property var results: ({})

    // The script whose results `results` holds -- or which is in flight. Two
    // evaluations of the same set of rows produce byte-identical scripts, so
    // this is what tells a repeat from a new level.
    property string lastScript: ""

    signal settled

    // A level's conditions are a snapshot taken when the level opens, so
    // re-entering a level must re-run them however recently they last ran.
    // Typing must not: every keystroke at a level re-derives the same rows,
    // and a condition costing a second (a `docker stats`, an `ssh`) would
    // otherwise be paid once per character.
    function invalidate() {
        lastScript = "";
        results = {};
    }

    function evaluate(nodes) {
        const conds = ConditionsJs.collect(nodes);
        if (conds.length === 0) {
            results = {};
            lastScript = "";
            settled();
            return;
        }

        const script = ConditionsJs.buildScript(conds);
        if (script === lastScript) {
            // Same rows as the run that is current or still in flight. Nothing
            // to do -- the in-flight one will emit settled() for both.
            if (!proc.running)
                settled();
            return;
        }

        lastScript = script;
        // Old results are deliberately kept until the new ones land: rows
        // decorated a moment ago should not lose their ticks for the duration
        // of a keystroke's debounce.
        debounce.restart();
    }

    // One burst of typing is one run. 150ms is below the point where a settling
    // tick reads as lag, and above a fast typist's inter-key gap.
    Timer {
        id: debounce

        interval: 150
        onTriggered: {
            proc.running = false;
            proc.script = root.lastScript;
            proc.running = true;
        }
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
