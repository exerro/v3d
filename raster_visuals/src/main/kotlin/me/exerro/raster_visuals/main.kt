package me.exerro.raster_visuals

import me.exerro.colour.Colour
import me.exerro.colour.ColourPalette
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

/** State of the program. */
data class State(
    /** First of 3 points forming the primary triangle. */
    val p0: P2D,
    /** Second of 3 points forming the primary triangle. */
    val p1: P2D,
    /** Third of 3 points forming the primary triangle. */
    val p2: P2D,
    /**
     * ~2D array of colours forming the "pixels" of the virtual screen.
     * Indexed using `y * SCREEN_WIDTH + x`.
     */
    val buffer: List<Colour>,
    /** Whether the mouse is currently held (e.g. being dragged). */
    val mouseHeld: Boolean = false,
    /** Position of the mouse cursor. */
    val mouse: P2D = P2D(0f, 0f),
) {
    val mouseX = mouse.x
    val mouseY = mouse.y
}

////////////////////////////////////////////////////////////////

/** 2D point class. */
data class P2D(val x: Float, val y: Float)

////////////////////////////////////////////////////////////////////////////////

/**
 * Turn a position from screen space (0 ..< screen size) to window space
 * (0 ..< window size)
 */
fun screenToWindowLocation(p: P2D) = P2D(
    x = p.x * PIXELS_PER_TILE + SCREEN_TILE_X0 * PIXELS_PER_TILE,
    y = p.y * PIXELS_PER_TILE + SCREEN_TILE_Y0 * PIXELS_PER_TILE,
)

/** Inverse of [screenToWindowLocation] */
fun windowToScreenLocation(p: P2D) = P2D(
    x = (p.x - SCREEN_TILE_X0 * PIXELS_PER_TILE) / PIXELS_PER_TILE,
    y = (p.y - SCREEN_TILE_Y0 * PIXELS_PER_TILE) / PIXELS_PER_TILE,
)

/**
 * Return whether two points are close. Used to check if the mouse is hovering
 * on/dragging a point.
 */
fun isNearPoint(m: P2D, p: P2D): Boolean =
    abs(m.x - p.x) < 12f && abs(m.y - p.y) < 12f

////////////////////////////////////////////////////////////////////////////////

/**
 * Holds the graphics object used for drawing things, e.g. lines and rectangles.
 */
class Graphics private constructor(
    val shader: GLShaderProgram,
    val colourUniform: GLUniformLocation,
    val vao: GLVertexArray,
    val buffer: GLBuffer,
) {
    companion object {
        /** Create a [Graphics] object in the current context and lifetime. */
        context (GLContext, Lifetime)
        fun create(): Graphics {
            val (shader) = createShaderProgram(VERTEX_SHADER, FRAGMENT_SHADER)
            val colourUniform = glGetUniformLocation(shader, "u_colour")

            val (vao) = glGenVertexArrays()
            val (buffer) = glCreateBuffers()

            glNamedBufferData(buffer, floatArrayOf(), GLBufferUsage.GL_STREAM_DRAW)

            glBindVertexArray(vao) {
                glBindBuffer(GL_ARRAY_BUFFER, buffer) {
                    glVertexAttribPointer(0, 2, GL_FLOAT)
                }
            }

            glEnableVertexAttribArray(vao, 0)

            return Graphics(shader, colourUniform, vao, buffer)
        }
    }
}

////////////////////////////////////////////////////////////////

/**
 * Vertex shader taking 2D vertex positions and simply passing those as
 * `gl_Position`. Used by all the graphics.
 */
const val VERTEX_SHADER = """
#version 140

in vec2 v_pos;

void main() {
    gl_Position = vec4(v_pos, 0, 1);
}
"""

/** Fragment shader writing the uniform colour `u_colour` to its output. */
const val FRAGMENT_SHADER = """
#version 140

uniform vec4 u_colour;

out vec4 f_colour;

void main() {
    f_colour = u_colour;
}
"""

////////////////////////////////////////////////////////////////

/** Draw a square with the given position (top left corner), size, and colour. */
context (GLContext)
fun drawSquarePS(graphics: Graphics, position: P2D, size: Float, colour: Colour) {
    val x0 = position.x / WINDOW_WIDTH * 2 - 1
    val y0 = position.y / WINDOW_HEIGHT * -2 + 1
    val x1 = (position.x + size - 1) / WINDOW_WIDTH * 2 - 1
    val y1 = (position.y + size - 1) / WINDOW_HEIGHT * -2 + 1
    val bufferData = floatArrayOf(x0, y0, x1, y0, x1, y1, x0, y0, x1, y1, x0, y1)
    glProgramUniform4f(graphics.shader, graphics.colourUniform, colour.red, colour.green, colour.blue, colour.alpha)
    glNamedBufferData(graphics.buffer, bufferData, GLBufferUsage.GL_STREAM_DRAW)
    glDrawArrays(count = 6)
}

/** Draw a square with the given centre position, size, and colour. */
context (GLContext)
fun drawSquareCS(graphics: Graphics, centre: P2D, size: Float, colour: Colour) {
    return drawSquarePS(graphics, P2D(x = centre.x - size / 2, y = centre.y - size / 2), size, colour)
}

