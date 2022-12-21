package me.exerro.raster_visuals

import me.exerro.colour.Colour
import me.exerro.colour.ColourPalette
import me.exerro.colour.RGBA
import me.exerro.eggli.GL
import me.exerro.eggli.GLContext
import me.exerro.eggli.enum.*
import me.exerro.eggli.gl.*
import me.exerro.eggli.types.GLBuffer
import me.exerro.eggli.types.GLShaderProgram
import me.exerro.eggli.types.GLUniformLocation
import me.exerro.eggli.types.GLVertexArray
import me.exerro.egglix.createGLFWRenderLoop
import me.exerro.egglix.createGLFWWindowWithWorker
import me.exerro.egglix.shader.createShaderProgram
import me.exerro.lifetimes.Lifetime
import me.exerro.lifetimes.withLifetime
import org.lwjgl.glfw.GLFW
import kotlin.math.*

const val PIXELS_PER_TILE = 32
const val TILES_X = 50
const val TILES_Y = 30
const val SCREEN_TILE_X0 = 4
const val SCREEN_TILE_X1 = 45
const val SCREEN_TILE_Y0 = 3
const val SCREEN_TILE_Y1 = 26
const val SCREEN_WIDTH = SCREEN_TILE_X1 - SCREEN_TILE_X0 + 1
const val SCREEN_HEIGHT = SCREEN_TILE_Y1 - SCREEN_TILE_Y0 + 1
const val WINDOW_WIDTH = PIXELS_PER_TILE * TILES_X
const val WINDOW_HEIGHT = PIXELS_PER_TILE * TILES_Y

val WINDOW_BACKGROUND_COLOUR = RGBA(0.05f, 0.07f, 0.09f)
val SCREEN_BACKGROUND_COLOUR_INACTIVE = RGBA(0.12f, 0.14f, 0.16f)
val SCREEN_BACKGROUND_COLOUR_ACTIVE = ColourPalette.purple

////////////////////////////////////////////////////////////////////////////////

data class State(
    val p0x: Float,
    val p0y: Float,
    val p1x: Float,
    val p1y: Float,
    val p2x: Float,
    val p2y: Float,
    val buffer: List<Colour>,
    val extraPoints: List<Pair<P2D, Colour>> = emptyList(),
    val mouseHeld: Boolean = false,
    val mouseX: Float = 0f,
    val mouseY: Float = 0f,
) {
    val p0 get() = P2D(p0x, p0y)
    val p1 get() = P2D(p1x, p1y)
    val p2 get() = P2D(p2x, p2y)
}

////////////////////////////////////////////////////////////////

data class P2D(val x: Float, val y: Float)

////////////////////////////////////////////////////////////////////////////////

fun screenToWindowLocation(x: Float, y: Float): Pair<Float, Float> {
    val sx = x * PIXELS_PER_TILE + SCREEN_TILE_X0 * PIXELS_PER_TILE
    val sy = y * PIXELS_PER_TILE + SCREEN_TILE_Y0 * PIXELS_PER_TILE
    return sx to sy
}

fun windowToScreenLocation(x: Float, y: Float): Pair<Float, Float> {
    val wx = (x - SCREEN_TILE_X0 * PIXELS_PER_TILE) / PIXELS_PER_TILE
    val wy = (y - SCREEN_TILE_Y0 * PIXELS_PER_TILE) / PIXELS_PER_TILE
    return wx to wy
}

fun isNearPoint(mx: Float, my: Float, px: Float, py: Float) =
    abs(mx - px) < 12f && abs(my - py) < 12f

////////////////////////////////////////////////////////////////////////////////

class Graphics(
    val shader: GLShaderProgram,
    val colourUniform: GLUniformLocation,
    val vao: GLVertexArray,
    val buffer: GLBuffer,
) {
    companion object {
        context (GLContext, Lifetime)
        fun create(): Graphics {
            val (shader) = createShaderProgram(VERTEX_SHADER, FRAGMENT_SHADER)
            val colourUniform = glGetUniformLocation(shader, "u_colour")

            val (vao) = glGenVertexArrays()
            val (buffer) = glCreateBuffers()

            glNamedBufferData(buffer, floatArrayOf())

            glBindVertexArray(vao) {
                glBindBuffer(GL_ARRAY_BUFFER, buffer) {
                    glVertexAttribPointer(0, 2, GL_FLOAT)
                }
            }

            glEnableVertexAttribArray(vao, 0)

            return Graphics(
                shader = shader,
                colourUniform = colourUniform,
                vao = vao,
                buffer = buffer,
            )
        }
    }
}

