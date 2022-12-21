package me.exerro.raster_visuals

import me.exerro.colour.Colour

import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

fun rasterizeTriangle(
    p0: P2D, p1: P2D, p2: P2D,
    c1: Colour, c2: Colour,
    setPixel: (Int, Int, Colour) -> Unit,
) {
    // First, we sort the points vertically so that points[0] is above points[1]
    // and points[1] is above points[2].
    // Ties don't matter, as commented on later on...
    val points = listOf(p0, p1, p2).sortedBy { it.y }

    // Next, find the X coordinate of the point along the longest vertical edge
    // of the triangle such that its Y value equals the middle point.
    //
    // The goal is that we end up with two sub-triangles - one from the top
    // point to the two flat midpoints (left and right), and one from those flat
    // midpoints to the bottom point.
    //
    //  P.
    //   .....
    //    .   ....
    //     O ───── P
    //      ..   .
    //        ...
    //         P
    val f = (points[1].y - points[0].y) / (points[2].y - points[0].y)
    val pMx = points[0].x * (1 - f) + points[2].x * f
    // Note, we have a potential division by 0 here ^
    // For the same reason ties don't matter, this is fine. Read on...
    // Just remember that pMx might be infinity.

    // Now we define these points explicitly.
    // * `pMin` is the top point
    // * `pMidLeft` is the leftmost middle point
    // * `pMidRight` is the rightmost middle point
    // * `pMax` is the bottom point
    val swapSides = pMx < points[1].x
    val pMin = points[0]
    val pMidLeft = if (swapSides) P2D(pMx, points[1].y) else points[1]
    val pMidRight = if (swapSides) points[1] else P2D(pMx, points[1].y)
    // Note, from above, pMidLeft and pMidRight may have an infinity X value.
    val pMax = points[2]

    // The next step is to find non-overlapping ranges of Y values (rows) where
    // we will be drawing pixels. We want two ranges: for the top half of the
    // triangle, and for the bottom. It's important that they don't overlap so
    // that the middle row is "owned" by only one half, top or bottom.

    // The equation for the minimum top-half row handles
    // * Out of bounds (off-screen) clipping
    // * Y_fractional < 0.5 :: this includes the first row as expected
    val rowTopMin = max(0f, floor(pMin.y + 0.5f))

    // Utility variable used in the next two equations.
    val midYFloored = floor(points[1].y + 0.5f)
    // Note, we use points[1] here to avoid the potential inf from pMx

    // The equation for the maximum top-half row handles
    // * Out of bounds (off-screen) clipping
    // * Y_fractional < 0.5 :: this delegates the middle row to the bottom half
    val rowTopMax = min(SCREEN_HEIGHT - 1f, midYFloored - 1)

    // The equation for the minimum bottom-half row is always one below the
    // maximum row of the top-half subject to clipping
    val rowBottomMin = max(0f, midYFloored)

    // The equation for the maximum bottom-half row handles
    // * Out of bounds (off-screen) clipping
    // * Y_fractional <= 0.5 :: this discards the last row as expected
    val rowBottomMax = min(SCREEN_HEIGHT - 1f, ceil(pMax.y - 0.5f))

    // At this point, we know two non-overlapping ranges of integral Y values
    // (rows) where pixels will be drawn, as well as three corresponding
    // non-integral points (two of which share a Y value and are ordered
    // left/right).

    // I've realised that it does actually matter if we try to draw a flat
    // triangle, dammit. It's rare enough that I don't care though.

    // Now, we have two very similar algorithms for the top and bottom half. The
    // overall idea is that we start of with a left and right X value from the
    // first row, draw between the integral version of that, and then increment
    // each value by some gradient.
    // We care about the centre of the pixel, so we need to find "how much the
    // left/right X value changes as we go down by 1 pixel" as well as "what's
    // the left/right X value halfway through the first row".

    // Finding the gradient for left/right is easy - divide the difference in X
    // by the difference in Y.
    val topDeltaY = pMidLeft.y - pMin.y
    val topLeftGradient = (pMidLeft.x - pMin.x) / topDeltaY
    val topRightGradient = (pMidRight.x - pMin.x) / topDeltaY

    // Now, we need to find the initial left/right X values halfway through the
    // first row. We take the top point's X value and move along the
    // corresponding edge by the difference between the row Y value + 0.5
    // (halfway through the row) and its actual Y value. Note, this would result
    // in negative oddities if it weren't for the constraints imposed by the row
    // calculations above.
    val topProjection = rowTopMin + 0.5f - pMin.y
    var topLeftX = pMin.x + topLeftGradient * topProjection
    var topRightX = pMin.x + topRightGradient * topProjection

    // Now, for each row we're drawing to, we can calculate the pixel columns
    // for each edge.
    for (y in rowTopMin.toInt() .. rowTopMax.toInt()) {
        // We set this up so that left pixels exactly on 0.5 will not be
        // included in the rightmost edge, allowing triangles to have the same
        // vertical edge without overdrawing pixels on top of one another.
        val columnMin = max(0f, ceil(topLeftX - 0.5f))
        val columnMax = min(SCREEN_WIDTH - 1f, ceil(topRightX - 0.5f) - 1)

        for (x in columnMin.toInt() .. columnMax.toInt()) {
            setPixel(x, y, c1)
        }

        topLeftX += topLeftGradient
        topRightX += topRightGradient
    }

    // Now, the same for the bottom half.
    val bottomDeltaY = pMax.y - pMidLeft.y
    val bottomLeftGradient = (pMax.x - pMidLeft.x) / bottomDeltaY
    val bottomRightGradient = (pMax.x - pMidRight.x) / bottomDeltaY

    // The difference here is that we're starting the edges at far ends, rather
    // than originating from the same point, so we adjust the equation
    // accordingly.
    val bottomProjection = rowBottomMin + 0.5f - pMidLeft.y
    var bottomLeftX = pMidLeft.x + bottomLeftGradient * bottomProjection
    var bottomRightX = pMidRight.x + bottomRightGradient * bottomProjection

    for (y in rowBottomMin.toInt() .. rowBottomMax.toInt()) {
        val columnMin = max(0f, ceil(bottomLeftX - 0.5f))
        val columnMax = min(SCREEN_WIDTH - 1f, ceil(bottomRightX - 0.5f) - 1)

        for (x in columnMin.toInt() .. columnMax.toInt()) {
            setPixel(x, y, c1)
        }

        bottomLeftX += bottomLeftGradient
        bottomRightX += bottomRightGradient
    }
}
