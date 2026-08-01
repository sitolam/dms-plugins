.pragma library

// Faithful port of the detection window logic in the MouthGuard web app
// (index.html:1411-1462). Kept as pure functions with no QML dependencies so
// it can be unit-tested with qmltestrunner.

function createState() {
    return {
        mouthOpen: false,
        rawOpenSince: null,
        currentOpenStart: null,
        mouthOpenSince: null,
        totalOpenMs: 0,
        totalClosedMs: 0,
        totalUnmeasuredMs: 0,
        openEvents: []
    }
}

// Events shorter than this are camera blips, not real mouth openings.
var MIN_EVENT_MS = 200

function tick(state, input) {
    var now = input.now
    var dt = input.dt
    var delay = input.delay
    var events = []

    // No face: accounting pauses entirely. Time counts toward neither open nor
    // closed, and alerts are suppressed — we genuinely do not know the state.
    if (!input.hasFace) {
        state.totalUnmeasuredMs += dt
        return events
    }

    // Time accounting uses the CONFIRMED state, and runs before detection.
    if (state.mouthOpen) {
        state.totalOpenMs += dt
    } else {
        state.totalClosedMs += dt
    }

    if (input.isOpen) {
        if (state.rawOpenSince === null) {
            state.rawOpenSince = now
        }

        if (!state.mouthOpen) {
            var openDur = now - state.rawOpenSince
            if (openDur >= delay) {
                // The window itself was open time; move it across.
                var retro = openDur
                state.totalClosedMs = Math.max(0, state.totalClosedMs - retro)
                state.totalOpenMs += retro
                state.mouthOpen = true
                state.currentOpenStart = state.rawOpenSince
                state.mouthOpenSince = now
                events.push("confirmed")
                events.push("alert")
            }
        } else if (now - state.mouthOpenSince >= delay) {
            // Re-arm: reset the clock so the next alert waits a full window.
            state.mouthOpenSince = now
            events.push("alert")
        }
    } else {
        if (state.mouthOpen) {
            var dur = now - (state.currentOpenStart === null ? now : state.currentOpenStart)
            if (dur > MIN_EVENT_MS) {
                state.openEvents.push(dur)
            }
            state.mouthOpen = false
            state.currentOpenStart = null
            events.push("closed")
        }
        state.rawOpenSince = null
    }

    return events
}
