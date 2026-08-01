import QtQuick
import QtTest
import "../StateMachine.js" as SM

TestCase {
    name: "StateMachine"

    function make() { return SM.createState() }

    function feed(s, opts) {
        return SM.tick(s, {
            now: opts.now, dt: opts.dt === undefined ? 100 : opts.dt,
            isOpen: opts.isOpen, hasFace: opts.hasFace === undefined ? true : opts.hasFace,
            delay: opts.delay === undefined ? 1000 : opts.delay
        })
    }

    function test_closed_mouth_accrues_closed_time() {
        var s = make()
        feed(s, { now: 100, dt: 100, isOpen: false })
        compare(s.totalClosedMs, 100)
        compare(s.totalOpenMs, 0)
    }

    function test_brief_opening_below_window_is_discarded() {
        // The v1.2.2 false-positive fix: a blip shorter than the detection
        // window must leave no trace at all — no alert, no open time, no event.
        var s = make()
        feed(s, { now: 100, isOpen: true })
        feed(s, { now: 500, isOpen: true })
        var ev = feed(s, { now: 600, isOpen: false })
        compare(s.mouthOpen, false)
        compare(s.totalOpenMs, 0)
        compare(s.openEvents.length, 0)
        compare(ev.indexOf("alert"), -1)
    }

    function test_holding_past_window_confirms_and_alerts() {
        var s = make()
        feed(s, { now: 100, isOpen: true })
        var ev = feed(s, { now: 1100, isOpen: true })
        compare(s.mouthOpen, true)
        verify(ev.indexOf("alert") >= 0)
        verify(ev.indexOf("confirmed") >= 0)
    }

    function test_detection_window_is_retroactively_counted_as_open() {
        // The window itself was time spent with the mouth open, so it must move
        // from the closed total to the open total on confirmation.
        var s = make()
        feed(s, { now: 100, dt: 100, isOpen: true })
        compare(s.totalClosedMs, 100)
        feed(s, { now: 1100, dt: 1000, isOpen: true })
        compare(s.totalOpenMs, 1000)
        compare(s.totalClosedMs, 100)
    }

    function test_alert_rearms_once_per_window_not_every_tick() {
        var s = make()
        feed(s, { now: 100, isOpen: true })
        feed(s, { now: 1100, isOpen: true })          // confirmed, alert 1
        var quiet = feed(s, { now: 1600, isOpen: true })
        compare(quiet.indexOf("alert"), -1)
        var again = feed(s, { now: 2200, isOpen: true })
        verify(again.indexOf("alert") >= 0)
    }

    function test_closing_records_the_event_duration() {
        // dt is honest at every step here (dt === now - previousNow), unlike
        // most other tests in this file which use feed()'s lazy dt default.
        // This proves the round-3 pause bound does not alter behaviour when
        // the caller tells the truth: the full 3000ms duration still lands.
        var s = make()
        feed(s, { now: 100, dt: 100, isOpen: true })
        feed(s, { now: 1100, dt: 1000, isOpen: true })
        var ev = feed(s, { now: 3100, dt: 2000, isOpen: false })
        verify(ev.indexOf("closed") >= 0)
        compare(s.openEvents.length, 1)
        compare(s.openEvents[0], 3000)
        compare(s.mouthOpen, false)
    }

    function test_sub_200ms_events_are_not_recorded() {
        var s = make()
        feed(s, { now: 100, isOpen: true, delay: 0 })
        feed(s, { now: 250, isOpen: false, delay: 0 })
        compare(s.openEvents.length, 0)
    }

    function test_no_face_accrues_unmeasured_and_suppresses_alerts() {
        var s = make()
        var ev = feed(s, { now: 100, dt: 100, isOpen: false, hasFace: false })
        compare(s.totalUnmeasuredMs, 100)
        compare(s.totalClosedMs, 0)
        compare(s.totalOpenMs, 0)
        compare(ev.length, 0)
    }

    function test_no_face_while_open_does_not_fire_alerts() {
        var s = make()
        feed(s, { now: 100, isOpen: true })
        feed(s, { now: 1100, isOpen: true })
        var ev = feed(s, { now: 2200, isOpen: false, hasFace: false })
        compare(ev.indexOf("alert"), -1)
        compare(s.totalUnmeasuredMs, 100)
        // What actually matters about "pausing": the open total must not
        // keep advancing while we cannot see the face.
        compare(s.totalOpenMs, 1000)
    }

    function test_zero_delay_confirms_immediately() {
        var s = make()
        var ev = feed(s, { now: 100, isOpen: true, delay: 0 })
        compare(s.mouthOpen, true)
        verify(ev.indexOf("alert") >= 0)
    }

    // --- Fix round 2: mutation-testing gap-fillers, verbatim from review ---

    function test_rearm_resets_the_clock() {
        var s = SM.createState()
        feed(s, { now: 100, isOpen: true }); feed(s, { now: 1100, isOpen: true })
        verify(feed(s, { now: 2200, isOpen: true }).indexOf("alert") >= 0)
        compare(feed(s, { now: 2700, isOpen: true }).indexOf("alert"), -1)
    }
    function test_close_resets_the_detection_window() {
        var s = SM.createState()
        feed(s, { now: 100, isOpen: true }); feed(s, { now: 500, isOpen: false })
        var ev = feed(s, { now: 600, isOpen: true })
        compare(s.mouthOpen, false); compare(ev.length, 0); compare(s.rawOpenSince, 600)
    }
    // Deliberately violates the dt === now - previousNow contract (now jumps
    // 1000ms while dt stays 100) on purpose: that is the only way to drive
    // totalClosedMs below the retroactive open-time credit and reach the
    // Math.max(0, ...) clamp. That clamp is defensive code inherited from
    // the browser original — honest dt can never make totalClosedMs go
    // negative, since the clamped amount and the dt-accumulated amount would
    // agree. Do not "fix" this test's dt to be honest; doing so would remove
    // the clamp's only test coverage.
    function test_closed_total_clamps_at_zero() {
        var s = SM.createState()
        feed(s, { now: 100, dt: 100, isOpen: true }); feed(s, { now: 1100, dt: 100, isOpen: true })
        compare(s.totalClosedMs, 0); compare(s.totalOpenMs, 1000)
    }
    function test_retro_uses_actual_duration_not_delay() {
        var s = SM.createState()
        feed(s, { now: 100, dt: 100, isOpen: true }); feed(s, { now: 1350, dt: 1250, isOpen: true })
        compare(s.totalOpenMs, 1250); compare(s.totalClosedMs, 100)
    }
    function test_exactly_200ms_is_discarded() {
        var s = SM.createState()
        feed(s, { now: 100, isOpen: true, delay: 0 }); feed(s, { now: 300, isOpen: false, delay: 0 })
        compare(s.openEvents.length, 0)
    }

    // --- Fix round 2: new no-face semantics (close-on-no-face, session finish) ---

    function test_no_face_while_confirmed_open_closes_and_records_event() {
        // No face is treated as not-open, faithful to the browser original:
        // an in-progress confirmed-open event must be closed and recorded,
        // not left dangling, when the face disappears.
        var s = make()
        feed(s, { now: 100, isOpen: true })
        feed(s, { now: 1100, isOpen: true })                       // confirmed, currentOpenStart = 100
        var ev = feed(s, { now: 2200, dt: 1100, isOpen: true, hasFace: false })
        verify(ev.indexOf("closed") >= 0)
        compare(s.mouthOpen, false)
        compare(s.openEvents.length, 1)
        compare(s.openEvents[0], 2100)                              // 2200 - 100
    }

    function test_no_face_mid_window_leaves_no_trace() {
        // Face lost before confirmation: there was never a confirmed event to
        // close, so nothing is recorded — but the raw-open run must still
        // reset, per the original's invariant.
        var s = make()
        feed(s, { now: 100, isOpen: true })                         // rawOpenSince = 100, unconfirmed
        var ev = feed(s, { now: 400, dt: 300, isOpen: true, hasFace: false })
        compare(ev.length, 0)
        compare(s.mouthOpen, false)
        compare(s.openEvents.length, 0)
        compare(s.rawOpenSince, null)
        compare(s.totalUnmeasuredMs, 300)
    }

    function test_face_returns_after_absence_starts_fresh_window() {
        // Regression check for the "alert fires on the first frame back"
        // bug: once the face returns, even with the mouth still open, a
        // brand-new detection window must start — no immediate alert.
        var s = make()
        feed(s, { now: 100, isOpen: true })
        feed(s, { now: 1100, isOpen: true })                        // confirmed + alert
        feed(s, { now: 2200, dt: 1100, isOpen: true, hasFace: false }) // face lost while open -> closes
        var ev = feed(s, { now: 2300, dt: 100, isOpen: true })
        compare(ev.indexOf("alert"), -1)
        compare(ev.indexOf("confirmed"), -1)
        compare(s.mouthOpen, false)
        compare(s.rawOpenSince, 2300)
    }

    function test_finish_flushes_open_event() {
        // The realistic Stop: a steady ~10Hz cadence with HONEST dt
        // throughout (dt === 100 === the actual now advance, every tick),
        // then finish() called promptly -- well within one tick's dt of the
        // last observed tick, exactly as it would be if the user just clicks
        // Stop right after the last frame instead of the next one arriving.
        // Nothing meaningful went unobserved, so the bound must not clip
        // anything: full credit up to the finish() moment is expected.
        var s = make()
        var now
        // Ramp up to confirmation: now = 100, 200, ..., 1100 (11 ticks at
        // 100ms). Confirms on the now=1100 tick: openDur = 1100 - 100 (=
        // rawOpenSince) = 1000 >= delay(1000). currentOpenStart becomes 100.
        for (now = 100; now <= 1100; now += 100) {
            feed(s, { now: now, dt: 100, isOpen: true })
        }
        compare(s.mouthOpen, true)
        // Mouth stays open a little longer, still honest 10Hz cadence.
        feed(s, { now: 1200, dt: 100, isOpen: true })
        feed(s, { now: 1300, dt: 100, isOpen: true })                // previousNow=1300, previousDt=100
        // Stop is pressed 50ms after the last tick -- well before the next
        // tick (which would have arrived at ~1400) was due.
        var ev = SM.finish(s, 1350)
        // Derivation: bound = min(candidateNow, previousNow + previousDt)
        //           = min(1350, 1300 + 100) = min(1350, 1400) = 1350
        //           (the candidate itself -- nothing was clipped)
        // duration  = bound - currentOpenStart = 1350 - 100 = 1250
        verify(ev.indexOf("closed") >= 0)
        compare(s.mouthOpen, false)
        compare(s.openEvents.length, 1)
        compare(s.openEvents[0], 1250)
    }

    function test_finish_after_a_gap_is_bounded() {
        // The pause-then-Stop: the session locks (or goes idle) while the
        // mouth is open, ticks stop entirely, and the user comes back much
        // later and clicks Stop. finish() must not credit the ~10 minute
        // gap as mouth-open time -- that is the original bug wearing a
        // smaller number (auto-pause turning a lock period into a
        // fabricated open event).
        var s = make()
        var now
        for (now = 100; now <= 1100; now += 100) {
            feed(s, { now: now, dt: 100, isOpen: true })            // confirms at now=1100, currentOpenStart=100
        }
        feed(s, { now: 1200, dt: 100, isOpen: true })
        feed(s, { now: 1300, dt: 100, isOpen: true })                // previousNow=1300, previousDt=100 -- last tick before the lock
        // Screen locks here. No further ticks for ~10 minutes, then the
        // user returns and clicks Stop.
        var ev = SM.finish(s, 1300 + 600000)
        // Derivation: bound = min(candidateNow, previousNow + previousDt)
        //           = min(601300, 1300 + 100) = min(601300, 1400) = 1400
        // duration  = bound - currentOpenStart = 1400 - 100 = 1300
        // (NOT ~601200, which is what crediting the whole lock period would give)
        verify(ev.indexOf("closed") >= 0)
        compare(s.mouthOpen, false)
        compare(s.openEvents.length, 1)
        compare(s.openEvents[0], 1300)
    }

    function test_finish_is_noop_when_nothing_open() {
        var s = make()
        feed(s, { now: 100, isOpen: false })
        var ev = SM.finish(s, 200)
        compare(ev.length, 0)
        compare(s.openEvents.length, 0)
    }

    // --- Fix round 3: auto-pause hardening (bound event ends to what was
    // actually observed, regardless of caller discipline) ---

    function test_pause_then_close_bounds_the_event_to_last_observation() {
        // Ticks stop entirely for ~10 minutes (auto-pause: session locked or
        // went idle), then a single tick arrives with the wall clock jumped
        // but dt reporting only one normal frame. The recorded event must be
        // bounded to roughly one tick past the last real observation, not
        // the full ~601000ms gap.
        var s = make()
        feed(s, { now: 100, isOpen: true })
        feed(s, { now: 1100, isOpen: true })                 // confirmed, currentOpenStart = 100
        var ev = feed(s, { now: 601100, dt: 100, isOpen: false })
        verify(ev.indexOf("closed") >= 0)
        compare(s.mouthOpen, false)
        compare(s.openEvents.length, 1)
        compare(s.openEvents[0], 1100)                        // bounded: (1100 + 100) - 100
        // The recorded event reconciles with the time actually accounted as
        // open — not the ~601000ms the raw clock jump would otherwise imply.
        compare(s.totalOpenMs, s.openEvents[0])
    }

    function test_pause_then_still_open_grants_no_retroactive_credit() {
        // Same pause shape, but the resume tick reports the mouth still
        // open: nothing closes, so only the honestly-reported dt may be
        // credited — not the ~10 minute gap.
        var s = make()
        feed(s, { now: 100, isOpen: true })
        feed(s, { now: 1100, isOpen: true })                 // confirmed, alert 1
        var openMsBeforeGap = s.totalOpenMs
        var ev = feed(s, { now: 601100, dt: 100, isOpen: true })
        compare(s.mouthOpen, true)
        compare(s.openEvents.length, 0)
        compare(s.totalOpenMs, openMsBeforeGap + 100)
        verify(ev.indexOf("alert") >= 0)                      // resume still re-arms normally
    }

    function test_finish_after_pause_is_bounded() {
        // finish() called after the same gap, with no further tick reporting
        // it, must be bounded using the last tick's own stored (now, dt).
        var s = make()
        feed(s, { now: 100, isOpen: true })
        feed(s, { now: 1100, isOpen: true })                 // confirmed, currentOpenStart = 100
        var ev = SM.finish(s, 601100)
        verify(ev.indexOf("closed") >= 0)
        compare(s.openEvents.length, 1)
        compare(s.openEvents[0], 1100)                        // bounded: (1100 + 100) - 100
    }

    function test_honest_long_dt_tick_is_not_clamped() {
        // A single genuinely long-but-honest tick — dt truthfully equal to
        // now - previousNow — must NOT be penalised. This is what
        // distinguishes "bound the damage from a lying caller" from "clamp
        // everything": the bound must be inert when the contract is honoured
        // even for a very large, honest dt.
        var s = make()
        feed(s, { now: 100, isOpen: true })
        feed(s, { now: 1100, isOpen: true })                 // confirmed, currentOpenStart = 100
        var ev = feed(s, { now: 601100, dt: 600000, isOpen: false })  // 601100 - 1100 === 600000, honest
        verify(ev.indexOf("closed") >= 0)
        compare(s.openEvents.length, 1)
        compare(s.openEvents[0], 601000)                      // full honest duration, not clamped
        compare(s.totalOpenMs, 601000)
    }
}
