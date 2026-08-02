import QtQuick
import QtTest

// GapChart.qml is a plain Canvas that imports qs.Common (for Theme), which
// is only resolvable inside a running DMS shell -- it is not on this repo's
// dev-shell QML_IMPORT_PATH (see flake.nix), so it cannot be instantiated
// here. This file re-implements, byte-for-byte, the pure scaling/mapping
// math from GapChart.qml's onPaint (maxGap floor + in-window max, xOf,
// yOf, and the maxGap<=0 bailout) so that arithmetic can be checked without
// a display. Keep this in sync with GapChart.qml if that math changes.
TestCase {
    name: "GapChartMath"

    // Mirrors GapChart.qml onPaint exactly, up to the point of issuing
    // canvas draw calls. Returns null if painting would bail out (empty
    // points or degenerate scale), otherwise the computed maxGap, the
    // threshold's y position, and the {x, y} of every in-window point in
    // the same order onPaint would draw them.
    function computeChart(points, threshold, windowMs, width, height) {
        if (!points || points.length === 0)
            return null

        const now = points[points.length - 1].t
        const t0 = now - windowMs

        let maxGap = threshold * 1.4
        for (let i = 0; i < points.length; i++) {
            const p = points[i]
            if (p.t < t0)
                continue
            if (p.gap > maxGap)
                maxGap = p.gap
        }
        if (maxGap <= 0)
            return null

        const xOf = t => (t - t0) / windowMs * width
        const yOf = g => height - (g / maxGap) * height

        const trace = []
        for (let i = 0; i < points.length; i++) {
            const p = points[i]
            if (p.t < t0)
                continue
            trace.push({ x: xOf(p.t), y: yOf(p.gap) })
        }

        return { maxGap: maxGap, thresholdY: yOf(threshold), trace: trace }
    }

    property real threshold: 3.5
    property int windowMs: 60000
    property real w: 300
    property real h: 100

    function test_empty_array_bails_out() {
        const r = computeChart([], threshold, windowMs, w, h)
        compare(r, null)
    }

    function test_degenerate_scale_bails_out() {
        // threshold 0 and every point <= 0: maxGap would be 0, must bail
        // rather than divide by zero.
        const r = computeChart([{ t: 0, gap: 0.0 }, { t: 100, gap: 0.0 }], 0.0, windowMs, w, h)
        compare(r, null)
    }

    function test_single_point_still_shows_threshold_line() {
        const r = computeChart([{ t: 1000, gap: 2.0 }], threshold, windowMs, w, h)
        verify(r !== null)
        compare(r.trace.length, 1)
        // threshold*1.4 floor == 4.9, threshold/maxGap == 3.5/4.9 -> 71.4% up
        fuzzyCompare(r.maxGap, 4.9, 0.001)
        fuzzyCompare(r.thresholdY / h, 1 - 3.5 / 4.9, 0.001)
    }

    function test_all_zero_points_do_not_divide_by_zero_and_threshold_is_visible() {
        const pts = []
        for (let i = 0; i < 10; i++)
            pts.push({ t: i * 200, gap: 0.0 })
        const r = computeChart(pts, threshold, windowMs, w, h)
        verify(r !== null)
        fuzzyCompare(r.maxGap, 4.9, 0.001)
        // All points sit at the bottom edge, threshold clearly above them.
        for (let i = 0; i < r.trace.length; i++)
            fuzzyCompare(r.trace[i].y, h, 0.001)
        verify(r.thresholdY < h)
    }

    function test_closed_mouth_band_stays_below_the_floor_scale() {
        // Real calibrated closed-mouth band: median 2.0, range 0-4.1.
        const band = [0.0, 1.2, 2.0, 2.0, 2.5, 3.1, 4.1, 1.8, 2.2, 0.5]
        const pts = band.map((g, i) => ({ t: i * 200, gap: g }))
        const r = computeChart(pts, threshold, windowMs, w, h)
        verify(r !== null)
        // Max sample (4.1) is under the 4.9 floor, so the floor -- not the
        // data -- sets the scale.
        fuzzyCompare(r.maxGap, 4.9, 0.001)
        fuzzyCompare(r.thresholdY / h, 1 - 3.5 / 4.9, 0.001)
    }

    function test_points_straddling_threshold_rescale_to_observed_max() {
        // Real calibrated ajar band: median 4.0, range 2.9-5.0. Top of the
        // band (5.0) exceeds the 4.9 floor, so maxGap should track it.
        const band = [2.9, 3.4, 3.5, 3.6, 4.0, 4.0, 4.5, 5.0, 3.2, 3.9]
        const pts = band.map((g, i) => ({ t: i * 200, gap: g }))
        const r = computeChart(pts, threshold, windowMs, w, h)
        verify(r !== null)
        fuzzyCompare(r.maxGap, 5.0, 0.001)
    }

    function test_stale_points_outside_window_are_excluded_from_scale_and_trace() {
        // A large stale spike older than windowMs relative to the latest
        // sample must not inflate maxGap, and must not appear in the trace.
        const pts = [
            { t: 0, gap: 20.0 },
            { t: windowMs + 5000, gap: 2.0 },
            { t: windowMs + 10000, gap: 2.5 }
        ]
        const r = computeChart(pts, threshold, windowMs, w, h)
        verify(r !== null)
        compare(r.trace.length, 2)
        fuzzyCompare(r.maxGap, 4.9, 0.001)
    }

    function test_open_mouth_band_scales_to_observed_max_and_peak_touches_top() {
        // Real calibrated open band: median 6.0, range 4.5-6.4.
        const band = [4.5, 5.0, 5.8, 6.0, 6.0, 6.2, 6.4, 5.5, 6.1, 4.8]
        const pts = band.map((g, i) => ({ t: i * 200, gap: g }))
        const r = computeChart(pts, threshold, windowMs, w, h)
        verify(r !== null)
        fuzzyCompare(r.maxGap, 6.4, 0.001)
        // Threshold stays in the middle of the frame rather than pinned to
        // an edge: 3.5/6.4 -> ~54.7% up.
        fuzzyCompare(r.thresholdY / h, 1 - 3.5 / 6.4, 0.001)
    }
}
