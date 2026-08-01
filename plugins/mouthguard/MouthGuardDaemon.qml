import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins
import "StateMachine.js" as SM

PluginComponent {
    id: root

    property var popoutService: null

    // --- settings, mirrored from pluginData -------------------------------
    readonly property string device: pluginData?.device ?? "/dev/video0"
    readonly property real threshold: pluginData?.threshold ?? DEFAULT_THRESHOLD
    readonly property real alertDelayMs: (pluginData?.alertDelay ?? 1.0) * 1000
    readonly property bool distComp: pluginData?.distanceCompensation ?? true
    readonly property string soundType: pluginData?.soundType ?? "soft"
    readonly property real volume: (pluginData?.volume ?? 85) / 100
    readonly property bool notifications: pluginData?.notifications ?? true
    readonly property int fps: pluginData?.fps ?? 10
    readonly property int noFaceTimeoutMs: (pluginData?.noFaceTimeout ?? 5) * 60000

    // Calibrated against the real dlib pipeline on the project owner's
    // hardware; see CALIBRATION.md and mouthguard_core.DEFAULT_THRESHOLD /
    // DEFAULT_DISTANCE_REF. These are dlib-scale values and bear no relation
    // to the web app's MediaPipe-scale originals (threshold 5, distance ref
    // 100px) -- do not "round trip" a value between the two apps.
    readonly property real DEFAULT_THRESHOLD: 3.5
    readonly property real DISTANCE_REF: 71

    // Minimum spacing between DELIVERED alerts (notification and sound
    // together), independent of alertDelayMs. When the detection window is
    // set to 0s the state machine faithfully emits "alert" on every tick --
    // that must not change -- so without this an alert would fire at the
    // detector's frame rate (roughly 6-10/s), a notification storm. The
    // state machine keeps emitting; only delivery is throttled, here.
    readonly property real ALERT_MIN_INTERVAL_MS: 2000
    property real _lastAlertDeliveredAt: 0

    // tools/gen_sounds.py peak-normalises each WAV independently, which
    // flattened the relative loudness the browser original encoded through
    // absolute gain. Restored here as a per-sound multiplier applied on top
    // of the user's volume setting -- buzz is meant to be the quietest.
    readonly property var _soundRelativeGain: ({
        soft: 1.0, double: 1.0, ping: 0.8, chime: 0.6, buzz: 0.4
    })

    // --- live state -------------------------------------------------------
    property bool active: false
    property bool alertsMuted: false
    property string mouthState: "inactive"
    property real lastGap: 0
    property real lastFace: 0
    property real lastAdjGap: 0
    property var gapHistory: []
    property var sessionStats: ({
        openMs: 0, closedMs: 0, unmeasuredMs: 0, events: 0, avgOpenMs: 0
    })

    property var _sm: SM.createState()
    property real _lastTickAt: 0
    property real _noFaceSince: 0
    property real _sessionStart: 0

    function toggle() {
        active = !active
        if (active) {
            resetSession()
        } else {
            // Flush any in-progress open event, or it is silently dropped
            // from sessionStats.events / avgOpenMs.
            SM.finish(_sm, Date.now())
            _publishStats()
            mouthState = "inactive"
        }
    }

    function resetSession() {
        _sm = SM.createState()
        _lastTickAt = 0
        _noFaceSince = 0
        _sessionStart = Date.now()
        _lastAlertDeliveredAt = 0
        gapHistory = []
        mouthState = "closed"
        _publishStats()
    }

    function _publishStats() {
        const evs = _sm.openEvents
        const total = evs.reduce((a, b) => a + b, 0)
        sessionStats = {
            openMs: _sm.totalOpenMs,
            closedMs: _sm.totalClosedMs,
            unmeasuredMs: _sm.totalUnmeasuredMs,
            events: evs.length,
            avgOpenMs: evs.length ? total / evs.length : 0
        }
    }

    function _alert(now) {
        if (alertsMuted) return
        if (_lastAlertDeliveredAt && now - _lastAlertDeliveredAt < ALERT_MIN_INTERVAL_MS) return
        _lastAlertDeliveredAt = now

        if (notifications) {
            Quickshell.execDetached([
                "notify-send", "-a", "MouthGuard", "-i", "sentiment_dissatisfied",
                "MouthGuard", "Close your mouth!"
            ])
        }
        if (soundType !== "none") {
            sound.source = Qt.resolvedUrl("sounds/" + soundType + ".wav")
            sound.volume = volume * (_soundRelativeGain[soundType] ?? 1.0)
            sound.play()
        }
    }

    function _onMeasurement(msg) {
        const now = Date.now()
        const dt = _lastTickAt ? now - _lastTickAt : 100
        _lastTickAt = now

        const hasFace = msg.gap !== undefined
        if (hasFace) {
            _noFaceSince = 0
            lastGap = msg.gap
            lastFace = msg.face
            lastAdjGap = (distComp && msg.face > 10)
                ? msg.gap * (DISTANCE_REF / msg.face) : msg.gap
        } else {
            if (!_noFaceSince) _noFaceSince = now
            lastAdjGap = 0
        }

        const effective = distComp ? lastAdjGap : lastGap
        const events = SM.tick(_sm, {
            now: now, dt: dt, isOpen: hasFace && effective > threshold,
            hasFace: hasFace, delay: alertDelayMs
        })

        if (events.indexOf("alert") >= 0) _alert(now)

        // Chart plots the same number the threshold is compared against, so the
        // threshold line stays meaningful whichever mode is active.
        const cutoff = now - 60000
        const next = gapHistory.concat([{ t: now, gap: hasFace ? effective : 0 }])
        gapHistory = next.filter(p => p.t >= cutoff)

        mouthState = !hasFace ? "noface" : (_sm.mouthOpen ? "open" : "closed")
        _publishStats()

        if (_noFaceSince && noFaceTimeoutMs > 0
                && now - _noFaceSince > noFaceTimeoutMs) {
            ToastService?.showInfo(
                "MouthGuard stopped — no face detected for "
                + Math.round(noFaceTimeoutMs / 60000) + " minutes")
            // Session is stopping: flush any in-progress open event, same as
            // the manual toggle()-off path. In practice the state machine
            // already closed any open event the instant the face was lost
            // (tick()'s no-face branch), so this is normally a no-op here --
            // but it is called for the same reason toggle() calls it: so a
            // session never ends silently dropping its last open event.
            SM.finish(_sm, now)
            _publishStats()
            active = false
            mouthState = "inactive"
        }
    }

    SoundEffectWrapper { id: sound }

    Process {
        id: detector
        running: root.active
        command: [
            "python3", pluginService.getPluginPath(root.pluginId) + "/detector.py",
            "--device", root.device, "--fps", String(root.fps)
        ]

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (!data) return
                let msg
                try { msg = JSON.parse(data) } catch (e) { return }
                if (msg.error) {
                    ToastService?.showError("MouthGuard: " + msg.error + " — " + msg.detail)
                    root.active = false
                    return
                }
                if (msg.ready) return
                root._onMeasurement(msg)
            }
        }

        stderr: StdioCollector {
            onTextReceived: text => console.warn("[MouthGuard]", text)
        }

        onExited: exitCode => {
            if (exitCode !== 0 && root.active) {
                ToastService?.showError("MouthGuard detector exited: " + exitCode)
                root.active = false
                root.mouthState = "inactive"
            }
        }
    }

    Component.onCompleted: {
        if (!pluginService) return
        const next = Object.assign({}, pluginService.pluginInstances)
        next[pluginId] = root
        pluginService.pluginInstances = next
        // Resume whatever the last session state was.
        active = pluginService.loadPluginData(pluginId, "active", false)
        if (active) resetSession()
    }

    Component.onDestruction: {
        if (!pluginService) return
        if (pluginService.pluginInstances[pluginId] !== root) return
        const next = Object.assign({}, pluginService.pluginInstances)
        delete next[pluginId]
        pluginService.pluginInstances = next
    }

    onActiveChanged: pluginService?.savePluginData(pluginId, "active", active)
}
