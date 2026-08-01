.pragma library

// Faithful port of the detection window logic in the MouthGuard web app
// (index.html:1411-1462), plus the session-end flush at index.html:1577-1581.
// Kept as pure functions with no QML dependencies so it can be unit-tested
// with qmltestrunner.
//
// Caller contract: the `dt` passed to tick() MUST equal `now - previousNow`
// (the wall-clock delta since the previous tick()/finish() call against this
// state). The accounting mixes dt-accumulated totals (totalOpenMs /
// totalClosedMs / totalUnmeasuredMs) with now-derived values (the detection
// window's retroactive open-time credit on confirmation, and closed-event
// durations) — if dt and now ever disagree about elapsed time, those totals
// will not reconcile.

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

// Shared close-and-record step used by the normal close path, the no-face
// path, and finish(): if the duration qualifies (strictly greater than
// MIN_EVENT_MS) it is pushed onto openEvents, then mouthOpen/currentOpenStart
// are cleared. Callers are responsible for anything beyond that (pushing the
// "closed" event string, resetting rawOpenSince, etc.) since the call sites
// need slightly different surrounding behaviour.
function closeOpenEvent(state, now) {
    var dur = now - (state.currentOpenStart === null ? now : state.currentOpenStart)
    if (dur > MIN_EVENT_MS) {
        state.openEvents.push(dur)
    }
    state.mouthOpen = false
    state.currentOpenStart = null
}

function tick(state, input) {
    if (input.hasFace === undefined || input.delay === undefined) {
        throw new Error("StateMachine.tick: input.hasFace and input.delay are required")
    }

    var now = input.now
    var dt = input.dt
    var delay = input.delay
    var events = []

    if (!input.hasFace) {
        // Time counts toward neither open nor closed — we genuinely do not
        // know the state while the face is not visible.
        state.totalUnmeasuredMs += dt

        // Faithful to the browser original: missing landmarks are treated as
        // not-open, so any confirmed-open event in progress is closed now,
        // exactly as the normal close path would. We deliberately do NOT try
        // to net the unmeasured span out of the event — the project owner
        // chose to make no claim about what happened while the face was not
        // visible.
        if (state.mouthOpen) {
            closeOpenEvent(state, now)
            events.push("closed")
        }

        // Unconditional reset restores the original's invariant: a raw-open
        // run is scoped to a contiguous run of face-present open frames, so
        // the face returning (even with the mouth still open) starts a fresh
        // window rather than resuming a stale one.
        state.rawOpenSince = null

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
            closeOpenEvent(state, now)
            events.push("closed")
        }
        state.rawOpenSince = null
    }

    return events
}

// Ports index.html:1577-1581 — records the in-progress open event (if any)
// when a session stops, so it is not silently dropped. A no-op when nothing
// is currently confirmed open.
function finish(state, now) {
    var events = []
    if (state.mouthOpen) {
        closeOpenEvent(state, now)
        events.push("closed")
    }
    return events
}