////////////////////////////////////////////////////////////////

const val VERTEX_SHADER = """
#version 140

in vec2 v_pos;

void main() {
    gl_Position = vec4(v_pos, 0, 1);
}
"""

const val FRAGMENT_SHADER = """
#version 140

uniform vec4 u_colour;

out vec4 f_colour;

void main() {
    f_colour = u_colour;
}
"""

////////////////////////////////////////////////////////////////

context (GLContext)
fun drawRectPS(graphics: Graphics, x: Float, y: Float, width: Float, height: Float, colour: Colour) {
    val x0 = x / WINDOW_WIDTH * 2 - 1
    val y0 = y / WINDOW_HEIGHT * -2 + 1
    val x1 = (x + width - 1) / WINDOW_WIDTH * 2 - 1
    val y1 = (y + height - 1) / WINDOW_HEIGHT * -2 + 1
    val bufferData = floatArrayOf(x0, y0, x1, y0, x1, y1, x0, y0, x1, y1, x0, y1)
    glProgramUniform4f(graphics.shader, graphics.colourUniform, colour.red, colour.green, colour.blue, colour.alpha)
    glNamedBufferData(graphics.buffer, bufferData, GLBufferUsage.GL_STREAM_DRAW)
    glDrawArrays(count = 6)
}

context (GLContext)
fun drawRectCS(graphics: Graphics, cx: Float, cy: Float, width: Float, height: Float, colour: Colour) {
    return drawRectPS(graphics, cx - width / 2, cy - width / 2, width, height, colour)
}

context (GLContext)
fun drawLine(graphics: Graphics, x0: Float, y0: Float, x1: Float, y1: Float, thickness: Float, colour: Colour) {
    val dx = x1 - x0
    val dy = y1 - y0
    val tx = dx / sqrt(dx * dx + dy * dy) / 2 * thickness
    val ty = dy / sqrt(dx * dx + dy * dy) / 2 * thickness
    val nx = ty
    val ny = -tx

    val windowPoints = floatArrayOf(
        x0 + nx - tx,
        y0 + ny - ty,
        x0 - nx - tx,
        y0 - ny - ty,
        x1 + nx + tx,
        y1 + ny + ty,
        x0 - nx - tx,
        y0 - ny - ty,
        x1 + nx + tx,
        y1 + ny + ty,
        x1 - nx + tx,
        y1 - ny + ty,
    )
    val glPoints = FloatArray(windowPoints.size)

    for (i in windowPoints.indices step 2) {
        glPoints[i] = windowPoints[i] / WINDOW_WIDTH * 2 - 1
        glPoints[i + 1] = windowPoints[i + 1] / WINDOW_HEIGHT * -2 + 1
    }

    glProgramUniform4f(graphics.shader, graphics.colourUniform, colour.red, colour.green, colour.blue, colour.alpha)
    glNamedBufferData(graphics.buffer, glPoints, GLBufferUsage.GL_STREAM_DRAW)
    glDrawArrays(count = 6)
}

////////////////////////////////////////////////////////////////

context (GLContext)
fun draw(graphics: Graphics, state: State) {
    glUseProgram(graphics.shader) {
        glBindVertexArray(graphics.vao) {
            val (p0sx, p0sy) = screenToWindowLocation(state.p0x, state.p0y)
            val (p1sx, p1sy) = screenToWindowLocation(state.p1x, state.p1y)
            val (p2sx, p2sy) = screenToWindowLocation(state.p2x, state.p2y)

            for (y in 0 until SCREEN_HEIGHT) {
                for (x in 0 until SCREEN_WIDTH) {
                    val (tlX, tlY) = screenToWindowLocation(x.toFloat(), y.toFloat())
                    val index = y * SCREEN_WIDTH + x
                    val isDarkened = y % 2 == x % 2
                    val colour = when {
                        isDarkened -> state.buffer[index]
                        else -> state.buffer[index].lighten(amount = 0.04f)
                    }
                    drawRectPS(graphics, tlX, tlY, PIXELS_PER_TILE.toFloat(), PIXELS_PER_TILE.toFloat(), colour)
                }
            }

            drawLine(graphics, p0sx, p0sy, p1sx, p1sy, 2f, ColourPalette.foreground3)
            drawLine(graphics, p2sx, p2sy, p1sx, p1sy, 2f, ColourPalette.foreground3)
            drawLine(graphics, p0sx, p0sy, p2sx, p2sy, 2f, ColourPalette.foreground3)

            for ((px, py, c) in listOf(
                Triple(p0sx, p0sy, ColourPalette.red),
                Triple(p1sx, p1sy, ColourPalette.green),
                Triple(p2sx, p2sy, ColourPalette.blue),
            )) {
                if (isNearPoint(state.mouseX, state.mouseY, px, py))
                    drawRectCS(graphics, px, py, 24f, 24f, c.lighten())
                drawRectCS(graphics, px, py, 16f, 16f, c)
            }

            for ((p, c) in state.extraPoints) {
                val (px, py) = screenToWindowLocation(p.x, p.y)
                drawRectCS(graphics, px, py, 16f, 16f, c)
            }
        }
    }
}