/** Draw a line between two points with the given thickness and colour. */
context (GLContext)
fun drawLine(graphics: Graphics, p0: P2D, p1: P2D, thickness: Float, colour: Colour) {
    val dx = p1.x - p0.x
    val dy = p1.y - p0.y
    val tx = dx / sqrt(dx * dx + dy * dy) / 2 * thickness
    val ty = dy / sqrt(dx * dx + dy * dy) / 2 * thickness
    val nx = ty
    val ny = -tx

    val windowPoints = floatArrayOf(
        p0.x + nx - tx, p0.y + ny - ty,
        p0.x - nx - tx, p0.y - ny - ty,
        p1.x + nx + tx, p1.y + ny + ty,
        p0.x - nx - tx, p0.y - ny - ty,
        p1.x + nx + tx, p1.y + ny + ty,
        p1.x - nx + tx, p1.y - ny + ty,
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

/**
 * Draw the entire application's graphics state.
 * Note, we're using the graphics shader and VAO automatically.
 */
context (GLContext)
fun draw(graphics: Graphics, state: State) {
    val p0w = screenToWindowLocation(state.p0)
    val p1w = screenToWindowLocation(state.p1)
    val p2w = screenToWindowLocation(state.p2)

    for (y in 0 until SCREEN_HEIGHT) {
        for (x in 0 until SCREEN_WIDTH) {
            val p = P2D(x.toFloat(), y.toFloat())
            val tl = screenToWindowLocation(p)
            val index = y * SCREEN_WIDTH + x
            val isDarkened = y % 2 == x % 2
            val colour = when {
                isDarkened -> state.buffer[index]
                else -> state.buffer[index].lighten(amount = 0.04f)
            }
            drawSquarePS(graphics, tl, PIXELS_PER_TILE.toFloat(), colour)
        }
    }

    drawLine(graphics, p0w, p1w, 2f, ColourPalette.foreground3)
    drawLine(graphics, p2w, p1w, 2f, ColourPalette.foreground3)
    drawLine(graphics, p0w, p2w, 2f, ColourPalette.foreground3)

    for ((p, c) in listOf(
        p0w to ColourPalette.red,
        p1w to ColourPalette.green,
        p2w to ColourPalette.blue,
    )) {
        if (isNearPoint(state.mouse, p))
            drawSquareCS(graphics, p, 24f, c.lighten())

        drawSquareCS(graphics, p, 16f, c)
    }
}

////////////////////////////////////////////////////////////////////////////////

/** Rasterize the state's triangle into its buffer. */
fun State.rasterize(): State {
    val buffer = MutableList<Colour>(SCREEN_WIDTH * SCREEN_HEIGHT) {
        SCREEN_BACKGROUND_COLOUR_INACTIVE
    }

    fun setPixel(x: Int, y: Int, colour: Colour = SCREEN_BACKGROUND_COLOUR_ACTIVE) {
        if (x < 0 || y < 0 || x >= SCREEN_WIDTH || y >= SCREEN_HEIGHT) {
            error("Ohshit we drew out of bounds $x $y")
        }
        buffer[y * SCREEN_WIDTH + x] = colour
    }

    rasterizeTriangle(p0, p1, p2, ColourPalette.purple, ColourPalette.teal, ::setPixel)
    rasterizeTriangle(p1, p2, P2D(p1.x * 2 - p0.x, p1.y * 2 - p0.y), ColourPalette.orange, ColourPalette.yellow, ::setPixel)

    return copy(buffer = buffer)
}

////////////////////////////////////////////////////////////////

/**
 * Move a point that has been dragged to the new mouse location.
 */
fun State.handleMouseDrag(mouse0: P2D, mouse1: P2D) = when {
    isNearPoint(mouse0, screenToWindowLocation(p0)) -> {
        copy(p0 = windowToScreenLocation(mouse1)).rasterize()
    }
    isNearPoint(mouse0, screenToWindowLocation(p1)) -> {
        copy(p1 = windowToScreenLocation(mouse1)).rasterize()
    }
    isNearPoint(mouse0, screenToWindowLocation(p2)) -> {
        copy(p2 = windowToScreenLocation(mouse1)).rasterize()
    }
    else -> this
}

////////////////////////////////////////////////////////////////////////////////

/** Main function/loop. */
fun main() {
    GLFW.glfwInit()

    var state = State(
        p0 = P2D(x = SCREEN_WIDTH * 0.2f, y = SCREEN_HEIGHT * 0.1f),
        p1 = P2D(x = 25.5f, y = SCREEN_HEIGHT * 0.9f),
        p2 = P2D(x = 25.5f, y = SCREEN_HEIGHT * 0.1f),
        buffer = List(SCREEN_WIDTH * SCREEN_HEIGHT) { SCREEN_BACKGROUND_COLOUR_INACTIVE },
    ).rasterize()

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

        worker.runLater {
            glEnable(GL_MULTISAMPLE)
            glClearColor(WINDOW_BACKGROUND_COLOUR.red, WINDOW_BACKGROUND_COLOUR.green, WINDOW_BACKGROUND_COLOUR.blue)
            glUseProgram(graphics.shader)
            glBindVertexArray(graphics.vao)
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
            val p = P2D(x = rx.toFloat(), y = ry.toFloat())

            if (state.mouseHeld)
                try {
                    state = state.handleMouseDrag(state.mouse, p)
                }
                catch (e: Exception) {
                    e.printStackTrace()
                }

            state = state.copy(mouse = p)
        }

        while (!GLFW.glfwWindowShouldClose(windowId)) {
            GLFW.glfwWaitEvents()
        }

        renderLoopHandle.stopBlocking()
    }
}
