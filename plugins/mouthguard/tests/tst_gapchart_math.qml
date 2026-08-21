import QtQuick
import QtTest
import "../GapChartMath.js" as GapChartMath

// GapChart.qml itself imports qs.Common (for Theme), which is only
// resolvable inside a running DMS shell -- it is not on this repo's dev
// shell QML_IMPORT_PATH (see flake.nix), so the Canvas component cannot be
// instantiated here. GapChartMath.js has no such dependency (no QML types,
// no Theme, no Canvas), so this test imports and exercises the exact same
// file GapChart.qml calls from onPaint -- not a copy of it.
TestCase {
    name: "GapChartMath"

    property real threshold: 3.5
    property int windowMs: 60000
    property real w: 300
    property real h: 100

    // Mirrors the shape of GapChart.qml's onPaint driving code (computing
    // t0, calling computeMaxGap/xOf/yOf), but every number comes from the
    // shared module -- editing GapChartMath.js changes what this returns.
    function computeChart(points, thresholdVal, windowMsVal, width, height) {
        if (!points || points.length === 0)
            return null

        const now = points[points.length - 1].t
        const t0 = now - windowMsVal

        const maxGap = GapChartMath.computeMaxGap(points, thresholdVal, windowMsVal, t0)
        if (maxGap <= 0)
            return null

        const trace = []
        for (let i = 0; i < points.length; i++) {
            const p = points[i]
            if (p.t < t0)
                continue
            trace.push({
                x: GapChartMath.xOf(p.t, t0, windowMsVal, width),
                y: GapChartMath.yOf(p.gap, maxGap, height)
            })
        }

        return {
            maxGap: maxGap,
            thresholdY: GapChartMath.yOf(thresholdVal, maxGap, height),
            trace: trace
        }
    }

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
        // floor = threshold*1.4 = 4.9, padded by 1.05 -> maxGap = 5.145.
        // threshold/maxGap = 3.5/5.145 -> 68.0% from bottom.
        fuzzyCompare(r.maxGap, 5.145, 0.001)
        fuzzyCompare(r.thresholdY / h, 1 - 3.5 / 5.145, 0.001)
    }

    function test_all_zero_points_do_not_divide_by_zero_and_threshold_is_visible() {
        const pts = []
        for (let i = 0; i < 10; i++)
            pts.push({ t: i * 200, gap: 0.0 })
        const r = computeChart(pts, threshold, windowMs, w, h)
        verify(r !== null)
        fuzzyCompare(r.maxGap, 5.145, 0.001)
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
        // Max sample (4.1) is under the 4.9 floor, so the padded floor --
        // not the data -- sets the scale: 4.9 * 1.05 = 5.145.
        fuzzyCompare(r.maxGap, 5.145, 0.001)
        fuzzyCompare(r.thresholdY / h, 1 - 3.5 / 5.145, 0.001)
    }

    function test_points_straddling_threshold_rescale_to_observed_max() {
        // Real calibrated ajar band: median 4.0, range 2.9-5.0. Top of the
        // band (5.0) exceeds the 4.9 floor, so maxGap should track it,
        // then get the same 1.05 headroom pad: 5.0 * 1.05 = 5.25.
        const band = [2.9, 3.4, 3.5, 3.6, 4.0, 4.0, 4.5, 5.0, 3.2, 3.9]
        const pts = band.map((g, i) => ({ t: i * 200, gap: g }))
        const r = computeChart(pts, threshold, windowMs, w, h)
        verify(r !== null)
        fuzzyCompare(r.maxGap, 5.25, 0.001)
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
        // In-window max (2.5) is still under the floor, so the padded
        // floor (4.9 * 1.05 = 5.145) sets the scale, not the excluded
        // spike.
        fuzzyCompare(r.maxGap, 5.145, 0.001)
    }

    function test_open_mouth_band_scales_to_observed_max_with_headroom() {
        // Real calibrated open band: median 6.0, range 4.5-6.4.
        const band = [4.5, 5.0, 5.8, 6.0, 6.0, 6.2, 6.4, 5.5, 6.1, 4.8]
        const pts = band.map((g, i) => ({ t: i * 200, gap: g }))
        const r = computeChart(pts, threshold, windowMs, w, h)
        verify(r !== null)
        // Observed max (6.4) exceeds the floor, padded: 6.4 * 1.05 = 6.72.
        fuzzyCompare(r.maxGap, 6.72, 0.001)
        // Threshold stays well clear of both edges: 3.5/6.72 -> ~52.1% up.
        fuzzyCompare(r.thresholdY / h, 1 - 3.5 / 6.72, 0.001)
        // The peak sample (6.4, index 6 in `band`) no longer touches the
        // very top edge (y=0): it lands at height*(1 - 6.4/6.72) -- about
        // 4.76% down from the top -- thanks to the headroom pad.
        const peak = r.trace[6]
        verify(peak.y > 0)
        fuzzyCompare(peak.y / h, 1 - 6.4 / 6.72, 0.001)
    }
}
