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
        var s = make()
        feed(s, { now: 100, isOpen: true })
        feed(s, { now: 1100, isOpen: true })
        var ev = feed(s, { now: 3100, isOpen: false })
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
    }

    function test_zero_delay_confirms_immediately() {
        var s = make()
        var ev = feed(s, { now: 100, isOpen: true, delay: 0 })
        compare(s.mouthOpen, true)
        verify(ev.indexOf("alert") >= 0)
    }
}