////////////////////////////////////////////////////////////////////////////////

fun rasterizeTriangle(
    p0: P2D, p1: P2D, p2: P2D,
    c1: Colour, c2: Colour,
    setPixel: (Int, Int, Colour) -> Unit,
) {
    val points = listOf(p0, p1, p2).sortedBy { it.y }

    val f = (points[1].y - points[0].y) / (points[2].y - points[0].y)
    val pMx = points[0].x * (1 - f) + points[2].x * f

    val pMin = points[0]
    val pMidLeft = if (pMx < points[1].x) P2D(pMx, points[1].y) else points[1]
    val pMidRight = if (pMx < points[1].x) points[1] else P2D(pMx, points[1].y)
    val pMax = points[2]

    val pMinYF = max(0f, ceil(pMin.y - 0.5f))
    val pMidTopYF = min(SCREEN_HEIGHT - 1f, floor(pMidLeft.y + 0.5f) - 1)
    val pMidBottomYF = max(0f, floor(pMidLeft.y + 0.5f))
    val pMaxYF = min(SCREEN_HEIGHT - 1f, floor(pMax.y + 0.5f))

    val pMinMidLeftDX = (pMidLeft.x - pMin.x) / (pMidLeft.y - pMin.y)
    val pMinMidRightDX = (pMidRight.x - pMin.x) / (pMidRight.y - pMin.y)
    val pMinLeftX0 = pMin.x + pMinMidLeftDX * (pMinYF + 0.5f - pMin.y)
    val pMinRightX0 = pMin.x + pMinMidRightDX * (pMinYF + 0.5f - pMin.y)
    var pMinLeftX = pMinLeftX0
    var pMinRightX = pMinRightX0

    for (y in pMinYF.toInt() .. pMidTopYF.toInt()) {
        for (x in max(0f, ceil(pMinLeftX - 0.5f)).toInt() .. min(SCREEN_WIDTH - 1f, floor(pMinRightX - 0.5f)).toInt()) {
            setPixel(x, y, c1)
        }

        pMinLeftX += pMinMidLeftDX
        pMinRightX += pMinMidRightDX
    }

    val pMidLeftMaxDX = (pMax.x - pMidLeft.x) / (pMax.y - pMidLeft.y)
    val pMidRightMaxDX = (pMax.x - pMidRight.x) / (pMax.y - pMidRight.y)
    val pMaxLeftX0 = pMidLeft.x + pMidLeftMaxDX * (pMidBottomYF + 0.5f - pMidLeft.y)
    val pMaxRightX0 = pMidRight.x + pMidRightMaxDX * (pMidBottomYF + 0.5f - pMidLeft.y)
    var pMaxLeftX = pMaxLeftX0
    var pMaxRightX = pMaxRightX0

    for (y in pMidBottomYF.toInt() .. pMaxYF.toInt()) {
        for (x in max(0f, ceil(pMaxLeftX - 0.5f)).toInt() .. min(SCREEN_WIDTH - 1f, floor(pMaxRightX - 0.5f)).toInt()) {
            setPixel(x, y, c2)
        }

        pMaxLeftX += pMidLeftMaxDX
        pMaxRightX += pMidRightMaxDX
    }
}

