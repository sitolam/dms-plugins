.pragma library

// Pure scaling/mapping math for GapChart.qml's onPaint, split out so it can
// be unit-tested with qmltestrunner without needing qs.Common (Theme) on
// the import path -- see tests/tst_gapchart_math.qml. No QML types, no
// Theme, no Canvas: plain arguments in, plain numbers out.

// Vertical scale for the chart: the taller of the threshold and the
// in-window data, so the threshold line is always on screen even when the
// mouth never opens (the common case). Only points inside the window
// [t0, t0+windowMs] count toward the max -- an old spike that has already
// scrolled off must not keep squashing the trace that is still visible.
// A 5% headroom pad is applied on top so a sample sitting exactly at the
// observed max doesn't render flush against the very top edge of the
// canvas.
function computeMaxGap(points, threshold, windowMs, t0) {
    let maxGap = threshold * 1.4
    for (let i = 0; i < points.length; i++) {
        const p = points[i]
        if (p.t < t0)
            continue
        if (p.gap > maxGap)
            maxGap = p.gap
    }
    return maxGap * 1.05
}

// Horizontal position of timestamp `t` within a window of `windowMs`
// starting at `t0`, mapped onto [0, width].
function xOf(t, t0, windowMs, width) {
    return (t - t0) / windowMs * width
}

// Vertical position of gap value `g` given the scale `maxGap`, mapped onto
// [0, height] with 0 (larger gap / more open) at the top.
function yOf(g, maxGap, height) {
    return height - (g / maxGap) * height
}
