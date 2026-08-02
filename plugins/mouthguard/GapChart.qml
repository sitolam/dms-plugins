import QtQuick
import qs.Common

// Scrolling plot of the measured lip gap against the alert threshold.
// `points` is replaced wholesale by the daemon several times a second
// (gapHistory), so onPaint must stay cheap: no per-point allocations,
// two flat passes over the array, nothing retained between frames.
Canvas {
    id: root

    property var points: []
    property real threshold: 0
    property int windowMs: 60000

    onPointsChanged: requestPaint()
    onThresholdChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        ctx.clearRect(0, 0, width, height)

        if (!points || points.length === 0)
            return

        const now = points[points.length - 1].t
        const t0 = now - windowMs

        // Scale to the taller of the threshold and the in-window data, so
        // the threshold line is always on screen even when the mouth never
        // opens (the common case). Only points inside the window count
        // toward the max -- an old spike that has already scrolled off
        // must not keep squashing the trace that is still visible.
        let maxGap = threshold * 1.4
        for (let i = 0; i < points.length; i++) {
            const p = points[i]
            if (p.t < t0)
                continue
            if (p.gap > maxGap)
                maxGap = p.gap
        }
        // Degenerate scale (threshold <= 0 and nothing in-window above it):
        // bail rather than divide by zero. A legitimate gap of 0.0 (mouth
        // fully closed) does not trigger this -- maxGap is floored by the
        // threshold term above whenever threshold > 0.
        if (maxGap <= 0)
            return

        const xOf = t => (t - t0) / windowMs * width
        const yOf = g => height - (g / maxGap) * height

        // Threshold reference line.
        ctx.save()
        ctx.setLineDash([4, 4])
        ctx.strokeStyle = Theme.error
        ctx.lineWidth = 1
        ctx.beginPath()
        ctx.moveTo(0, yOf(threshold))
        ctx.lineTo(width, yOf(threshold))
        ctx.stroke()
        ctx.restore()

        // Gap trace. Points older than windowMs are skipped outright, not
        // compressed into the visible range. A single surviving sample
        // can't form a line segment, so it is drawn as a dot instead of
        // silently vanishing.
        ctx.strokeStyle = Theme.primary
        ctx.fillStyle = Theme.primary
        ctx.lineWidth = 2
        ctx.beginPath()
        let count = 0
        let lastX = 0
        let lastY = 0
        for (let i = 0; i < points.length; i++) {
            const p = points[i]
            if (p.t < t0)
                continue
            const x = xOf(p.t)
            const y = yOf(p.gap)
            if (count === 0)
                ctx.moveTo(x, y)
            else
                ctx.lineTo(x, y)
            lastX = x
            lastY = y
            count++
        }
        if (count > 1) {
            ctx.stroke()
        } else if (count === 1) {
            ctx.beginPath()
            ctx.arc(lastX, lastY, ctx.lineWidth, 0, Math.PI * 2)
            ctx.fill()
        }
    }
}
