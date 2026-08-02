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
    // MouthGuardSettings.qml's threshold slider is int-only (DMS 1.5.3
    // SliderSetting/DankSlider have no fractional step -- see that file's
    // header comment) and stores TENTHS of a gap-unit so a stock slider can
    // reach the calibrated 3.5 default (35 stored, e.g. minimum 10 =
    // threshold 1.0). Divide by 10 here to recover the real px-scale value
    // DEFAULT_THRESHOLD and the rest of this file operate in; the unset
    // fallback multiplies DEFAULT_THRESHOLD back up first so both paths
    // land on the exact same 3.5.
    readonly property real threshold: (pluginData?.threshold ?? (DEFAULT_THRESHOLD * 10)) / 10
    // MouthGuardSettings.qml's alertDelay slider stores MILLISECONDS
    // directly (again to stay on DMS's integer-only slider, and to exceed
    // rather than lose the original web app's 0.1s/100ms step) -- read as
    // ms with no `* 1000` here. Default 1000 matches that slider's default
    // exactly.
    readonly property real alertDelayMs: pluginData?.alertDelay ?? 1000
    readonly property bool distComp: pluginData?.distanceCompensation ?? true
    readonly property string soundType: pluginData?.soundType ?? "soft"
    readonly property real volume: (pluginData?.volume ?? 85) / 100
    readonly property bool notifications: pluginData?.notifications ?? true
    readonly property int fps: pluginData?.fps ?? 10
    readonly property int noFaceTimeoutMs: (pluginData?.noFaceTimeout ?? 5) * 60000
    readonly property bool autoPause: pluginData?.autoPause ?? true

    // Bound (not merely read once) so any of these services changing state
    // while the plugin is running -- lock, idle, screen-off, or a sleep
    // preparation signal -- flips this immediately. Gated on `active` so a
    // stale true left over from before the session started can't fire
    // onShouldPauseChanged before there is a detector to pause.
    readonly property bool shouldPause: active && autoPause && (
        (SessionService?.locked ?? false)
        || (SessionService?.idleHint ?? false)
        || (SessionService?.preparingForSleep ?? false)
        || (IdleService?.monitorsOff ?? false)
    )

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
    // True while the detector has released the capture device (auto-pause)
    // or is between processes after a crash/restart -- both are "we are not
    // currently receiving measurements" gaps, reconciled the same way. See
    // onShouldPauseChanged, onExited, and _onMeasurement/_reconcileGap.
    property bool paused: false
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

    // Most-recent-first, capped at 30 entries. Populated from
    // Component.onCompleted and appended to by _saveSession().
    property var history: []

    function toggle() {
        if (active) {
            _stopSession()
        } else {
            active = true
            resetSession()
        }
    }

    // Every path that ends a session (manual toggle-off, no-face auto-stop,
    // a detector-reported error, and a detector crash) must flush any
    // in-progress open event and settle state the same way, or it is
    // silently dropped from sessionStats.events / avgOpenMs -- the exact bug
    // finish() exists to prevent. One helper, four call sites, so a future
    // fifth stop path cannot reintroduce it by copy-paste omission.
    function _stopSession() {
        const now = Date.now()
        // If a session is stopped while still mid-gap (paused for a lock
        // that never unlocked before toggle-off, or between a crashed
        // detector and its replacement's first line -- see onExited) the
        // gap has to be credited to totalUnmeasuredMs here too, or it is
        // simply dropped from the final stats and accounted would fall
        // short of session length. _reconcileGap always closes any
        // in-progress open event itself, so the finish() call below becomes
        // a no-op for that event -- it still runs unconditionally since
        // finish() is what every other stop path relies on.
        if (paused) _reconcileGap(now)
        SM.finish(_sm, now)
        _publishStats()
        // Must come after finish()/_publishStats() above, not before: those
        // are what flush the last in-progress open event into
        // _sm.totalOpenMs/openEvents. Saving history first would silently
        // drop that final event from the persisted record -- the exact bug
        // two earlier fix rounds were spent eliminating (see _reconcileGap's
        // comment for the related finish()-ordering bug this mirrors).
        _saveSession()
        active = false
        paused = false
        mouthState = "inactive"
    }

    // Appends the just-ended session to `history` (most-recent-first, capped
    // at 30) and persists it. Only ever called from _stopSession(), after
    // SM.finish()/_publishStats() have already run -- see the comment at
    // that call site.
    //
    // `wallClockMs` is deliberately not named `durationMs`: _reconcileGap
    // credits auto-pause and detector-restart gaps to totalUnmeasuredMs, so
    // openMs + closedMs can legitimately fall short of the session's real
    // wall-clock span whenever a pause occurred. Naming the wall-clock field
    // plainly, and storing unmeasuredMs alongside openMs/closedMs, keeps a
    // future reader (Task 14's chart, Task 16's CC tile) from mistaking one
    // for the other.
    function _saveSession() {
        if (!_sessionStart) return
        const measured = _sm.totalOpenMs + _sm.totalClosedMs
        // A session with nothing measured is noise, not history.
        if (measured < 1000) return

        const entry = {
            start: _sessionStart,
            wallClockMs: Date.now() - _sessionStart,
            openMs: _sm.totalOpenMs,
            closedMs: _sm.totalClosedMs,
            unmeasuredMs: _sm.totalUnmeasuredMs,
            events: _sm.openEvents.length
        }
        history = [entry].concat(history).slice(0, 30)
        pluginService?.savePluginState(pluginId, "history", history)
    }

    // Credits an interval during which tick() was never called -- an
    // auto-pause (lock/idle/sleep), or a detector crash-and-restart -- to
    // totalUnmeasuredMs, via the state machine's own no-face branch (never
    // by writing _sm.totalUnmeasuredMs directly, and never by altering
    // StateMachine.js). dt = now - _lastTickAt satisfies tick()'s "dt ===
    // now - previousNow" caller contract exactly: nothing else advances the
    // state machine's clock while paused is true, because _onMeasurement
    // drops every stray in-flight line for as long as shouldPause holds.
    //
    // Order matters here. finish() MUST run first, closing any in-progress
    // open event at the last OBSERVED moment (_lastTickAt), before the
    // no-face tick below claims the gap as unmeasured. Folding both into a
    // single no-face tick with an honest dt would instead close the event
    // at `now` -- at the far end of the gap -- because boundEventEnd's
    // clamp is deliberately inert for a caller that tells the truth about
    // dt (an honest caller needs no bounding), and a large, honest dt is
    // exactly what this call passes. That would turn a lock/idle/sleep
    // span into a fabricated multi-hour open event: the exact bug this
    // task exists to prevent, just relocated instead of fixed. Once
    // finish() has closed it, mouthOpen is already false, so the no-face
    // tick's own close branch has nothing left to do -- it only credits dt
    // to totalUnmeasuredMs, which is the correct, and only, claim to make
    // about time nothing was observed.
    function _reconcileGap(now) {
        if (_lastTickAt) {
            SM.finish(_sm, _lastTickAt)
            SM.tick(_sm, {
                now: now, dt: now - _lastTickAt,
                isOpen: false, hasFace: false, delay: alertDelayMs
            })
        }
        _lastTickAt = now
    }

    function resetSession() {
        _sm = SM.createState()
        _lastTickAt = 0
        _noFaceSince = 0
        _sessionStart = Date.now()
        _lastAlertDeliveredAt = 0
        gapHistory = []
        paused = false
        mouthState = "closed"
        _publishStats()
    }

    // Auto-pause: release the capture device (camera LED off) on lock,
    // idle, screen-off, or sleep preparation, without killing the detector
    // process -- the whole point is to avoid paying the ~1s dlib model
    // reload on every lock/unlock. detector.py keeps the model resident and
    // just stops/starts touching the device (see detector.py's "pause"/
    // "resume" stdin commands).
    onShouldPauseChanged: {
        if (!active) return
        if (shouldPause) {
            paused = true
            mouthState = "paused"
            detector.write("pause\n")
        } else {
            // Ask the detector to reopen the camera, but do NOT clear
            // `paused` (or resume measurement processing) here. detector.py
            // can fail to reopen -- camera still settling, another app
            // grabbed it -- and deliberately stays alive and paused rather
            // than exiting (see the stdout handler's camera_busy case
            // below), so treating this write as instant success would both
            // mis-report state and let the next real measurement's dt span
            // the failed-resume retry wait as if it were live data. `paused`
            // is only cleared once a real measurement actually arrives --
            // see _onMeasurement -- which is also where the whole dead span
            // gets credited to totalUnmeasuredMs.
            detector.write("resume\n")
        }
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

        if (paused) {
            if (shouldPause) {
                // Still supposed to be paused: this is a stray measurement
                // line already in flight before the detector processed our
                // "pause" command (or before it processes a fresh "pause"
                // sent for a still-active lock/idle condition). Drop it
                // without touching _lastTickAt or the state machine so it
                // cannot be counted during the pause.
                return
            }
            // shouldPause is false, so we've asked the detector to resume
            // (or a crashed process was replaced -- see onExited) and this
            // is the first real measurement since. That is proof the dead
            // span is over, however long it took -- including any failed-
            // resume retries or a model reload. Credit the whole span to
            // totalUnmeasuredMs with a single synthetic no-face tick before
            // processing this measurement.
            _reconcileGap(now)
            paused = false
        }

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
            // Zeroed together, deliberately: leaving lastGap/lastFace at
            // their last-seen values while only lastAdjGap went to zero
            // would let a consumer (the Task 15 popout) display a stale
            // "last known" reading as if it were current. Detection itself
            // is unaffected either way -- isOpen already requires hasFace --
            // this is about not silently showing a wrong number.
            lastGap = 0
            lastFace = 0
            lastAdjGap = 0
        }

        const effective = distComp ? lastAdjGap : lastGap
        const events = SM.tick(_sm, {
            now: now, dt: dt, isOpen: hasFace && effective > threshold,
            hasFace: hasFace, delay: alertDelayMs
        })

        if (events.indexOf("alert") >= 0) _alert(now)

        // Chart plots the same number the threshold is compared against, so the
        // threshold line stays meaningful whichever mode is active. A fresh
        // array is still built every tick (assigning the same array
        // reference back to a `property var` would not fire gapHistoryChanged,
        // so reactive consumers like the Task 14 chart would silently stop
        // updating) -- but the second, trimming pass only runs when an entry
        // has actually aged out of the 60s window, rather than on every tick.
        const cutoff = now - 60000
        let next = gapHistory.concat([{ t: now, gap: hasFace ? effective : 0 }])
        if (next.length && next[0].t < cutoff) {
            next = next.filter(p => p.t >= cutoff)
        }
        gapHistory = next

        mouthState = !hasFace ? "noface" : (_sm.mouthOpen ? "open" : "closed")
        _publishStats()

        if (_noFaceSince && noFaceTimeoutMs > 0
                && now - _noFaceSince > noFaceTimeoutMs) {
            ToastService?.showInfo(
                "MouthGuard stopped — no face detected for "
                + Math.round(noFaceTimeoutMs / 60000) + " minutes")
            // In practice the state machine already closed any open event
            // the instant the face was lost (tick()'s no-face branch), so
            // _stopSession()'s finish() call is normally a no-op here -- it
            // is still called for consistency with every other stop path.
            _stopSession()
        }
    }

    SoundEffectWrapper { id: sound }

    Process {
        id: detector
        running: root.active
        // Required so detector.write() below can reach the process's stdin
        // -- that's how "pause"/"resume" are delivered.
        stdinEnabled: true
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
                    // A failed resume attempt reports camera_busy too, but
                    // detector.py deliberately stays alive and paused rather
                    // than exiting in that case (see detector.py's "resume"
                    // branch) -- exiting would discard the resident dlib
                    // model over what may be a momentary device-busy blip,
                    // exactly the cost auto-pause exists to avoid. Every
                    // other error (model missing, the initial camera open
                    // failing) happens before any pause could have occurred,
                    // so root.paused is false there and this falls through
                    // to the normal fatal handling below.
                    if (msg.error === "camera_busy" && root.paused) return
                    root._stopSession()
                    return
                }
                if (msg.ready) {
                    // A fresh process (first start, or the restart onExited
                    // marks with paused=true) always starts unpaused and
                    // capturing. If a pause condition is still active --
                    // e.g. the detector crashed while the session was
                    // locked -- bring it in line immediately rather than
                    // leaving the camera live until the next lock/unlock
                    // edge; onShouldPauseChanged won't fire again on its
                    // own since shouldPause never changed.
                    if (root.shouldPause) detector.write("pause\n")
                    return
                }
                root._onMeasurement(msg)
            }
        }

        stderr: StdioCollector {
            onTextReceived: text => console.warn("[MouthGuard]", text)
        }

        onExited: exitCode => {
            if (exitCode !== 0 && root.active) {
                ToastService?.showError("MouthGuard detector exited: " + exitCode)
                root._stopSession()
                return
            }
            // The process exited while the session is meant to continue --
            // e.g. the `running: root.active` binding restarting a process
            // that died on its own without root.active ever changing. The
            // replacement begins from a cold camera and, for dlib, a ~1s
            // model reload: mark the same pending-reconciliation gap the
            // auto-pause path uses (freeze _lastTickAt, flag paused) rather
            // than discarding the interval with the old `_lastTickAt = 0`.
            // The replacement process's first real measurement will credit
            // the whole dead span to totalUnmeasuredMs via
            // _onMeasurement/_reconcileGap, instead of crediting it to
            // nothing (the old behaviour) or letting it leak into open/
            // closed time under one huge dt.
            if (root.active && root._lastTickAt) {
                root.paused = true
                root.mouthState = "paused"
            }
        }
    }

    Component.onCompleted: {
        if (!pluginService) return
        const next = Object.assign({}, pluginService.pluginInstances)
        next[pluginId] = root
        pluginService.pluginInstances = next
        history = pluginService.loadPluginState(pluginId, "history", [])
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