fun State.rasterize(): State {
    val buffer = MutableList<Colour>(SCREEN_WIDTH * SCREEN_HEIGHT) {
        SCREEN_BACKGROUND_COLOUR_INACTIVE
    }
    val extraPoints = mutableListOf<Pair<P2D, Colour>>()

    fun setPixel(x: Int, y: Int, colour: Colour = SCREEN_BACKGROUND_COLOUR_ACTIVE) {
        if (x < 0 || y < 0 || x >= SCREEN_WIDTH || y >= SCREEN_HEIGHT) {
            error("Ohshit we drew out of bounds $x $y")
        }
        buffer[y * SCREEN_WIDTH + x] = colour
    }

    rasterizeTriangle(p0, p1, p2, ColourPalette.purple, ColourPalette.teal, ::setPixel)
    rasterizeTriangle(p1, p2, P2D(p1.x * 2 - p0.x, p1.y * 2 - p0.y), ColourPalette.orange, ColourPalette.yellow, ::setPixel)

    return copy(buffer = buffer, extraPoints = extraPoints)
}

////////////////////////////////////////////////////////////////

fun State.handleMouseDrag(x0: Float, y0: Float, x1: Float, y1: Float): State {
    val (p0sx, p0sy) = screenToWindowLocation(p0x, p0y)
    val (p1sx, p1sy) = screenToWindowLocation(p1x, p1y)
    val (p2sx, p2sy) = screenToWindowLocation(p2x, p2y)

    return when {
        isNearPoint(x0, y0, p0sx, p0sy) -> {
            val (x1s, y1s) = windowToScreenLocation(x1, y1)
            copy(p0x = x1s, p0y = y1s).rasterize()
        }
        isNearPoint(x0, y0, p1sx, p1sy) -> {
            val (x1s, y1s) = windowToScreenLocation(x1, y1)
            copy(p1x = x1s, p1y = y1s).rasterize()
        }
        isNearPoint(x0, y0, p2sx, p2sy) -> {
            val (x1s, y1s) = windowToScreenLocation(x1, y1)
            copy(p2x = x1s, p2y = y1s).rasterize()
        }
        else -> this
    }
}

////////////////////////////////////////////////////////////////////////////////

fun main() {
    GLFW.glfwInit()

    withLifetime {
        GLFW.glfwWindowHint(GLFW.GLFW_SAMPLES, 8)

        val (windowId, worker) = createGLFWWindowWithWorker(
            width = WINDOW_WIDTH,
            height = WINDOW_HEIGHT,
            title = "Raster Visuals",
            debug = false,
        )

        val graphics = worker.evaluateBlocking(GL {
            Graphics.create()
        })

        var state = State(
            p0x = SCREEN_WIDTH * 0.2f,
            p0y = SCREEN_HEIGHT * 0.2f,
            p1x = SCREEN_WIDTH * 0.5f,
            p1y = SCREEN_HEIGHT * 0.8f,
            p2x = SCREEN_WIDTH * 0.9f,
            p2y = SCREEN_HEIGHT * 0.3f,
            buffer = List(SCREEN_WIDTH * SCREEN_HEIGHT) { SCREEN_BACKGROUND_COLOUR_INACTIVE },
        ).rasterize()

        worker.runLater {
            glEnable(GL_MULTISAMPLE)
            glClearColor(WINDOW_BACKGROUND_COLOUR.red, WINDOW_BACKGROUND_COLOUR.green, WINDOW_BACKGROUND_COLOUR.blue)
        }

        val renderLoopHandle = createGLFWRenderLoop(windowId, worker) {
            glClear(GL_COLOR_BUFFER_BIT)
            draw(graphics, state)
        }

        GLFW.glfwSetWindowAttrib(windowId, GLFW.GLFW_RESIZABLE, GLFW.GLFW_FALSE)

        GLFW.glfwSetMouseButtonCallback(windowId) { _, _, action, _ ->
            state = state.copy(mouseHeld = action == GLFW.GLFW_PRESS)
        }

        GLFW.glfwSetCursorPosCallback(windowId) { _, rx, ry ->
            val x = rx.toFloat()
            val y = ry.toFloat()

            if (state.mouseHeld)
                try {
                    state = state.handleMouseDrag(state.mouseX, state.mouseY, x, y)
                }
                catch (e: Exception) {
                    e.printStackTrace()
                }

            state = state.copy(mouseX = x, mouseY = y)
        }

        while (!GLFW.glfwWindowShouldClose(windowId)) {
            GLFW.glfwWaitEvents()
        }

        renderLoopHandle.stopBlocking()
    }
}
